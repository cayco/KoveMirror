import Foundation
import Network
import Combine

public final class KoveDashClient: ObservableObject {
    @Published public private(set) var isControlConnected = false
    @Published public private(set) var isVideoConnected = false
    @Published public private(set) var isHeartbeatConnected = false
    @Published public private(set) var isConnected = false
    @Published public private(set) var isSearching = false
    
    @Published public private(set) var totalBytesReceived: Int64 = 0
    @Published public private(set) var headerWidth: UInt16 = 0
    @Published public private(set) var headerHeight: UInt16 = 0
    @Published public private(set) var clientName: String = ""
    @Published public private(set) var targetHost: String = ""
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var heartbeatConnection: NWConnection?
    
    public let decoder = H264Decoder()
    private var videoHeaderParsed = false
    private var discoveryConnections: [NWConnection] = []
    
    public init() {}
    
    // MARK: - Auto Subnet Discovery
    
    public func startAutoDiscovery() {
        guard !isSearching else { return }
        disconnect()
        
        isSearching = true
        Logger.shared.info("🔍 Scanning local Wi-Fi subnet for iPhone running KoveMirror...")
        
        let localIPs = getLocalIPAddresses()
        guard let primaryLocalIP = localIPs.first(where: { !$0.hasPrefix("127.") }) else {
            Logger.shared.warning("⚠️ No local Wi-Fi interface detected. Please check network connection.")
            isSearching = false
            return
        }
        
        let ipComponents = primaryLocalIP.split(separator: ".")
        guard ipComponents.count == 4 else {
            isSearching = false
            return
        }
        
        let subnetPrefix = "\(ipComponents[0]).\(ipComponents[1]).\(ipComponents[2])."
        let group = DispatchGroup()
        
        for lastOctet in 1...254 {
            let candidateIP = "\(subnetPrefix)\(lastOctet)"
            if candidateIP == primaryLocalIP { continue }
            
            group.enter()
            probeHost(candidateIP, port: KoveProtocol.portControl) { [weak self] success in
                guard let self = self else { group.leave(); return }
                if success && self.isSearching {
                    self.isSearching = false
                    Logger.shared.success("🎯 Discovered iPhone KoveMirror at \(candidateIP)! Connecting...")
                    DispatchQueue.main.async {
                        self.connect(to: candidateIP)
                    }
                }
                group.leave()
            }
        }
        
        DispatchQueue.global().async {
            _ = group.wait(timeout: .now() + 3.0)
            DispatchQueue.main.async {
                if self.isSearching {
                    self.isSearching = false
                    Logger.shared.warning("🔍 Subnet scan finished. If iPhone was not found, enter iPhone IP manually in control panel.")
                }
            }
        }
    }
    
    private func probeHost(_ host: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        var hasResponded = false
        
        connection.stateUpdateHandler = { state in
            guard !hasResponded else { return }
            switch state {
            case .ready:
                hasResponded = true
                connection.cancel()
                completion(true)
            case .failed, .cancelled:
                hasResponded = true
                connection.cancel()
                completion(false)
            default:
                break
            }
        }
        
        connection.start(queue: .global())
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if !hasResponded {
                hasResponded = true
                connection.cancel()
                completion(false)
            }
        }
    }
    
    private func getLocalIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            
            if (flags & (IFF_UP | IFF_RUNNING)) != 0, addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: hostname)
                    addresses.append(address)
                }
            }
        }
        freeifaddrs(ifaddr)
        return addresses
    }
    
    // MARK: - Connection Management
    
    public func connect(to host: String) {
        disconnect()
        self.targetHost = host
        Logger.shared.info("🔌 Connecting to Kove Mirror Server at \(host)...")
        
        connectControl(host: host)
        connectVideo(host: host)
        connectHeartbeat(host: host)
    }
    
    public func disconnect() {
        isSearching = false
        controlConnection?.cancel()
        videoConnection?.cancel()
        heartbeatConnection?.cancel()
        
        controlConnection = nil
        videoConnection = nil
        heartbeatConnection = nil
        
        isControlConnected = false
        isVideoConnected = false
        isHeartbeatConnected = false
        isConnected = false
        videoHeaderParsed = false
        
        decoder.reset()
        Logger.shared.info("🔌 Disconnected from Kove Mirror Server")
    }
    
    // MARK: - Port 17818 (Control Socket)
    
    private func connectControl(host: String) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: KoveProtocol.portControl)!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isControlConnected = true
                    self.updateOverallConnectionState()
                    Logger.shared.success("✅ Connected to Control Port \(KoveProtocol.portControl)")
                    self.readControlData(connection)
                case .failed(let error):
                    self.isControlConnected = false
                    self.updateOverallConnectionState()
                    Logger.shared.error("❌ Control Socket connection failed: \(error.localizedDescription)")
                case .cancelled:
                    self.isControlConnected = false
                    self.updateOverallConnectionState()
                default:
                    break
                }
            }
        }
        
        self.controlConnection = connection
        connection.start(queue: .main)
    }
    
    private func readControlData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                if data.count == 6 && data[0] == 0x02 && data[1] == 0x01 && data[2] == 0x00 {
                    connection.send(content: data, completion: .idempotent)
                } else if let jsonString = String(data: data, encoding: .utf8) {
                    Logger.shared.info("📥 Control Data: \(jsonString.filter { $0.isASCII && !$0.isNewline })")
                } else {
                    let hex = data.prefix(30).map { String(format: "%02X", $0) }.joined(separator: " ")
                    Logger.shared.data("📥 Control Packet (\(data.count) bytes): [\(hex)]")
                }
            }
            
            if !isComplete && error == nil {
                self.readControlData(connection)
            } else {
                DispatchQueue.main.async { self.isControlConnected = false }
            }
        }
    }
    
    // MARK: - Port 15456 (Video Stream Socket)
    
    private func connectVideo(host: String) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: KoveProtocol.portVideo)!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isVideoConnected = true
                    self.videoHeaderParsed = false
                    self.updateOverallConnectionState()
                    Logger.shared.success("✅ Connected to Video Stream Port \(KoveProtocol.portVideo)")
                    self.readVideoData(connection)
                case .failed(let error):
                    self.isVideoConnected = false
                    self.updateOverallConnectionState()
                    Logger.shared.error("❌ Video Stream Socket failed: \(error.localizedDescription)")
                case .cancelled:
                    self.isVideoConnected = false
                    self.updateOverallConnectionState()
                default:
                    break
                }
            }
        }
        
        self.videoConnection = connection
        connection.start(queue: .main)
    }
    
    private func readVideoData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                DispatchQueue.main.async { self.totalBytesReceived += Int64(data.count) }
                
                var payload = data
                
                if !self.videoHeaderParsed && payload.count >= 69 {
                    self.parseVideoHeader(payload.prefix(69))
                    payload = payload.dropFirst(69)
                    self.videoHeaderParsed = true
                }
                
                if !payload.isEmpty {
                    self.decoder.parseIncomingData(payload)
                }
            }
            
            if !isComplete && error == nil {
                self.readVideoData(connection)
            } else {
                DispatchQueue.main.async { self.isVideoConnected = false }
            }
        }
    }
    
    private func parseVideoHeader(_ headerData: Data) {
        guard headerData.count == 69 else { return }
        
        let nameBytes = headerData.prefix(65)
        let nameString = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "android"
        
        let width = UInt16(headerData[65]) << 8 | UInt16(headerData[66])
        let height = UInt16(headerData[67]) << 8 | UInt16(headerData[68])
        
        DispatchQueue.main.async {
            self.clientName = nameString
            self.headerWidth = width
            self.headerHeight = height
            Logger.shared.success("🎥 VideoSize Header Received: Client='\(nameString)', Resolution=\(width)x\(height)")
        }
    }
    
    // MARK: - Port 15457 (Heartbeat Socket)
    
    private func connectHeartbeat(host: String) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: KoveProtocol.portHeartbeat)!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isHeartbeatConnected = true
                    self.updateOverallConnectionState()
                    Logger.shared.success("✅ Connected to Heartbeat Port \(KoveProtocol.portHeartbeat)")
                    self.readHeartbeatData(connection)
                case .failed(let error):
                    self.isHeartbeatConnected = false
                    self.updateOverallConnectionState()
                    Logger.shared.error("❌ Heartbeat Socket failed: \(error.localizedDescription)")
                case .cancelled:
                    self.isHeartbeatConnected = false
                    self.updateOverallConnectionState()
                default:
                    break
                }
            }
        }
        
        self.heartbeatConnection = connection
        connection.start(queue: .main)
    }
    
    private func readHeartbeatData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                let heartbeatPacket = Data(KoveProtocol.heartbeatPacket)
                connection.send(content: heartbeatPacket, completion: .idempotent)
            }
            
            if !isComplete && error == nil {
                self.readHeartbeatData(connection)
            } else {
                DispatchQueue.main.async { self.isHeartbeatConnected = false }
            }
        }
    }
    
    private func updateOverallConnectionState() {
        self.isConnected = isControlConnected || isVideoConnected || isHeartbeatConnected
    }
}
