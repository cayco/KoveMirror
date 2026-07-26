import SwiftUI
import MapKit
import CoreLocation
import ReplayKit

struct NavigationMirrorView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    @StateObject private var locationManager = LocationDelegate()
    @State private var searchRadius: String = ""
    @State private var destinationText: String = ""
    @State private var route: MKRoute?
    @State private var isNavigating = false
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.11)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Control Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KOVE 800X PRO DASH")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Text("LIVE MAP NAVIGATION")
                            .font(.subheadline)
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
                .padding(.vertical, 10)
                .background(Color(red: 0.10, green: 0.12, blue: 0.16))
                
                // Destination Search Bar Overlay
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.cyan)
                    
                    TextField("Enter destination (e.g. Stelvio Pass)...", text: $destinationText)
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    if !destinationText.isEmpty {
                        Button(action: {
                            searchDestination()
                        }) {
                            Text("ROUTE")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.cyan)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                // Live Map Canvas Box (Rendered & Streamed Live to Motorcycle TFT)
                ZStack(alignment: .bottom) {
                    MapCanvasView(locationManager: locationManager, route: route)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.4), lineWidth: 1.5))
                    
                    // Telemetry & Guidance Overlay (Rendered directly onto TFT output stream)
                    VStack {
                        // Top Turn Guidance Banner
                        if let route = route, let step = route.steps.first(where: { !$0.instructions.isEmpty }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.turn.up.right")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.instructions)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("In \(Int(step.distance)) meters")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(14)
                            .padding(12)
                        }
                        
                        Spacer()
                        
                        // Bottom Telemetry Bar
                        HStack(spacing: 16) {
                            // Speedometer
                            VStack(spacing: 0) {
                                Text("\(Int(max(0, locationManager.speed * 3.6)))")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundColor(.cyan)
                                
                                Text("KM/H")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(14)
                            
                            Spacer()
                            
                            // Compass Heading
                            VStack(spacing: 2) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.caption)
                                    .foregroundColor(.cyan)
                                    .rotationEffect(.degrees(locationManager.heading))
                                
                                Text("\(Int(locationManager.heading))°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(14)
                        }
                        .padding(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                
                // Instructions Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("💡 APPLE DEVELOPER FREE ACCOUNT NOTICE:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.yellow)
                    
                    Text("Free Personal Apple Developer accounts restrict Broadcast Extension targets in Control Center. KoveMirror's built-in Live Navigation Map streams directly to your TFT dash without requiring a paid developer account!")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            locationManager.requestPermission()
            mirrorService.startMirroring()
        }
    }
    
    private func searchDestination() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destinationText
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let mapItem = response?.mapItems.first else { return }
            
            let directionsRequest = MKDirections.Request()
            directionsRequest.source = MKMapItem.forCurrentLocation()
            directionsRequest.destination = mapItem
            directionsRequest.transportType = .automobile
            
            let directions = MKDirections(request: directionsRequest)
            directions.calculate { response, error in
                if let calculatedRoute = response?.routes.first {
                    DispatchQueue.main.async {
                        self.route = calculatedRoute
                        self.isNavigating = true
                    }
                }
            }
        }
    }
}

// MARK: - MapKit Live Canvas View

struct MapCanvasView: UIViewRepresentable {
    @ObservedObject var locationManager: LocationDelegate
    var route: MKRoute?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.overrideUserInterfaceStyle = .dark
        mapView.mapType = .standard
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let route = route {
            uiView.removeOverlays(uiView.overlays)
            uiView.addOverlay(route.polyline)
            uiView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        
        init(_ parent: MapCanvasView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemCyan
                renderer.lineWidth = 6
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - CoreLocation Manager Delegate

class LocationDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var speed: CLLocationSpeed = 0.0
    @Published var heading: CLLocationDirection = 0.0
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.headingFilter = 2
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            DispatchQueue.main.async {
                self.speed = max(0, loc.speed)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
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
