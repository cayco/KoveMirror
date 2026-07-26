import Foundation
import Network
import Combine

public final class KoveTCPManager: ObservableObject {
    @Published public private(set) var isControlConnected = false
    @Published public private(set) var isVideoConnected = false
    @Published public private(set) var isHeartbeatConnected = false
    @Published public private(set) var totalBytesSent: Int64 = 0
    
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    private var heartbeatListener: NWListener?
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var heartbeatConnection: NWConnection?
    
    private var videoHeartbeatTimer: DispatchSourceTimer?
    private var dedicatedHeartbeatTimer: DispatchSourceTimer?
    
    private var isHandshakeCompleted = false
    public var width: UInt16 = 480
    public var height: UInt16 = 800
    
    public var onVideoConnected: (() -> Void)?
    public var onVideoDisconnected: (() -> Void)?
    
    public init() {}
    
    // MARK: - Start Servers
    
    public func startServers(width: UInt16 = 480, height: UInt16 = 800) {
        self.width = width
        self.height = height
        
        startControlServer()
        startVideoServer()
        startHeartbeatServer()
    }
    
    public func stopServers() {
        stopVideoHeartbeat()
        stopDedicatedHeartbeat()
        
        controlConnection?.cancel()
        
        videoHeartbeatTimer?.cancel()
        dedicatedHeartbeatTimer?.cancel()
        videoHeartbeatTimer = nil
        dedicatedHeartbeatTimer = nil
        videoConnection?.cancel()
        heartbeatConnection?.cancel()
        
        controlConnection = nil
        videoConnection = nil
        heartbeatConnection = nil
        
        isControlConnected = false
        isVideoConnected = false
        isHeartbeatConnected = false
        isHandshakeCompleted = false
        
        Logger.shared.info("🔌 Active TCP connections closed. Servers remain listening for next session.")
    }
    
    // MARK: - Port 17818 (Control Server)
    
    private func startControlServer() {
        guard controlListener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: KoveProtocol.portControl)!)
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Logger.shared.success("✅ Control Server ready on PORT \(KoveProtocol.portControl)")
                case .failed(let err):
                    Logger.shared.error("❌ Control Server failed: \(err.localizedDescription)")
                    self?.controlListener?.cancel()
                    self?.controlListener = nil
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleControlConnection(connection)
            }
            
            listener.start(queue: .main)
            self.controlListener = listener
        } catch {
            Logger.shared.error("Failed to bind Control Server on port \(KoveProtocol.portControl): \(error.localizedDescription)")
        }
    }
    
    private func handleControlConnection(_ connection: NWConnection) {
        controlConnection?.cancel()
        controlConnection = connection
        isHandshakeCompleted = false
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isControlConnected = true
                Logger.shared.success("🔌 TFT Control socket connected! Sending TUC GET...")
                self?.sendControlTucGet()
                self?.readControlData(connection)
            case .failed(let err):
                self?.isControlConnected = false
                Logger.shared.error("❌ Control socket failed: \(err.localizedDescription)")
            case .cancelled:
                self?.isControlConnected = false
                Logger.shared.warning("🔌 Control socket closed")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func sendControlTucGet() {
        guard let connection = controlConnection else { return }
        let tucJson = "{\"msg_id\":27,\"func\":\"TUC\",\"act\":\"GET\"}"
        let data = KoveProtocol.frameControlJSON(tucJson)
        
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                Logger.shared.error("Failed to send TUC GET: \(error.localizedDescription)")
            } else {
                Logger.shared.info("📤 TUC GET query sent on Port 17818")
            }
        }))
    }
    
    private func readControlData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                // 2026 Kove: Echo 6-byte heartbeat packet [02 01 00 00 00 00]
                if data.count == 6 && data[0] == 0x02 && data[1] == 0x01 && data[2] == 0x00 {
                    connection.send(content: data, completion: .idempotent)
                } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    Logger.shared.info("📥 Control Data: \(text.filter { $0.isASCII && !$0.isNewline })")
                } else {
                    let hex = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
                    Logger.shared.data("📥 Control Hex: [\(hex)] (\(data.count) bytes)")
                }
                
                // Trigger control handshake on initial TFT reply
                if !self.isHandshakeCompleted {
                    self.isHandshakeCompleted = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.sendControlBinaryHandshake()
                    }
                }
            }
            
            if isComplete || error != nil {
                self.isControlConnected = false
            } else {
                self.readControlData(connection)
            }
        }
    }
    
    private func sendControlBinaryHandshake() {
        guard let connection = controlConnection else { return }
        
        let binaryHandshake = KoveProtocol.makeBinaryControlHandshake()
        connection.send(content: binaryHandshake, completion: .contentProcessed({ _ in
            Logger.shared.success("📤 Port 17818 binary handshake sequence sent")
        }))
        
        let navi2 = KoveProtocol.frameControlJSON("{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":2}")
        let navi1 = KoveProtocol.frameControlJSON("{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":1}")
        
        connection.send(content: navi2, completion: .idempotent)
        connection.send(content: navi1, completion: .idempotent)
    }
    
    // MARK: - Port 15456 (Video Server)
    
    private func startVideoServer() {
        guard videoListener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: KoveProtocol.portVideo)!)
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Logger.shared.success("✅ Video Server ready on PORT \(KoveProtocol.portVideo)")
                case .failed(let err):
                    Logger.shared.error("❌ Video Server failed: \(err.localizedDescription)")
                    self?.videoListener?.cancel()
                    self?.videoListener = nil
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleVideoConnection(connection)
            }
            
            listener.start(queue: .main)
            self.videoListener = listener
        } catch {
            Logger.shared.error("Failed to bind Video Server on port \(KoveProtocol.portVideo): \(error.localizedDescription)")
        }
    }
    
    private func handleVideoConnection(_ connection: NWConnection) {
        videoConnection?.cancel()
        videoConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.readVideoFeedback(connection)
                
                // CRITICAL: Send header and wait for it to be processed BEFORE starting video data.
                // Prevents TCP coalescing which breaks poorly written embedded recv() loops.
                self.sendVideoHeader { success in
                    if success {
                        // Add a tiny physical delay to ensure the TFT parses the header before NAL units arrive
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.isVideoConnected = true
                            self.startVideoHeartbeat()
                            self.onVideoConnected?()
                        }
                    }
                }
            case .failed(let err):
                self.isVideoConnected = false
                self.stopVideoHeartbeat()
                self.onVideoDisconnected?()
                Logger.shared.error("❌ Video socket failed: \(err.localizedDescription)")
            case .cancelled:
                self.isVideoConnected = false
                self.stopVideoHeartbeat()
                self.onVideoDisconnected?()
                Logger.shared.warning("🔌 Video socket closed")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func sendVideoHeader(completion: @escaping (Bool) -> Void) {
        guard let connection = videoConnection else {
            completion(false)
            return
        }
        let header = KoveProtocol.makeVideoSizeHeader(width: width, height: height, clientName: "android")
        
        connection.send(content: header, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                Logger.shared.error("Failed to send Video Header: \(error.localizedDescription)")
                completion(false)
            } else {
                Logger.shared.info("📤 VideoSize header sent (69 bytes) -> W:\(self.width), H:\(self.height)")
                completion(true)
            }
        }))
    }
    
    private func startVideoHeartbeat() {
        videoHeartbeatTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, let connection = self.videoConnection, self.isVideoConnected else { return }
            let packet = Data(KoveProtocol.heartbeatPacket)
            connection.send(content: packet, completion: .idempotent)
        }
        timer.resume()
        videoHeartbeatTimer = timer
    }
    
    private func stopVideoHeartbeat() {
        videoHeartbeatTimer?.cancel()
        videoHeartbeatTimer = nil
    }
    
    private func readVideoFeedback(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            if let data = content, !data.isEmpty {
                Logger.shared.data("📥 TFT Video Feedback: \(data.count) bytes")
            }
            if !isComplete && error == nil {
                self?.readVideoFeedback(connection)
            }
        }
    }
    
    public func sendVideoData(_ data: Data) {
        guard let connection = videoConnection, isVideoConnected else { return }
        
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.totalBytesSent += Int64(data.count)
                }
            }
        }))
    }
    
    // MARK: - Port 15457 (Dedicated Heartbeat Server)
    
    private func startHeartbeatServer() {
        guard heartbeatListener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: KoveProtocol.portHeartbeat)!)
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Logger.shared.success("✅ Dedicated Heartbeat Server ready on PORT \(KoveProtocol.portHeartbeat)")
                case .failed(let err):
                    Logger.shared.error("❌ Heartbeat Server failed: \(err.localizedDescription)")
                    self?.heartbeatListener?.cancel()
                    self?.heartbeatListener = nil
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleHeartbeatConnection(connection)
            }
            
            listener.start(queue: .main)
            self.heartbeatListener = listener
        } catch {
            Logger.shared.error("Failed to bind Dedicated Heartbeat Server on port \(KoveProtocol.portHeartbeat): \(error.localizedDescription)")
        }
    }
    
    private func handleHeartbeatConnection(_ connection: NWConnection) {
        heartbeatConnection?.cancel()
        heartbeatConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isHeartbeatConnected = true
                Logger.shared.success("🔌 TFT Dedicated Heartbeat socket connected! Starting 200ms ping...")
                self?.startDedicatedHeartbeatPing()
            case .failed, .cancelled:
                self?.isHeartbeatConnected = false
                self?.stopDedicatedHeartbeat()
                Logger.shared.warning("🔌 Dedicated Heartbeat socket disconnected")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func startDedicatedHeartbeatPing() {
        dedicatedHeartbeatTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            guard let self = self, let connection = self.heartbeatConnection, self.isHeartbeatConnected else { return }
            let packet = Data(KoveProtocol.heartbeatPacket)
            connection.send(content: packet, completion: .idempotent)
        }
        timer.resume()
        dedicatedHeartbeatTimer = timer
    }
    
    private func stopDedicatedHeartbeat() {
        dedicatedHeartbeatTimer?.cancel()
        dedicatedHeartbeatTimer = nil
    }
}
