import Foundation

struct ChargingStatus {
    var isCharging: Bool = false
    var isConnected: Bool = false
    var batteryPercentage: Int = 0
    var remainingHours: Int = -1
    var remainingMinutes: Int = -1
    var chargeRate: Double = 0.0
}
