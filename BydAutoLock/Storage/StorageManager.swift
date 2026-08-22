import Foundation

/// 설정 및 자격증명 저장소
/// - 민감 데이터(계정, 토큰): Keychain
/// - 일반 설정: UserDefaults
final class StorageManager {

    static let shared = StorageManager()
    private let defaults = UserDefaults.standard
    private let widgetDefaults = UserDefaults(suiteName: "group.com.ggp.bydautolock")
    private init() {}

    // MARK: - Widget / Watch 공유 데이터

    func saveWidgetData(isRunning: Bool, isLocked: Bool?, battery: Int?, drivingRange: Int?) {
        widgetDefaults?.set(isRunning, forKey: "widget_isRunning")
        if let v = isLocked      { widgetDefaults?.set(v, forKey: "widget_isLocked") }
        if let v = battery       { widgetDefaults?.set(v, forKey: "widget_battery") }
        if let v = drivingRange  { widgetDefaults?.set(v, forKey: "widget_drivingRange") }
        widgetDefaults?.synchronize()
    }

    // MARK: - Keychain Keys

    private enum KC {
        static let username   = "byd.username"
        static let password   = "byd.password"
        static let pin        = "byd.pin"
        static let userId     = "byd.userId"
        static let signToken  = "byd.signToken"
        static let encryToken = "byd.encryToken"
        static let vins       = "byd.vins"
        static let selectedVin = "byd.selectedVin"

        // BLE 직접 제어 — Watch 페어링(별도 인증 도메인) 토큰 + 차량 dkey
        static let watchEncryToken = "byd.watch.encryToken"
        static let watchSignToken  = "byd.watch.signToken"
        static let watchControlPwd = "byd.watch.controlPwd"
        static let bleDkey         = "byd.ble.dkey"
        static let blePassword     = "byd.ble.password"
    }

    // MARK: - UserDefaults Keys

    private enum UD {
        static let region            = "byd_region"
        static let hasCredentials    = "has_credentials"
        static let deviceMac         = "bt_device_mac"
        static let deviceName        = "bt_device_name"
        static let peripheralUUID    = "bt_peripheral_uuid"
        static let unlockRssi        = "unlock_rssi_threshold"
        static let lockRssi          = "lock_rssi_threshold"
        static let rssiAlpha         = "rssi_smoothing_alpha"
        static let serviceEnabled    = "service_enabled"
        static let autoAcOnUnlock    = "auto_ac_on_unlock"
        static let autoAcOffOnLock   = "auto_ac_off_on_lock"
        static let acTargetTemp      = "ac_target_temp"
        static let acWindLevel       = "ac_wind_level"
        static let acCycleMode       = "ac_cycle_mode"
        static let bleScanMode       = "ble_scan_mode"
        static let geofencingEnabled = "geofencing_enabled"
        static let geofenceRadius    = "geofence_radius"
        static let autoUnlockOnApproach  = "auto_unlock_on_approach"
        static let autoLockOnDeparture   = "auto_lock_on_departure"

        // 알림
        static let notifyLockUnlock  = "notify_lock_unlock"
        static let notifySignalLost  = "notify_signal_lost"
        static let notifyAc          = "notify_ac"
        static let notifyService     = "notify_service"
        static let notifyLowBattery  = "notify_low_battery"
        static let lowBatteryThreshold = "low_battery_threshold"
        static let lastVehicleLat    = "last_vehicle_lat"
        static let lastVehicleLng    = "last_vehicle_lng"
        static let lastVehicleTime   = "last_vehicle_time"
        static let lastVehicleSource = "last_vehicle_source"

        // BLE 직접 제어 — Watch 페어링 상태 + 차량 BLE 정보 (dkey/토큰 자체는 KC로 분리)
        static let watchQrUuid          = "watch_qr_uuid"
        static let watchIdentifier      = "watch_identifier"
        static let watchUserType        = "watch_user_type"
        static let watchVin             = "watch_vin"
        static let watchVehicleInfoJson = "watch_vehicle_info_json"
        static let watchImeiSeed        = "watch_imei_seed"
        static let bleMacAddress        = "ble_mac_address"
        static let bleKeyNumber         = "ble_key_number"
        static let bleAuthProtocol      = "ble_auth_protocol"
    }

    // MARK: - Auth (Keychain)

    var username: String? {
        get { KeychainHelper.load(forKey: KC.username) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.username) } else { KeychainHelper.delete(forKey: KC.username) } }
    }
    var password: String? {
        get { KeychainHelper.load(forKey: KC.password) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.password) } else { KeychainHelper.delete(forKey: KC.password) } }
    }
    var pin: String? {
        get { KeychainHelper.load(forKey: KC.pin) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.pin) } else { KeychainHelper.delete(forKey: KC.pin) } }
    }
    var userId: String? {
        get { KeychainHelper.load(forKey: KC.userId) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.userId) } else { KeychainHelper.delete(forKey: KC.userId) } }
    }
    var signToken: String? {
        get { KeychainHelper.load(forKey: KC.signToken) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.signToken) } else { KeychainHelper.delete(forKey: KC.signToken) } }
    }
    var encryToken: String? {
        get { KeychainHelper.load(forKey: KC.encryToken) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.encryToken) } else { KeychainHelper.delete(forKey: KC.encryToken) } }
    }
    var vins: String? {
        get { KeychainHelper.load(forKey: KC.vins) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.vins) } else { KeychainHelper.delete(forKey: KC.vins) } }
    }
    var selectedVin: String? {
        get { KeychainHelper.load(forKey: KC.selectedVin) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.selectedVin) } else { KeychainHelper.delete(forKey: KC.selectedVin) } }
    }

    var hasCredentials: Bool {
        get { defaults.bool(forKey: UD.hasCredentials) }
        set { defaults.set(newValue, forKey: UD.hasCredentials) }
    }

    // MARK: - Region

    var region: String {
        get { defaults.string(forKey: UD.region) ?? "KR" }
        set { defaults.set(newValue, forKey: UD.region) }
    }

    // MARK: - Bluetooth

    var deviceMac: String? {
        get { defaults.string(forKey: UD.deviceMac) }
        set { defaults.set(newValue, forKey: UD.deviceMac) }
    }
    var deviceName: String? {
        get { defaults.string(forKey: UD.deviceName) }
        set { defaults.set(newValue, forKey: UD.deviceName) }
    }
    var peripheralUUID: String? {
        get { defaults.string(forKey: UD.peripheralUUID) }
        set { defaults.set(newValue, forKey: UD.peripheralUUID) }
    }

    // MARK: - RSSI Thresholds

    var unlockRssi: Int {
        get { defaults.object(forKey: UD.unlockRssi) as? Int ?? -70 }
        set { defaults.set(newValue, forKey: UD.unlockRssi) }
    }
    var lockRssi: Int {
        get { defaults.object(forKey: UD.lockRssi) as? Int ?? -85 }
        set { defaults.set(newValue, forKey: UD.lockRssi) }
    }
    var rssiAlpha: Float {
        get { defaults.object(forKey: UD.rssiAlpha) as? Float ?? 0.25 }
        set { defaults.set(newValue, forKey: UD.rssiAlpha) }
    }

    // MARK: - Service Control

    var isServiceEnabled: Bool {
        get { defaults.object(forKey: UD.serviceEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.serviceEnabled) }
    }
    var isAutoAcOnUnlock: Bool {
        get { defaults.bool(forKey: UD.autoAcOnUnlock) }
        set { defaults.set(newValue, forKey: UD.autoAcOnUnlock) }
    }
    var isAutoAcOffOnLock: Bool {
        get { defaults.bool(forKey: UD.autoAcOffOnLock) }
        set { defaults.set(newValue, forKey: UD.autoAcOffOnLock) }
    }
    var acTargetTemp: Float {
        get { defaults.object(forKey: UD.acTargetTemp) as? Float ?? 22.0 }
        set { defaults.set(newValue, forKey: UD.acTargetTemp) }
    }
    var acWindLevel: Int {
        get { defaults.object(forKey: UD.acWindLevel) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: UD.acWindLevel) }
    }
    var acCycleMode: Int {
        get { defaults.object(forKey: UD.acCycleMode) as? Int ?? 2 }
        set { defaults.set(newValue, forKey: UD.acCycleMode) }
    }
    // 0=Balanced, 1=LowLatency, 2=LowPower
    var bleScanMode: Int {
        get { defaults.object(forKey: UD.bleScanMode) as? Int ?? 1 }
        set { defaults.set(newValue, forKey: UD.bleScanMode) }
    }

    // MARK: - Vehicle Model

    static let vehicleModels = ["ATTO 3", "SEAL", "DOLPHIN", "SEALION 7", "기타"]

    var vehicleModel: String {
        get { defaults.string(forKey: "vehicle_model") ?? "" }
        set { defaults.set(newValue, forKey: "vehicle_model") }
    }

    // MARK: - Geofencing

    var isGeofencingEnabled: Bool {
        get { defaults.bool(forKey: UD.geofencingEnabled) }
        set { defaults.set(newValue, forKey: UD.geofencingEnabled) }
    }
    /// 지오펜스 반경 (미터). 범위: 50~500m, 기본값: 150m
    var geofenceRadius: Int {
        get { defaults.object(forKey: UD.geofenceRadius) as? Int ?? 150 }
        set { defaults.set(max(50, min(500, newValue)), forKey: UD.geofenceRadius) }
    }
    var isAutoUnlockOnApproach: Bool {
        get { defaults.object(forKey: UD.autoUnlockOnApproach) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.autoUnlockOnApproach) }
    }
    var isAutoLockOnDeparture: Bool {
        get { defaults.object(forKey: UD.autoLockOnDeparture) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.autoLockOnDeparture) }
    }

    // MARK: - Last Vehicle Location

    var lastVehicleLat: Double {
        get { defaults.double(forKey: UD.lastVehicleLat) }
        set { defaults.set(newValue, forKey: UD.lastVehicleLat) }
    }
    var lastVehicleLng: Double {
        get { defaults.double(forKey: UD.lastVehicleLng) }
        set { defaults.set(newValue, forKey: UD.lastVehicleLng) }
    }
    var lastVehicleTime: TimeInterval {
        get { defaults.double(forKey: UD.lastVehicleTime) }
        set { defaults.set(newValue, forKey: UD.lastVehicleTime) }
    }
    var lastVehicleSource: String? {
        get { defaults.string(forKey: UD.lastVehicleSource) }
        set { defaults.set(newValue, forKey: UD.lastVehicleSource) }
    }

    // MARK: - Notifications

    var notifyLockUnlock: Bool {
        get { defaults.object(forKey: UD.notifyLockUnlock) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.notifyLockUnlock) }
    }
    var notifySignalLost: Bool {
        get { defaults.object(forKey: UD.notifySignalLost) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.notifySignalLost) }
    }
    var notifyAc: Bool {
        get { defaults.object(forKey: UD.notifyAc) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.notifyAc) }
    }
    var notifyService: Bool {
        get { defaults.object(forKey: UD.notifyService) as? Bool ?? false }
        set { defaults.set(newValue, forKey: UD.notifyService) }
    }
    var notifyLowBattery: Bool {
        get { defaults.object(forKey: UD.notifyLowBattery) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.notifyLowBattery) }
    }
    var lowBatteryThreshold: Int {
        get { defaults.object(forKey: UD.lowBatteryThreshold) as? Int ?? 20 }
        set { defaults.set(newValue, forKey: UD.lowBatteryThreshold) }
    }

    // MARK: - BLE 직접 제어 — Watch 페어링 토큰 (Keychain)

    var watchEncryToken: String? {
        get { KeychainHelper.load(forKey: KC.watchEncryToken) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.watchEncryToken) } else { KeychainHelper.delete(forKey: KC.watchEncryToken) } }
    }
    var watchSignToken: String? {
        get { KeychainHelper.load(forKey: KC.watchSignToken) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.watchSignToken) } else { KeychainHelper.delete(forKey: KC.watchSignToken) } }
    }
    var watchControlPwd: String? {
        get { KeychainHelper.load(forKey: KC.watchControlPwd) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.watchControlPwd) } else { KeychainHelper.delete(forKey: KC.watchControlPwd) } }
    }
    /// 차량 BLE 디지털 키 (dkey) — 이 값이 있으면 BLE 직접 제어 가능
    var bleDkey: String? {
        get { KeychainHelper.load(forKey: KC.bleDkey) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.bleDkey) } else { KeychainHelper.delete(forKey: KC.bleDkey) } }
    }
    var blePassword: String? {
        get { KeychainHelper.load(forKey: KC.blePassword) }
        set { if let v = newValue { KeychainHelper.save(v, forKey: KC.blePassword) } else { KeychainHelper.delete(forKey: KC.blePassword) } }
    }

    // MARK: - BLE 직접 제어 — Watch 페어링 상태 / 차량 BLE 정보 (UserDefaults)

    var watchQrUuid: String? {
        get { defaults.string(forKey: UD.watchQrUuid) }
        set { defaults.set(newValue, forKey: UD.watchQrUuid) }
    }
    var watchIdentifier: String? {
        get { defaults.string(forKey: UD.watchIdentifier) }
        set { defaults.set(newValue, forKey: UD.watchIdentifier) }
    }
    var watchUserType: String? {
        get { defaults.string(forKey: UD.watchUserType) }
        set { defaults.set(newValue, forKey: UD.watchUserType) }
    }
    var watchVin: String? {
        get { defaults.string(forKey: UD.watchVin) }
        set { defaults.set(newValue, forKey: UD.watchVin) }
    }
    var watchVehicleInfoJson: String? {
        get { defaults.string(forKey: UD.watchVehicleInfoJson) }
        set { defaults.set(newValue, forKey: UD.watchVehicleInfoJson) }
    }
    /// Watch API용 기기 식별자 시드 (실제 IMEI 아님 — 로컬 랜덤 UUID, Android ANDROID_ID 폴백과 동등)
    var watchImeiSeed: String {
        if let existing = defaults.string(forKey: UD.watchImeiSeed) { return existing }
        let seed = UUID().uuidString
        defaults.set(seed, forKey: UD.watchImeiSeed)
        return seed
    }
    var bleMacAddress: String? {
        get { defaults.string(forKey: UD.bleMacAddress) }
        set { defaults.set(newValue, forKey: UD.bleMacAddress) }
    }
    var bleKeyNumber: Int64 {
        get { Int64(defaults.string(forKey: UD.bleKeyNumber) ?? "0") ?? 0 }
        set { defaults.set(String(newValue), forKey: UD.bleKeyNumber) }
    }
    var bleAuthProtocol: Int {
        get { defaults.object(forKey: UD.bleAuthProtocol) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: UD.bleAuthProtocol) }
    }

    /// BLE 직접 제어에 필요한 dkey를 확보했는지 여부
    var hasBleDkey: Bool { !(bleDkey ?? "").isEmpty }

    // MARK: - Clear Auth

    func clearAuth() {
        [KC.username, KC.password, KC.pin, KC.userId, KC.signToken, KC.encryToken, KC.vins, KC.selectedVin]
            .forEach { KeychainHelper.delete(forKey: $0) }
        hasCredentials = false
    }

    /// Watch 페어링 자격증명 + dkey 전체 삭제 (BLE 직접 제어 등록 초기화)
    func clearWatchCredentials() {
        [KC.watchEncryToken, KC.watchSignToken, KC.watchControlPwd, KC.bleDkey, KC.blePassword]
            .forEach { KeychainHelper.delete(forKey: $0) }
        [UD.watchQrUuid, UD.watchIdentifier, UD.watchUserType, UD.watchVin, UD.watchVehicleInfoJson,
         UD.bleMacAddress, UD.bleKeyNumber, UD.bleAuthProtocol]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
