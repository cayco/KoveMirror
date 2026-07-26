import SwiftUI

struct SettingsView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    
    @State private var selectedResolutionIndex = 0
    let resolutions: [(name: String, width: UInt16, height: UInt16)] = [
        ("480 × 800 (Default Kove 800X)", 480, 800),
        ("600 × 1024 (HD TFT Standard)", 600, 1024),
        ("768 × 1024 (High-Res 2026 Models)", 768, 1024)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11)
                    .ignoresSafeArea()
                
                Form {
                    Section(header: Text("TFT DISPLAY RESOLUTION").foregroundColor(.cyan)) {
                        Picker("Target Resolution", selection: $selectedResolutionIndex) {
                            ForEach(0..<resolutions.count, id: \.self) { idx in
                                Text(resolutions[idx].name).tag(idx)
                            }
                        }
                        .pickerStyle(.inline)
                        .onChange(of: selectedResolutionIndex) { newIdx in
                            let res = resolutions[newIdx]
                            mirrorService.updateResolution(width: res.width, height: res.height)
                        }
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.14, blue: 0.18))
                    
                    Section(header: Text("PROTOCOL PARAMETERS").foregroundColor(.cyan)) {
                        HStack {
                            Text("Gateway IP")
                            Spacer()
                            Text("192.168.10.1")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Text("Control Port")
                            Spacer()
                            Text("17818")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Text("Video Stream Port")
                            Spacer()
                            Text("15456")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Text("Dedicated Heartbeat Port")
                            Spacer()
                            Text("15457")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Text("Video Codec")
                            Spacer()
                            Text("H.264 / AVC (VideoToolbox)")
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.14, blue: 0.18))
                    
                    Section(header: Text("COMPATIBILITY").foregroundColor(.cyan)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kove 800X Pro (2024)")
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Fully supported with standard BLE GATT and TCP servers.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kove 2026+ Models")
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Fully supported with strict Port 17818 6-byte heartbeat echo requirement.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.14, blue: 0.18))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Mirror Settings")
        }
    }
}
