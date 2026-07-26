import Foundation
import Combine
import CoreVideo
import CoreMedia
import AVFoundation

public final class KoveMirrorService: ObservableObject {
    @Published public var bleManager: KoveBLEManager
    @Published public var tcpManager: KoveTCPManager
    @Published public var encoder: H264Encoder
    @Published public var screenCapture: ScreenCaptureManager
    
    @Published public var isMirroringActive = false
    @Published public var width: UInt16 = 480
    @Published public var height: UInt16 = 800
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.bleManager = KoveBLEManager()
        self.tcpManager = KoveTCPManager()
        self.encoder = H264Encoder(width: 480, height: 800)
        self.screenCapture = ScreenCaptureManager()
        
        bleManager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        tcpManager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        encoder.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        screenCapture.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        setupPipeline()
    }
    
    // MARK: - Pipeline Setup
    
    private func setupPipeline() {
        // 1. When TFT requests mirror over BLE -> Start TCP Servers
        bleManager.onMirrorRequested = { [weak self] in
            guard let self = self else { return }
            Logger.shared.success("🚀 TFT Mirror status activated over BLE. Starting TCP servers...")
            self.tcpManager.startServers(width: self.width, height: self.height)
        }
        
        // 2. When Port 15456 Video Socket connects -> Launch H.264 Encoder & Screen Capture
        tcpManager.onVideoConnected = { [weak self] in
            guard let self = self else { return }
            Logger.shared.success("🎬 TFT Video Socket connected. Starting H.264 VideoToolbox Session...")
            self.encoder.startSession(width: Int32(self.width), height: Int32(self.height))
            
            if self.screenCapture.isBroadcastIPCActive {
                Logger.shared.success("📡 System Screen Broadcast is ACTIVE. Forwarding full system screen (Maps/Waze) to TFT!")
            } else {
                Logger.shared.info("ℹ️ System Screen Broadcast standby. Starting Navigation Canvas fallback until System Broadcast is launched...")
                self.screenCapture.startSyntheticCanvasCapture(width: Int(self.width), height: Int(self.height))
            }
            
            DispatchQueue.main.async {
                self.isMirroringActive = true
            }
        }
        
        tcpManager.onVideoDisconnected = { [weak self] in
            guard let self = self else { return }
            Logger.shared.warning("🎬 TFT Video Socket disconnected. Stopping video encoder...")
            self.encoder.stopSession()
            self.screenCapture.stopCapture()
            
            DispatchQueue.main.async {
                self.isMirroringActive = false
            }
        }
        
        // 3. Connect Screen Capture -> H.264 Encoder
        screenCapture.onPixelBufferCaptured = { [weak self] pixelBuffer, pts in
            self?.encoder.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: pts)
        }
        
        // 4. Connect H.264 Encoder -> Port 15456 TCP Output
        encoder.onEncodedData = { [weak self] h264Data in
            self?.tcpManager.sendVideoData(h264Data)
        }
    }
    
    // MARK: - Master Public Controls
    
    public func startMirroring(width: UInt16 = 480, height: UInt16 = 800) {
        self.width = width
        self.height = height
        
        Logger.shared.info("▶️ Starting KoveMirror Service (\(width)x\(height))...")
        
        // Step A: Start TCP Servers so they are listening when motorcycle connects to Wi-Fi
        tcpManager.startServers(width: width, height: height)
        
        // Step B: Start scanning for motorcycle BLE device
        bleManager.startScanning()
        
        // Step C: Start Background Keep-Alive to allow streaming while app is minimized
        BackgroundKeepAlive.shared.start()
    }
    
    public func stopMirroring() {
        Logger.shared.info("⏹️ Stopping KoveMirror Service...")
        
        screenCapture.stopCapture()
        encoder.stopSession()
        tcpManager.stopServers()
        bleManager.disconnect()
        BackgroundKeepAlive.shared.stop()
        
        DispatchQueue.main.async {
            self.isMirroringActive = false
        }
    }
    
    public func updateResolution(width: UInt16, height: UInt16) {
        self.width = width
        self.height = height
        
        if isMirroringActive {
            stopMirroring()
            startMirroring(width: width, height: height)
        }
    }
}

public class BackgroundKeepAlive {
    public static let shared = BackgroundKeepAlive()
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    
    private init() {}
    
    public func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            
            engine.attach(player)
            
            let format = engine.outputNode.outputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            try engine.start()
            
            let frameCount = AVAudioFrameCount(format.sampleRate) // 1 second buffer
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                buffer.frameLength = frameCount
                if let channelData = buffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        let ptr = channelData[channel]
                        for i in 0..<Int(frameCount) {
                            ptr[i] = 0.0
                        }
                    }
                }
                player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                player.play()
            }
            
            self.audioEngine = engine
            self.playerNode = player
            Logger.shared.info("🔊 Background keep-alive (silent audio) started.")
        } catch {
            Logger.shared.error("❌ Failed to start background keep-alive: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            Logger.shared.info("🔇 Background keep-alive stopped.")
        } catch {
            Logger.shared.error("Failed to stop audio session: \(error.localizedDescription)")
        }
        
        playerNode = nil
        audioEngine = nil
    }
}
