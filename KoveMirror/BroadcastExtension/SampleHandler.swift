import ReplayKit
import CoreVideo
import CoreMedia
import Network
import VideoToolbox

/// ReplayKit Broadcast Upload Extension Handler for KoveMirror
/// Captures full system screen (Google Maps, Waze, Scenic, OsmAnd) and transmits frames
/// to the KoveMirror host app via local loopback IPC socket.
class SampleHandler: RPBroadcastSampleHandler {

    private var connection: NWConnection?
    private var isConnected = false
    private var isSending = false
    private let ipcPort: UInt16 = 19890
    private let sendQueue = DispatchQueue(label: "com.kovemirror.broadcast.send", qos: .userInteractive)
    
    // VTPixelTransferSession & Pool for hardware downscaling to TFT resolution
    private var transferSession: VTPixelTransferSession?
    private var scaledBufferPool: CVPixelBufferPool?
    private let targetWidth = 480
    private let targetHeight = 800
    private var reconnectTimer: DispatchSourceTimer?

    override public func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
        setupTransferSession()
        connectToHostApp()
    }

    override public func broadcastPaused() {
        super.broadcastPaused()
    }

    override public func broadcastResumed() {
        super.broadcastResumed()
    }

    override public func broadcastFinished() {
        super.broadcastFinished()
        stopReconnectTimer()
        connection?.cancel()
        connection = nil
        isConnected = false
        if let session = transferSession {
            VTPixelTransferSessionInvalidate(session)
            transferSession = nil
        }
        scaledBufferPool = nil
    }

    override public func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Hardware-downscale to target TFT resolution (480x800) before IPC transfer
        let scaledBuffer = scalePixelBuffer(pixelBuffer) ?? pixelBuffer
        sendPixelBuffer(scaledBuffer)
    }
    
    private func setupTransferSession() {
        VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
    }
    
    private func scalePixelBuffer(_ sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if scaledBufferPool == nil {
            let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 4]
            let bufferAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &scaledBufferPool)
        }
        
        guard let pool = scaledBufferPool else { return nil }
        var destinationBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinationBuffer)
        guard let dest = destinationBuffer, let session = transferSession else { return nil }
        
        let status = VTPixelTransferSessionTransferImage(session, from: sourceBuffer, to: dest)
        return status == noErr ? dest : nil
    }

    // MARK: - Local Loopback IPC Connection

    private func connectToHostApp() {
        if connection != nil {
            connection?.cancel()
            connection = nil
        }
        
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: ipcPort)!)
        let params = NWParameters.tcp
        
        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.stopReconnectTimer()
            case .failed, .cancelled:
                self?.isConnected = false
                self?.startReconnectTimer()
            default:
                break
            }
        }
        conn.start(queue: sendQueue)
        self.connection = conn
    }
    
    private func startReconnectTimer() {
        guard reconnectTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.connectToHostApp()
        }
        timer.resume()
        reconnectTimer = timer
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    private func sendPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard isConnected, let connection = connection else { return }
        
        if isSending {
            return
        }
        isSending = true

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let dataSize = bytesPerRow * height
        var header = Data()
        
        // Frame Header (14 bytes): [Magic 0x4B, 0x4D] [Width UInt16] [Height UInt16] [BytesPerRow UInt32] [PayloadSize UInt32]
        header.append(contentsOf: [0x4B, 0x4D])
        var w = UInt16(width).bigEndian
        var h = UInt16(height).bigEndian
        var bpr = UInt32(bytesPerRow).bigEndian
        var sz = UInt32(dataSize).bigEndian
        
        header.append(Data(bytes: &w, count: 2))
        header.append(Data(bytes: &h, count: 2))
        header.append(Data(bytes: &bpr, count: 4))
        header.append(Data(bytes: &sz, count: 4))

        let frameData = Data(bytes: baseAddress, count: dataSize)
        
        var packet = Data()
        packet.append(header)
        packet.append(frameData)

        connection.send(content: packet, completion: .contentProcessed({ [weak self] _ in
            self?.isSending = false
        }))
    }
}

