import CoreLocation

@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var observer: Observer
    private(set) var hasFix = false
    private(set) var denied = false
    @ObservationIgnored var onAuthorized: (() -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        // Until we get a fix, guess a longitude from the time zone.
        let offsetHours = Double(TimeZone.current.secondsFromGMT()) / 3600
        observer = Observer(latitude: 40, longitude: offsetHours * 15)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.startUpdatingLocation()
            onAuthorized?()
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        observer = Observer(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, elevation: max(0, loc.altitude))
        hasFix = true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
