import Foundation
import CoreLocation

@MainActor
protocol GeofenceManagerDelegate: AnyObject {
    func didEnterGeofence()
    func didExitGeofence()
}

/// iOS CoreLocation 기반 지오펜싱 (반경 150m)
final class GeofenceManager: NSObject {

    static let shared = GeofenceManager()
    weak var delegate: GeofenceManagerDelegate?

    private let locationManager = CLLocationManager()
    private static let geofenceID = "byd.vehicle.parking"
    private static let radius: CLLocationDistance = 150.0
    private var ignoringExitUntil: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func setup() {
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func registerGeofence(lat: Double, lng: Double) {
        guard abs(lat) > 0.1 || abs(lng) > 0.1 else { return }
        // 재등록 직후 iOS가 발생시키는 spurious 이탈 이벤트 10초간 무시
        ignoringExitUntil = Date().addingTimeInterval(10)
        removeGeofence()

        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let region = CLCircularRegion(center: center, radius: Self.radius, identifier: Self.geofenceID)
        region.notifyOnEntry = true
        region.notifyOnExit  = true
        locationManager.startMonitoring(for: region)
        // 이미 지오펜스 안에 있는 경우 진입 이벤트가 오지 않으므로 현재 상태 즉시 확인
        locationManager.requestState(for: region)
        LogManager.shared.log("Geofence", "등록: (\(lat), \(lng)) 반경 \(Int(Self.radius))m")
    }

    func removeGeofence() {
        for region in locationManager.monitoredRegions where region.identifier == Self.geofenceID {
            locationManager.stopMonitoring(for: region)
        }
    }
}

extension GeofenceManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.geofenceID else { return }
        LogManager.shared.log("Geofence", "진입")
        Task { @MainActor in delegate?.didEnterGeofence() }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.geofenceID else { return }
        // 재등록 직후 spurious 이탈 이벤트 무시
        if let until = ignoringExitUntil, Date() < until { return }
        LogManager.shared.log("Geofence", "이탈")
        Task { @MainActor in delegate?.didExitGeofence() }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == Self.geofenceID else { return }
        LogManager.shared.log("Geofence", "현재 상태: \(state == .inside ? "내부" : state == .outside ? "외부" : "알 수 없음")")
        if state == .inside {
            Task { @MainActor in delegate?.didEnterGeofence() }
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        LogManager.shared.log("Geofence", "모니터링 오류: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        LogManager.shared.log("Geofence", "위치 권한 변경: \(status.rawValue)")
    }
}
