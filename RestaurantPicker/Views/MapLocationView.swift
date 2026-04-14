import CoreLocation
import MapKit
import SwiftUI

/// A full-screen map that lets the user set a custom search location.
///
/// Long-press anywhere on the map to drop a pin. The restaurant list
/// will automatically re-fetch using the pinned location. Tap
/// "Reset to My Location" to clear the override and revert to GPS.
///
/// ## Usage
/// ```swift
/// MapLocationView()
///     .environmentObject(locationManager)
/// ```
struct MapLocationView: View {
    @EnvironmentObject private var locationManager: LocationManager

    /// The map camera position, initialised to the effective location
    /// or a sensible default.
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Whether the camera has been initialised from the effective location.
    @State private var hasInitialisedCamera = false

    /// Coordinate of the dropped pin (nil when no override is active).
    private var pinCoordinate: CLLocationCoordinate2D? {
        locationManager.overrideLocation?.coordinate
    }

    /// Whether an override location is currently active.
    private var hasOverride: Bool {
        locationManager.overrideLocation != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapContent

                overlayControls
            }
            .navigationTitle("Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initialiseCameraIfNeeded()
            }
            .onChange(of: locationManager.currentLocation) {
                // Centre on GPS the first time it arrives, if no override
                if !hasOverride, !hasInitialisedCamera {
                    initialiseCameraIfNeeded()
                }
            }
        }
    }

    // MARK: - Map Content

    /// The main map view with annotations and a long-press gesture overlay.
    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Show the dropped pin
                if let pin = pinCoordinate {
                    Annotation("Search here", coordinate: pin) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }
                }

                // Show user's real GPS location as a secondary marker
                if let gps = locationManager.currentLocation?.coordinate, hasOverride {
                    Annotation("My Location", coordinate: gps) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        switch value {
                        case let .second(true, drag):
                            guard let point = drag?.location else { return }
                            handleMapLongPress(at: point, using: proxy)
                        default:
                            break
                        }
                    }
            )
        }
    }

    // MARK: - Overlay Controls

    /// Bottom overlay showing the pin coordinate and reset button.
    private var overlayControls: some View {
        VStack(spacing: 12) {
            if let pin = pinCoordinate {
                // Coordinate badge
                pinInfoBadge(coordinate: pin)
            }

            if hasOverride {
                resetButton
            } else {
                instructionBadge
            }
        }
        .padding()
    }

    /// Shows the pinned coordinate in a rounded badge.
    private func pinInfoBadge(coordinate: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.red)
            Text(Self.formatCoordinate(coordinate))
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    /// A button that clears the override location.
    private var resetButton: some View {
        Button {
            withAnimation {
                locationManager.clearOverrideLocation()
                // Re-centre on GPS
                if let gps = locationManager.currentLocation?.coordinate {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: gps,
                            latitudinalMeters: 2000,
                            longitudinalMeters: 2000
                        )
                    )
                }
            }
        } label: {
            Label("Reset to My Location", systemImage: "location.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// An instruction hint when no pin is placed.
    private var instructionBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(.secondary)
            Text("Long-press to set a search location")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Actions

    /// Handles a long-press gesture on the map by converting the screen
    /// point to a coordinate and setting the override location.
    private func handleMapLongPress(
        at screenPoint: CGPoint,
        using proxy: MapProxy
    ) {
        guard let coordinate = proxy.convert(screenPoint, from: .local) else {
            return
        }
        let newLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        withAnimation {
            locationManager.setOverrideLocation(newLocation)
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 2000,
                    longitudinalMeters: 2000
                )
            )
        }
    }

    /// Sets the initial camera position from the effective location.
    private func initialiseCameraIfNeeded() {
        guard !hasInitialisedCamera else { return }
        if let location = locationManager.effectiveLocation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 2000,
                    longitudinalMeters: 2000
                )
            )
            hasInitialisedCamera = true
        }
    }

    // MARK: - Helpers

    /// Formats a coordinate as a human-readable string.
    static func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        let latDir = coordinate.latitude >= 0 ? "N" : "S"
        let lonDir = coordinate.longitude >= 0 ? "E" : "W"
        return String(
            format: "%.4f° %@, %.4f° %@",
            abs(coordinate.latitude), latDir,
            abs(coordinate.longitude), lonDir
        )
    }
}

// MARK: - Preview

#Preview {
    MapLocationView()
        .environmentObject(LocationManager())
}
