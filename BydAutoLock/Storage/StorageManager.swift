import Foundation

/// 설정 및 자격증명 저장소
/// - 민감 데이터(계정, 토큰): Keychain
/// - 일반 설정: UserDefaults
final class StorageManager {

    static let shared = StorageManager()
    private let defaults = UserDefaults.standard
    private let widgetDefaults = UserDefaults(suiteName: "group.com.ggpark.bydautolock")
    private init() {}

    // MARK: - Widget / Watch 공유 데이터

    func saveWidgetData(isRunning: Bool, isLocked: Bool?, battery: Int?, rssi: Int?) {
        widgetDefaults?.set(isRunning, forKey: "widget_isRunning")
        if let v = isLocked { widgetDefaults?.set(v, forKey: "widget_isLocked") }
        if let v = battery  { widgetDefaults?.set(v, forKey: "widget_battery") }
        if let v = rssi     { widgetDefaults?.set(v, forKey: "widget_rssi") }
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
    }

    // MARK: - UserDefaults Keys

    private enum UD {
        static let region            = "byd_region"
        static let hasCredentials    = "has_credentials"
        static let deviceMac         = "bt_device_mac"
        static let deviceName        = "bt_device_name"
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
        static let autoUnlockOnApproach  = "auto_unlock_on_approach"
        static let autoLockOnDeparture   = "auto_lock_on_departure"
        static let debugLoggingEnabled   = "debug_logging_enabled"
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

    // MARK: - Geofencing

    var isGeofencingEnabled: Bool {
        get { defaults.bool(forKey: UD.geofencingEnabled) }
        set { defaults.set(newValue, forKey: UD.geofencingEnabled) }
    }
    var isAutoUnlockOnApproach: Bool {
        get { defaults.object(forKey: UD.autoUnlockOnApproach) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.autoUnlockOnApproach) }
    }
    var isAutoLockOnDeparture: Bool {
        get { defaults.object(forKey: UD.autoLockOnDeparture) as? Bool ?? true }
        set { defaults.set(newValue, forKey: UD.autoLockOnDeparture) }
    }

    // MARK: - Debug

    var isDebugLoggingEnabled: Bool {
        get { defaults.bool(forKey: UD.debugLoggingEnabled) }
        set { defaults.set(newValue, forKey: UD.debugLoggingEnabled) }
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

    // MARK: - Clear Auth

    func clearAuth() {
        [KC.username, KC.password, KC.pin, KC.userId, KC.signToken, KC.encryToken, KC.vins, KC.selectedVin]
            .forEach { KeychainHelper.delete(forKey: $0) }
        hasCredentials = false
    }
}
