import SwiftUI
import AVFoundation
import AppKit

public struct SampleBufferVideoView: NSViewRepresentable {
    public class Coordinator: NSObject, H264DecoderDelegate {
        var videoLayer: AVSampleBufferDisplayLayer?
        
        public func decoder(_ decoder: H264Decoder, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let layer = self.videoLayer else { return }
                if layer.status == .failed {
                    Logger.shared.error("⚠️ AVSampleBufferDisplayLayer failed: \(String(describing: layer.error))")
                    layer.flushAndRemoveImage()
                }
                layer.enqueue(sampleBuffer)
            }
        }
        
        public func decoder(_ decoder: H264Decoder, didUpdateResolution width: Int, height: Int) {
            DispatchQueue.main.async { [weak self] in
                self?.videoLayer?.flush()
            }
        }
    }
    
    @ObservedObject var decoder: H264Decoder
    
    public init(decoder: H264Decoder) {
        self.decoder = decoder
    }
    
    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = SampleBufferNSView()
        context.coordinator.videoLayer = view.videoLayer
        decoder.delegate = context.coordinator
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure layer frame matches view bounds on updates
        if let sampleView = nsView as? SampleBufferNSView {
            sampleView.updateLayerFrame()
        }
    }
}

final class SampleBufferNSView: NSView {
    let videoLayer = AVSampleBufferDisplayLayer()
    
    override var isFlipped: Bool {
        return true
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        videoLayer.videoGravity = .resizeAspect
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
        
        if let rootLayer = layer {
            videoLayer.frame = rootLayer.bounds
            rootLayer.addSublayer(videoLayer)
        }
    }
    
    public func updateLayerFrame() {
        if let rootLayer = layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = rootLayer.bounds
            CATransaction.commit()
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayerFrame()
    }
    
    override func layout() {
        super.layout()
        updateLayerFrame()
    }
}
