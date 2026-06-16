import Foundation

struct HvacStatus {
    var isAcOn: Bool = false
    var interiorTemperature: Double = 0.0
    var exteriorTemperature: Double = 0.0
    var targetTemperature: Double = 22.0
    var windLevel: Int = 0
    var cycleMode: Int = 2
    var airConditioningMode: Int = 1
}
