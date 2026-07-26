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
                    layer.flush()
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
        // Layout updates handled automatically by NSView bounds change
    }
}

final class SampleBufferNSView: NSView {
    let videoLayer = AVSampleBufferDisplayLayer()
    
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
        
        if let rootLayer = layer {
            videoLayer.frame = rootLayer.bounds
            rootLayer.addSublayer(videoLayer)
        }
    }
    
    override func layout() {
        super.layout()
        if let rootLayer = layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = rootLayer.bounds
            CATransaction.commit()
        }
    }
}
