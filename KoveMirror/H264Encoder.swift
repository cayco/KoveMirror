import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import QuartzCore

public final class H264Encoder: ObservableObject {
    @Published public private(set) var isEncoding = false
    @Published public private(set) var encodedFrameCount: Int64 = 0
    @Published public private(set) var currentFPS: Double = 0.0
    
    private var compressionSession: VTCompressionSession?
    private var width: Int32
    private var height: Int32
    private var fps: Int32
    private var bitrate: Int32
    
    private var fpsCounter = 0
    private var lastFPSCheck = Date()
    public var onEncodedData: ((Data) -> Void)?
    
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastEncodeTime: Date = Date()
    private var watchdogTimer: DispatchSourceTimer?
    private let encodeLock = NSLock()
    private var needsKeyFrame: Bool = true
    
    public init(width: Int32 = 480, height: Int32 = 800, fps: Int32 = 30, bitrate: Int32 = 1_200_000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
    }
    
    deinit {
        stopSession()
    }
    
    // MARK: - Compression Session Initialization
    
    public func startSession(width: Int32? = nil, height: Int32? = nil) {
        stopSession()
        
        if let w = width { self.width = w }
        if let h = height { self.height = h }
        
        Logger.shared.info("🎬 Initializing H.264 VideoToolbox Encoder (\(self.width)x\(self.height) @ \(fps) FPS, \(bitrate / 1000) Kbps)...")
        
        var session: VTCompressionSession?
        let encoderSpec: [String: Any] = [
            "EnableHardwareAcceleratedVideoEncoder": true,
            "RequireHardwareAcceleratedVideoEncoder": false
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: self.width,
            height: self.height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: self.width,
                kCVPixelBufferHeightKey as String: self.height
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            Logger.shared.error("❌ Failed to create VTCompressionSession. Status: \(status)")
            return
        }
        
        // Configure Session Properties for low-latency embedded TFT decoders (Carbit / EasyConnection)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_4_1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber) // 1 second keyframe interval
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session
        self.isEncoding = true
        
        // Start watchdog timer to repeat frames (matching Android's repeat-previous-frame-after = 100ms)
        encodeLock.lock()
        self.lastPixelBuffer = nil
        self.lastEncodeTime = Date()
        self.needsKeyFrame = true
        encodeLock.unlock()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isEncoding else { return }
            self.encodeLock.lock()
            let now = Date()
            let shouldEncode = now.timeIntervalSince(self.lastEncodeTime) >= 0.1
            let pixelBuffer = self.lastPixelBuffer
            let session = self.compressionSession
            let forceKeyFrame = self.needsKeyFrame
            self.needsKeyFrame = false
            self.encodeLock.unlock()
            
            if shouldEncode, let pb = pixelBuffer, let s = session {
                let pts = CMTime(value: Int64(CACurrentMediaTime() * 1_000_000_000), timescale: 1_000_000_000)
                var flags: VTEncodeInfoFlags = []
                var frameProperties: CFDictionary? = nil
                
                if forceKeyFrame {
                    let key = kVTEncodeFrameOptionKey_ForceKeyFrame
                    let value = kCFBooleanTrue
                    let dict = [key: value] as CFDictionary
                    frameProperties = dict
                }
                
                VTCompressionSessionEncodeFrame(
                    s,
                    imageBuffer: pb,
                    presentationTimeStamp: pts,
                    duration: .invalid,
                    frameProperties: frameProperties,
                    sourceFrameRefcon: nil,
                    infoFlagsOut: &flags
                )
            }
        }
        timer.resume()
        self.watchdogTimer = timer
        
        Logger.shared.success("✅ H.264 Hardware VideoToolbox Encoder Ready (High AutoLevel, Realtime)")
    }
    
    public func stopSession() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        
        encodeLock.lock()
        lastPixelBuffer = nil
        encodeLock.unlock()
        
        guard isEncoding, let session = compressionSession else { return }
        isEncoding = false
        compressionSession = nil
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        Logger.shared.info("🎬 H.264 Encoder session stopped")
    }
    
    // MARK: - Frame Encoding
    
    public func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        guard isEncoding, let session = compressionSession else { return }
        
        encodeLock.lock()
        lastPixelBuffer = pixelBuffer
        lastEncodeTime = Date()
        let forceKeyFrame = needsKeyFrame
        needsKeyFrame = false
        encodeLock.unlock()
        
        var flags: VTEncodeInfoFlags = []
        var frameProperties: CFDictionary? = nil
        
        if forceKeyFrame {
            let key = kVTEncodeFrameOptionKey_ForceKeyFrame
            let value = kCFBooleanTrue
            let dict = [key: value] as CFDictionary
            frameProperties = dict
            Logger.shared.info("🔑 Forcing IDR Keyframe for stream initialization")
        }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        
        if status != noErr {
            Logger.shared.error("Frame encode error: \(status). Attempting to restart session...")
            startSession(width: self.width, height: self.height)
        }
    }
    
    // MARK: - VTCompressionSession Callback
    
    private let outputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon, _, status, flags, sampleBuffer) in
        guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refCon).takeUnretainedValue()
        if encoder.isEncoding {
            encoder.processSampleBuffer(sampleBuffer, flags: flags)
        }
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, flags: VTEncodeInfoFlags) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var isKeyFrame = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let firstAttachment = attachments.first,
           let notSync = firstAttachment[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKeyFrame = !notSync
        }
        
        var packetData = Data()
        let annexBHeader = Data([0x00, 0x00, 0x00, 0x01])
        
        // Extract SPS & PPS NAL units if KeyFrame (IDR)
        if isKeyFrame {
            var paramSetCount: Int = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramSetCount,
                nalUnitHeaderLengthOut: nil
            )
            
            if status == noErr {
                // Parameter set 0: SPS
                var spsPointer: UnsafePointer<UInt8>?
                var spsSize: Int = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: 0,
                    parameterSetPointerOut: &spsPointer,
                    parameterSetSizeOut: &spsSize,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                
                if let sps = spsPointer {
                    packetData.append(annexBHeader)
                    packetData.append(sps, count: spsSize)
                }
                
                // Parameter set 1: PPS
                if paramSetCount > 1 {
                    var ppsPointer: UnsafePointer<UInt8>?
                    var ppsSize: Int = 0
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        formatDescription,
                        parameterSetIndex: 1,
                        parameterSetPointerOut: &ppsPointer,
                        parameterSetSizeOut: &ppsSize,
                        parameterSetCountOut: nil,
                        nalUnitHeaderLengthOut: nil
                    )
                    
                    if let pps = ppsPointer {
                        packetData.append(annexBHeader)
                        packetData.append(pps, count: ppsSize)
                    }
                }
            }
        }
        
        // Extract AVCC Elementary Stream NAL units and convert length header to Annex B start code
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        if status == noErr, let dataPointer = dataPointer {
            var bufferOffset = 0
            let avccHeaderLength = 4
            
            while bufferOffset < length - avccHeaderLength {
                var nalUnitLength: UInt32 = 0
                memcpy(&nalUnitLength, dataPointer.advanced(by: bufferOffset), avccHeaderLength)
                nalUnitLength = UInt32(bigEndian: nalUnitLength)
                
                let payloadPointer = dataPointer.advanced(by: bufferOffset + avccHeaderLength)
                let nalUnitType = payloadPointer.pointee & 0x1F
                
                // CRITICAL: Strip SEI (Supplemental Enhancement Information) NAL units (Type 6)
                // Embedded hardware decoders (like Kove TFT) often crash if they encounter unexpected NAL unit types.
                if nalUnitType != 6 {
                    packetData.append(annexBHeader)
                    packetData.append(UnsafePointer<UInt8>(OpaquePointer(payloadPointer)), count: Int(nalUnitLength))
                } else {
                    Logger.shared.info("Stripped SEI NAL unit from stream to protect hardware decoder")
                }
                
                bufferOffset += Int(nalUnitLength) + avccHeaderLength
            }
        }
        
        if !packetData.isEmpty {
            onEncodedData?(packetData)
            
            DispatchQueue.main.async {
                self.encodedFrameCount += 1
                self.fpsCounter += 1
                
                let now = Date()
                let timePassed = now.timeIntervalSince(self.lastFPSCheck)
                if timePassed >= 1.0 {
                    self.currentFPS = Double(self.fpsCounter) / timePassed
                    self.fpsCounter = 0
                    self.lastFPSCheck = now
                }
            }
        }
    }
}
