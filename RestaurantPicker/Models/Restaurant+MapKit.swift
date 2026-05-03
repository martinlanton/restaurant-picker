import MapKit

// MARK: - Restaurant + MapKit

extension Restaurant {
    /// Opens the restaurant in the Maps app with driving directions pre-selected.
    ///
    /// Constructs an `MKMapItem` from the restaurant's coordinate, name,
    /// phone number, and URL so the Maps sheet is pre-populated.
    ///
    /// Shared by `RestaurantDetailView` and `SelectedRestaurantView` to
    /// eliminate duplicated implementation.
    func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.phoneNumber = phoneNumber
        mapItem.url = url
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }
}
