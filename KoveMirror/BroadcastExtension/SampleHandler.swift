import ReplayKit
import CoreVideo
import CoreMedia
import Network

/// ReplayKit Broadcast Upload Extension Handler for KoveMirror
/// Captures full system screen (Google Maps, Waze, Scenic, OsmAnd) and transmits frames
/// to the KoveMirror host app via local loopback IPC socket.
public class SampleHandler: RPBroadcastSampleHandler {

    private var connection: NWConnection?
    private var isConnected = false
    private let ipcPort: UInt16 = 19890
    private let sendQueue = DispatchQueue(label: "com.kovemirror.broadcast.send", qos: .userInteractive)

    override public func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
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
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    override public func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        sendPixelBuffer(pixelBuffer)
    }

    // MARK: - Local Loopback IPC Connection

    private func connectToHostApp() {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: ipcPort)!)
        let params = NWParameters.tcp
        
        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
            case .failed, .cancelled:
                self?.isConnected = false
            default:
                break
            }
        }
        conn.start(queue: sendQueue)
        self.connection = conn
    }

    private func sendPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard isConnected, let connection = connection else { return }

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

        connection.send(content: packet, completion: .idempotent)
    }
}
