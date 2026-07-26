import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import AVFoundation

public protocol H264DecoderDelegate: AnyObject {
    func decoder(_ decoder: H264Decoder, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
    func decoder(_ decoder: H264Decoder, didUpdateResolution width: Int, height: Int)
}

public final class H264Decoder: ObservableObject {
    @Published public private(set) var decodedFrameCount: Int64 = 0
    @Published public private(set) var currentFPS: Double = 0.0
    @Published public private(set) var streamWidth: Int = 0
    @Published public private(set) var streamHeight: Int = 0
    
    public weak var delegate: H264DecoderDelegate?
    
    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?
    
    private var streamBuffer = Data()
    private var fpsCounter = 0
    private var lastFPSCheck = Date()
    
    public init() {}
    
    public func reset() {
        spsData = nil
        ppsData = nil
        formatDescription = nil
        streamBuffer.removeAll()
        decodedFrameCount = 0
        currentFPS = 0
        Logger.shared.info("🎬 H264Decoder state reset")
    }
    
    /// Entry point for TCP Video payload chunks (Port 15456)
    public func parseIncomingData(_ data: Data) {
        streamBuffer.append(data)
        
        // Scan streamBuffer for Annex-B start codes (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
        var searchIndex = 0
        var nalStartIndices: [(index: Int, codeLength: Int)] = []
        
        let count = streamBuffer.count
        guard count >= 4 else { return }
        
        let bytes = streamBuffer.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        guard let ptr = bytes.baseAddress else { return }
        
        while searchIndex < count - 3 {
            if ptr[searchIndex] == 0x00 && ptr[searchIndex + 1] == 0x00 {
                if ptr[searchIndex + 2] == 0x01 {
                    nalStartIndices.append((index: searchIndex, codeLength: 3))
                    searchIndex += 3
                    continue
                } else if searchIndex < count - 4 && ptr[searchIndex + 2] == 0x00 && ptr[searchIndex + 3] == 0x01 {
                    nalStartIndices.append((index: searchIndex, codeLength: 4))
                    searchIndex += 4
                    continue
                }
            }
            searchIndex += 1
        }
        
        guard nalStartIndices.count > 1 else { return }
        
        // Process NAL units between start codes
        for i in 0..<(nalStartIndices.count - 1) {
            let start = nalStartIndices[i].index + nalStartIndices[i].codeLength
            let end = nalStartIndices[i + 1].index
            let nalLength = end - start
            
            if nalLength > 0 {
                let nalData = streamBuffer.subdata(in: start..<end)
                processNALUnit(nalData)
            }
        }
        
        // Keep remaining unparsed bytes from last start code onwards
        let lastStartCodeIndex = nalStartIndices.last!.index
        streamBuffer = streamBuffer.subdata(in: lastStartCodeIndex..<streamBuffer.count)
    }
    
    private func processNALUnit(_ nalData: Data) {
        guard !nalData.isEmpty else { return }
        
        // Check for 6-byte Kove heartbeat packet: [02 01 00 00 00 00]
        if nalData.count == 6 && nalData[0] == 0x02 && nalData[1] == 0x01 && nalData[2] == 0x00 {
            return // Ignore heartbeat
        }
        
        let nalHeader = nalData[0]
        let nalType = nalHeader & 0x1F
        
        switch nalType {
        case 7: // SPS
            spsData = nalData
            updateFormatDescriptionIfReady()
        case 8: // PPS
            ppsData = nalData
            updateFormatDescriptionIfReady()
        case 5, 1: // IDR Keyframe (5) or Non-IDR Slice (1)
            decodeFrameNAL(nalData, isKeyFrame: (nalType == 5))
        default:
            break
        }
    }
    
    private func updateFormatDescriptionIfReady() {
        guard let sps = spsData, let pps = ppsData else { return }
        
        sps.withUnsafeBytes { spsBuf in
            pps.withUnsafeBytes { ppsBuf in
                guard let spsPtr = spsBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsPtr = ppsBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                
                let paramPointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let paramSizes: [Int] = [sps.count, pps.count]
                
                var newFormatDesc: CMFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: paramPointers,
                    parameterSetSizes: paramSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDesc
                )
                
                if status == noErr, let formatDesc = newFormatDesc {
                    self.formatDescription = formatDesc
                    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
                    
                    DispatchQueue.main.async {
                        if self.streamWidth != Int(dimensions.width) || self.streamHeight != Int(dimensions.height) {
                            self.streamWidth = Int(dimensions.width)
                            self.streamHeight = Int(dimensions.height)
                            Logger.shared.success("🎥 H.264 Stream Format Description Created: \(dimensions.width)x\(dimensions.height)")
                            self.delegate?.decoder(self, didUpdateResolution: Int(dimensions.width), height: Int(dimensions.height))
                        }
                    }
                } else {
                    Logger.shared.error("Failed to create CMVideoFormatDescription: \(status)")
                }
            }
        }
    }
    
    private func decodeFrameNAL(_ nalData: Data, isKeyFrame: Bool) {
        guard let formatDesc = formatDescription else { return }
        
        // Convert NAL unit to AVCC format (4-byte Big-Endian length header)
        var avccLength = UInt32(nalData.count).bigEndian
        var blockData = Data()
        withUnsafeBytes(of: &avccLength) { blockData.append(contentsOf: $0) }
        blockData.append(nalData)
        
        let dataCount = blockData.count
        var blockBuffer: CMBlockBuffer?
        let blockStatus = blockData.withUnsafeMutableBytes { buf -> OSStatus in
            guard let ptr = buf.baseAddress else { return kCMBlockBufferNoErr }
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: ptr,
                blockLength: dataCount,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        
        guard blockStatus == noErr, let blockBuffer = blockBuffer else { return }
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [blockData.count]
        
        let timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var timingInfoArray = [timingInfo]
        
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfoArray,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        if sampleStatus == noErr, let sampleBuffer = sampleBuffer {
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                let displayKey = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
                CFDictionarySetValue(dict, displayKey, Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
            
            delegate?.decoder(self, didOutputSampleBuffer: sampleBuffer)
            
            DispatchQueue.main.async {
                self.decodedFrameCount += 1
                self.fpsCounter += 1
                
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastFPSCheck)
                if elapsed >= 1.0 {
                    self.currentFPS = Double(self.fpsCounter) / elapsed
                    self.fpsCounter = 0
                    self.lastFPSCheck = now
                }
            }
        }
    }
}
