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
    private var ignoringExitUntil: Date?
    // 동일 좌표 재등록 방지
    private var lastRegisteredLat: Double?
    private var lastRegisteredLng: Double?
    // didEnterRegion + didDetermineState 중복 콜백 방지 (2초 디바운스)
    private var lastEnterEventTime: Date?

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
        // 동일 좌표 재등록 방지 (GPS 갱신 시 반복 호출 차단)
        if let lastLat = lastRegisteredLat, let lastLng = lastRegisteredLng,
           abs(lat - lastLat) < 0.0001 && abs(lng - lastLng) < 0.0001 { return }
        lastRegisteredLat = lat
        lastRegisteredLng = lng
        // 재등록 직후 iOS가 발생시키는 spurious 이탈 이벤트 10초간 무시
        ignoringExitUntil = Date().addingTimeInterval(10)
        lastEnterEventTime = nil
        removeGeofence()

        let radius = CLLocationDistance(StorageManager.shared.geofenceRadius)
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let region = CLCircularRegion(center: center, radius: radius, identifier: Self.geofenceID)
        region.notifyOnEntry = true
        region.notifyOnExit  = true
        locationManager.startMonitoring(for: region)
        // 이미 지오펜스 안에 있는 경우 진입 이벤트가 오지 않으므로 현재 상태 즉시 확인
        locationManager.requestState(for: region)
        LogManager.shared.log("Geofence", "등록: (\(lat), \(lng)) 반경 \(Int(radius))m")
    }

    func removeGeofence() {
        for region in locationManager.monitoredRegions where region.identifier == Self.geofenceID {
            locationManager.stopMonitoring(for: region)
        }
    }

    /// 앱이 백그라운드에서 suspend되지 않도록 위치 업데이트를 유지
    /// - 10m 정확도 + 10m 이동 필터 → GPS 사용, 배터리 소모 있음
    /// - 이 호출이 없으면 UIBackgroundTask 만료 후 앱이 suspend되어 RSSI 폴링이 멈춤
    func startBackgroundKeepAlive() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        locationManager.startUpdatingLocation()
    }

    func stopBackgroundKeepAlive() {
        locationManager.stopUpdatingLocation()
    }
}

extension GeofenceManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.geofenceID else { return }
        LogManager.shared.log("Geofence", "진입")
        fireEnterEvent()
    }

    private func fireEnterEvent() {
        let now = Date()
        // didEnterRegion + didDetermineState 중복 콜백 2초 디바운스
        if let last = lastEnterEventTime, now.timeIntervalSince(last) < 2.0 { return }
        lastEnterEventTime = now
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
            fireEnterEvent()
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        LogManager.shared.log("Geofence", "모니터링 오류: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        LogManager.shared.log("Geofence", "위치 권한 변경: \(status.rawValue)")
    }

    // startBackgroundKeepAlive() 로 인한 위치 업데이트 콜백 (무시)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
}
