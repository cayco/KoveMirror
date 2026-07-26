import SwiftUI
import WebKit
import ReplayKit

struct NavigationMirrorView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    @State private var selectedMapSource: MapSource = .googleMaps
    @State private var customUrlString: String = ""
    
    enum MapSource: String, CaseIterable, Identifiable {
        case googleMaps = "Google Maps"
        case waze = "Waze"
        case openStreetMap = "OpenStreetMap"
        
        var id: String { rawValue }
        
        var url: URL {
            switch self {
            case .googleMaps:
                return URL(string: "https://www.google.com/maps")!
            case .waze:
                return URL(string: "https://www.waze.com/live-map")!
            case .openStreetMap:
                return URL(string: "https://www.openstreetmap.org")!
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.11)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KOVE 800X PRO TFT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Text("LIVE NAVIGATION CANVAS")
                            .font(.title3)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Streaming Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(mirrorService.isMirroringActive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(mirrorService.isMirroringActive ? "STREAMING TO TFT" : "CONNECTING...")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(mirrorService.isMirroringActive ? .green : .orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                // Map Engine Selector (Google Maps / Waze / OpenStreetMap)
                Picker("Map Source", selection: $selectedMapSource) {
                    ForEach(MapSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                
                // Live Interactive Navigation Web View Container
                ZStack {
                    NavigationWebView(url: selectedMapSource.url)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.4), lineWidth: 1.5))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom Stream Control Bar
                HStack(spacing: 12) {
                    Button(action: {
                        if mirrorService.isMirroringActive {
                            mirrorService.stopMirroring()
                        } else {
                            mirrorService.startMirroring()
                        }
                    }) {
                        HStack {
                            Image(systemName: mirrorService.isMirroringActive ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title3)
                            Text(mirrorService.isMirroringActive ? "STOP TFT STREAM" : "START STREAMING TO TFT")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(mirrorService.isMirroringActive ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mirrorService.isMirroringActive ? Color.red : Color.cyan)
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            mirrorService.startMirroring()
        }
    }
}

// MARK: - Interactive Navigation WKWebView Component

struct NavigationWebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
}

struct VStatView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.cyan)
            
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 8))
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}
