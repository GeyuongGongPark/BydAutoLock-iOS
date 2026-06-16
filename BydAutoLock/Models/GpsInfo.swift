import Foundation
import CoreLocation

struct GpsInfo {
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var speed: Double = 0.0
    var direction: Double = 0.0
    var timestamp: TimeInterval = 0

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        abs(latitude) > 0.1 || abs(longitude) > 0.1
    }
}
