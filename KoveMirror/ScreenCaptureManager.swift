import Foundation
import ReplayKit
import CoreVideo
import CoreMedia
import Network

#if canImport(UIKit)
import UIKit
#endif

public final class ScreenCaptureManager: ObservableObject {
    @Published public private(set) var isCapturing = false
    @Published public private(set) var isBroadcastIPCActive = false
    public var onPixelBufferCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    
    private var renderTimer: Timer?
    private var pixelBufferPool: CVPixelBufferPool?
    private var width: Int = 480
    private var height: Int = 800
    
    // Broadcast Extension IPC Server
    private var ipcListener: NWListener?
    private var ipcConnection: NWConnection?
    private let ipcPort: UInt16 = 19890
    
    public init() {
        startBroadcastIPCListener()
    }
    
    deinit {
        stopBroadcastIPCListener()
    }
    
    // MARK: - ReplayKit Broadcast Extension Local Loopback Receiver
    
    public func startBroadcastIPCListener() {
        guard ipcListener == nil else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: ipcPort)!)
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Logger.shared.success("📡 ReplayKit Broadcast IPC Server listening on 127.0.0.1:\(self.ipcPort)")
                case .failed(let err):
                    Logger.shared.error("❌ Broadcast IPC Server error: \(err.localizedDescription)")
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIPCConnection(connection)
            }
            
            listener.start(queue: .main)
            self.ipcListener = listener
        } catch {
            Logger.shared.error("Failed to start Broadcast IPC listener: \(error.localizedDescription)")
        }
    }
    
    public func stopBroadcastIPCListener() {
        ipcConnection?.cancel()
        ipcConnection = nil
        ipcListener?.cancel()
        ipcListener = nil
        DispatchQueue.main.async {
            self.isBroadcastIPCActive = false
        }
    }
    
    private func handleIPCConnection(_ connection: NWConnection) {
        ipcConnection?.cancel()
        ipcConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self?.isBroadcastIPCActive = true
                    self?.isCapturing = true
                }
                Logger.shared.success("🚀 Active System Broadcast Stream connected from Control Center!")
                self?.readIPCFrameData(connection)
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self?.isBroadcastIPCActive = false
                }
                Logger.shared.warning("📡 Broadcast Stream disconnected")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func readIPCFrameData(_ connection: NWConnection) {
        // Read 14-byte header: Magic(2) [0x4B, 0x4D] + Width(2) + Height(2) + BytesPerRow(4) + DataSize(4)
        connection.receive(exactLength: 14) { [weak self] content, _, isComplete, error in
            guard let self = self, let headerData = content, headerData.count == 14 else {
                if !isComplete && error == nil {
                    self?.readIPCFrameData(connection)
                }
                return
            }
            
            let bytes = Array(headerData)
            guard bytes[0] == 0x4B, bytes[1] == 0x4D else {
                self.readIPCFrameData(connection)
                return
            }
            
            let frameWidth = Int(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
            let frameHeight = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
            let bytesPerRow = Int(UInt32(bytes[6]) << 24 | UInt32(bytes[7]) << 16 | UInt32(bytes[8]) << 8 | UInt32(bytes[9]))
            let dataSize = Int(UInt32(bytes[10]) << 24 | UInt32(bytes[11]) << 16 | UInt32(bytes[12]) << 8 | UInt32(bytes[13]))
            
            connection.receive(exactLength: dataSize) { [weak self] frameData, _, isComplete, error in
                guard let self = self, let data = frameData, data.count == dataSize else {
                    if !isComplete && error == nil {
                        self?.readIPCFrameData(connection)
                    }
                    return
                }
                
                self.processRawFrameBytes(data, width: frameWidth, height: frameHeight, bytesPerRow: bytesPerRow)
                
                if !isComplete && error == nil {
                    self.readIPCFrameData(connection)
                }
            }
        }
    }
    
    private func processRawFrameBytes(_ data: Data, width: Int, height: Int, bytesPerRow: Int) {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            data.copyBytes(to: baseAddress.assumingMemoryBound(to: UInt8.self), count: data.count)
            let pts = CMTime(value: Int64(CACurrentMediaTime() * 1_000_000_000), timescale: 1_000_000_000)
            onPixelBufferCaptured?(buffer, pts)
        }
    }
    
    // MARK: - ReplayKit In-App Screen Capture
    
    public func startInAppScreenCapture(width: Int = 480, height: Int = 800) {
        stopCapture()
        self.width = width
        self.height = height
        
        if isBroadcastIPCActive {
            Logger.shared.info("📡 Using active System Broadcast Stream from ReplayKit Extension.")
            return
        }
        
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            Logger.shared.error("ReplayKit screen recorder is not available")
            startSyntheticCanvasCapture(width: width, height: height)
            return
        }
        
        recorder.startCapture(handler: { [weak self] sampleBuffer, sampleBufferType, error in
            guard let self = self else { return }
            if let error = error {
                Logger.shared.error("ReplayKit capture error: \(error.localizedDescription)")
                return
            }
            
            if sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.onPixelBufferCaptured?(pixelBuffer, pts)
            }
        }, completionHandler: { [weak self] error in
            if let error = error {
                Logger.shared.error("Failed to start ReplayKit capture: \(error.localizedDescription). Falling back to Navigation Canvas...")
                self?.startSyntheticCanvasCapture(width: width, height: height)
            } else {
                DispatchQueue.main.async {
                    self?.isCapturing = true
                }
                Logger.shared.success("🎥 ReplayKit in-app screen capture active!")
            }
        })
    }
    
    // MARK: - Synthetic Navigation Canvas Stream (Fallback / Demo Mode)
    
    public func startSyntheticCanvasCapture(width: Int = 480, height: Int = 800) {
        stopCapture()
        self.width = width
        self.height = height
        
        if isBroadcastIPCActive {
            Logger.shared.info("📡 System Broadcast Stream active. Skipping synthetic canvas.")
            return
        }
        
        setupBufferPool()
        isCapturing = true
        
        let frameInterval = 1.0 / 30.0
        renderTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.generateCanvasFrame()
        }
        Logger.shared.success("🗺️ Synthetic Navigation Canvas Capture active (\(width)x\(height) @ 30 FPS)")
    }
    
    public func stopCapture() {
        renderTimer?.invalidate()
        renderTimer = nil
        
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().stopCapture { _ in
                Logger.shared.info("🎥 ReplayKit capture stopped")
            }
        }
        
        isCapturing = false
    }
    
    private func setupBufferPool() {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &pixelBufferPool)
    }
    
    private func generateCanvasFrame() {
        guard let pool = pixelBufferPool else { return }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        #if canImport(UIKit)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        // Render Dashboard View onto buffer
        UIGraphicsPushContext(context)
        drawDashboardCanvas(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        #endif
        
        let pts = CMTime(value: Int64(CACurrentMediaTime() * 1_000_000_000), timescale: 1_000_000_000)
        onPixelBufferCaptured?(buffer, pts)
    }
    
    #if canImport(UIKit)
    private func drawDashboardCanvas(in rect: CGRect) {
        let time = Date()
        let seconds = Date().timeIntervalSince1970
        
        // 1. Dark Background
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).cgColor)
        context.fill(rect)
        
        // 2. Decorative Gradient Arc Header
        let path = UIBezierPath(roundedRect: CGRect(x: 20, y: 20, width: rect.width - 40, height: 180), cornerRadius: 20)
        UIColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 1.0).setFill()
        path.fill()
        
        // 3. Speedometer & Digital Gauges
        let speed = Int(65 + 15 * sin(seconds * 0.5))
        let speedText = "\(speed)" as NSString
        let speedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: UIColor.systemCyan
        ]
        speedText.draw(at: CGPoint(x: rect.width / 2 - 40, y: 50), withAttributes: speedAttrs)
        
        let unitText = "KM/H" as NSString
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.lightGray
        ]
        unitText.draw(at: CGPoint(x: rect.width / 2 - 25, y: 125), withAttributes: unitAttrs)
        
        // 4. Turn-by-Turn Guidance Arrow & Map Panel
        let mapRect = CGRect(x: 20, y: 220, width: rect.width - 40, height: rect.height - 240)
        let mapPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 20)
        UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0).setFill()
        mapPath.fill()
        
        // Draw Navigation Arrow
        let arrowText = "⬆️ 300m" as NSString
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: UIColor.systemGreen
        ]
        arrowText.draw(at: CGPoint(x: 40, y: 240), withAttributes: arrowAttrs)
        
        let streetText = "Grand Avenue" as NSString
        let streetAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        streetText.draw(at: CGPoint(x: 40, y: 285), withAttributes: streetAttrs)
        
        // Time & Battery Info at bottom
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let clockText = "Kove 800X TFT Mirror • \(formatter.string(from: time))" as NSString
        let clockAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.gray
        ]
        clockText.draw(at: CGPoint(x: 30, y: rect.height - 35), withAttributes: clockAttrs)
    }
    #endif
}
