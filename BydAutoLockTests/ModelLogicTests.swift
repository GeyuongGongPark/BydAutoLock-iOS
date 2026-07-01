import XCTest
import CoreLocation
@testable import BydAutoLock

final class ModelLogicTests: XCTestCase {

    func testVehicleStatusIsDrivingWhenPowerGearIsOn() {
        let status = VehicleStatus(powerGear: 3, speed: 0)

        XCTAssertTrue(status.isDriving)
    }

    func testVehicleStatusIsDrivingWhenSpeedIsPositive() {
        let status = VehicleStatus(powerGear: 1, speed: 0.1)

        XCTAssertTrue(status.isDriving)
    }

    func testVehicleStatusIsNotDrivingWhenPowerOffAndStopped() {
        let status = VehicleStatus(powerGear: 1, speed: 0)

        XCTAssertFalse(status.isDriving)
    }

    func testGpsInfoValidityRejectsNearZeroCoordinates() {
        XCTAssertFalse(GpsInfo(latitude: 0.05, longitude: -0.05).isValid)
        XCTAssertTrue(GpsInfo(latitude: 37.5665, longitude: 126.9780).isValid)
    }

    func testGpsInfoCoordinateUsesStoredLatitudeAndLongitude() {
        let gps = GpsInfo(latitude: 37.5665, longitude: 126.9780)

        XCTAssertEqual(gps.coordinate.latitude, 37.5665, accuracy: 0.0001)
        XCTAssertEqual(gps.coordinate.longitude, 126.9780, accuracy: 0.0001)
    }
}
