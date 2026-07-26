import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

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
    
    public init(width: Int32 = 480, height: Int32 = 800, fps: Int32 = 30, bitrate: Int32 = 1_200_000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
    }
    
    // MARK: - Compression Session Initialization
    
    public func startSession(width: Int32? = nil, height: Int32? = nil) {
        stopSession()
        
        if let w = width { self.width = w }
        if let h = height { self.height = h }
        
        Logger.shared.info("🎬 Initializing H.264 VideoToolbox Encoder (\(self.width)x\(self.height) @ \(fps) FPS, \(bitrate / 1000) Kbps)...")
        
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: self.width,
            height: self.height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
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
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_3_1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CAVLC)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber) // 1 second keyframe interval
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session
        self.isEncoding = true
        Logger.shared.success("✅ H.264 Hardware VideoToolbox Encoder Ready (Baseline AutoLevel, Realtime)")
    }
    
    public func stopSession() {
        guard let session = compressionSession else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        compressionSession = nil
        isEncoding = false
        Logger.shared.info("🎬 H.264 Encoder session stopped")
    }
    
    // MARK: - Frame Encoding
    
    public func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        guard isEncoding, let session = compressionSession else { return }
        
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        
        if status != noErr {
            Logger.shared.error("Frame encode error: \(status)")
        }
    }
    
    // MARK: - VTCompressionSession Callback
    
    private let outputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon, _, status, flags, sampleBuffer) in
        guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refCon).takeUnretainedValue()
        encoder.processSampleBuffer(sampleBuffer, flags: flags)
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, flags: VTEncodeInfoFlags) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var isKeyFrame = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            if let notSyncVal = CFDictionaryGetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
                let notSync = unsafeBitCast(notSyncVal, to: CFBoolean.self)
                isKeyFrame = !CFBooleanGetValue(notSync)
            }
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
                
                packetData.append(annexBHeader)
                packetData.append(UnsafePointer<UInt8>(OpaquePointer(dataPointer.advanced(by: bufferOffset + avccHeaderLength))), count: Int(nalUnitLength))
                
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
