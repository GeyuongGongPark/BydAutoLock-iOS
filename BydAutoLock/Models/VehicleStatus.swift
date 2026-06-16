import Foundation

struct VehicleStatus {
    var batteryPercentage: Int = 0
    var drivingRange: Double = 0.0
    var isLocked: Bool = false
    var isClimateOn: Bool = false
    var interiorTemperature: Double = 0.0
    var powerGear: Int = -1  // -1: 알 수 없음, 1: OFF, 3: ON
    var epb: Int = -1         // -1: 알 수 없음, 0: 해제, 1: 체결
    var speed: Double = 0.0

    /// 주행 중 여부 (powerGear=3 또는 speed>0)
    var isDriving: Bool {
        return powerGear == 3 || speed > 0.0
    }
}
