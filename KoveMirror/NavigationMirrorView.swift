import SwiftUI

struct NavigationMirrorView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    @State private var currentSpeed: Int = 78
    @State private var heading: String = "NE"
    @State private var nextTurnDistance: Int = 450
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.11)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kove 800X Pro TFT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            Text("LIVE MIRROR CANVAS")
                                .font(.title3)
                                .fontWeight(.heavy)
                                .foregroundColor(.cyan)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(mirrorService.screenCapture.isBroadcastIPCActive ? Color.cyan : (mirrorService.isMirroringActive ? Color.green : Color.orange))
                                .frame(width: 10, height: 10)
                            
                            Text(mirrorService.screenCapture.isBroadcastIPCActive ? "SYSTEM BROADCAST" : (mirrorService.isMirroringActive ? "DEMO CANVAS" : "STANDBY"))
                                .font(.caption2)
                                .fontWeight(.black)
                                .foregroundColor(mirrorService.screenCapture.isBroadcastIPCActive ? .cyan : (mirrorService.isMirroringActive ? .green : .orange))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // ReplayKit System Screen Broadcast Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: mirrorService.screenCapture.isBroadcastIPCActive ? "record.circle.fill" : "app.badge.checkmark")
                                .font(.title2)
                                .foregroundColor(mirrorService.screenCapture.isBroadcastIPCActive ? .red : .cyan)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SYSTEM SCREEN BROADCAST (MAPS/WAZE)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(mirrorService.screenCapture.isBroadcastIPCActive ? "Active: Mirroring full iPhone screen to TFT!" : "Ready: Launch from iOS Control Center")
                                    .font(.caption2)
                                    .foregroundColor(mirrorService.screenCapture.isBroadcastIPCActive ? .green : .gray)
                            }
                            Spacer()
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HOW TO MIRROR GOOGLE MAPS / WAZE TO TFT:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.cyan)
                                Text("Swipe down from top right corner of iPhone to open Control Center.")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.cyan)
                                Text("Long-press the Screen Recording button (🔴).")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("3.")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.cyan)
                                Text("Select 'KoveMirror Broadcast' and tap 'Start Broadcast'.")
                                    .font(.caption2).foregroundColor(.white)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("4.")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.cyan)
                                Text("Open Google Maps, Waze, Scenic, or OsmAnd — your map will project directly onto the motorcycle TFT dash!")
                                    .font(.caption2).foregroundColor(.green)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(mirrorService.screenCapture.isBroadcastIPCActive ? Color.cyan : Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    
                    // Live TFT Output Preview Box
                    VStack(spacing: 0) {
                        // Top Status Bar
                        HStack {
                            Label("\(currentSpeed) KM/H", systemImage: "speedometer")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            Spacer()
                            
                            Text("H.264 Baseline 3.1 @ 30 FPS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Text(Date(), style: .time)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        
                        // Main Canvas Area
                        ZStack {
                            if mirrorService.screenCapture.isBroadcastIPCActive {
                                VStack(spacing: 12) {
                                    Image(systemName: "tv.and.mediabox.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.cyan)
                                    
                                    Text("LIVE SYSTEM SCREEN BROADCAST ACTIVE")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("Your full iPhone display (Google Maps / Waze) is currently streaming to the motorcycle TFT display.")
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.09, green: 0.11, blue: 0.15))
                            } else {
                                // Fallback / Demo Canvas Grid
                                Canvas { context, size in
                                    let gridPath = Path { path in
                                        for x in stride(from: 0, to: size.width, by: 40) {
                                            path.move(to: CGPoint(x: x, y: 0))
                                            path.addLine(to: CGPoint(x: x, y: size.height))
                                        }
                                        for y in stride(from: 0, to: size.height, by: 40) {
                                            path.move(to: CGPoint(x: 0, y: y))
                                            path.addLine(to: CGPoint(x: size.width, y: y))
                                        }
                                    }
                                    context.stroke(gridPath, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
                                }
                                .background(Color(red: 0.09, green: 0.11, blue: 0.15))
                                
                                VStack(spacing: 20) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "arrow.turn.up.right")
                                            .font(.system(size: 42, weight: .black))
                                            .foregroundColor(.green)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("In \(nextTurnDistance) meters")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            
                                            Text("Turn Right on Alpine Pass Rd")
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(16)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.3), lineWidth: 1))
                                    .padding(.horizontal)
                                    
                                    Spacer()
                                    
                                    VStack(spacing: 0) {
                                        Text("\(currentSpeed)")
                                            .font(.system(size: 76, weight: .bold, design: .rounded))
                                            .foregroundColor(.cyan)
                                        
                                        Text("DEMO CANVAS (KM/H)")
                                            .font(.footnote)
                                            .fontWeight(.heavy)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 20) {
                                        VStatView(title: "FRONT TIRE", value: "2.4 BAR", icon: "gauge")
                                        VStatView(title: "REAR TIRE", value: "2.5 BAR", icon: "gauge")
                                        VStatView(title: "FUEL LEVEL", value: "78%", icon: "fuelpump.fill")
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, 20)
                                }
                            }
                        }
                    }
                    .aspectRatio(480.0 / 800.0, contentMode: .fit)
                    .cornerRadius(24)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.cyan.opacity(0.3), lineWidth: 2))
                    .shadow(color: Color.cyan.opacity(0.15), radius: 20, x: 0, y: 10)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
        }
        .onReceive(timer) { _ in
            currentSpeed = Int(70 + 12 * sin(Date().timeIntervalSince1970 * 0.4))
            nextTurnDistance = max(50, nextTurnDistance - 5)
            if nextTurnDistance <= 50 { nextTurnDistance = 500 }
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
