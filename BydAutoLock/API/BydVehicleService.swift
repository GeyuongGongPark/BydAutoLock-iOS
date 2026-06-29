import Foundation

/// BYD 차량 원격 제어 및 상태 조회 API 클라이언트
/// Android BydVehicleService.java를 Swift async/await로 포팅
actor BydVehicleService {

    private let config: BydConfig
    private let codec: BangcleCodec
    private let session: URLSession

    private(set) var userId: String?
    private(set) var signToken: String?
    private(set) var encryToken: String?
    private var accountImeiMD5 = "00000000000000000000000000000000"

    // 세션 갱신 콜백
    var onSessionUpdated: ((String, String, String) -> Void)?
    var onSessionExpired: (() -> Void)?

    // 자격증명 (세션 만료 시 자동 재로그인)
    private var storedUsername: String?
    private var storedPassword: String?
    private var isRelogging = false

    private let deviceProfile: [String: String] = [
        "ostype": "and",
        "imei": "BANGCLE01234",
        "mac": "00:00:00:00:00:00",
        "model": "POCO F1",
        "sdk": "35",
        "mod": "Xiaomi",
        "mobileBrand": "XIAOMI",
        "mobileModel": "POCO F1",
        "deviceType": "0",
        "networkType": "wifi",
        "osType": "15",
        "osVersion": "35",
        "appInnerVersion": "322",
        "appVersion": "3.2.2"
    ]

    var isLoggedIn: Bool { signToken != nil && !(signToken?.isEmpty ?? true) }

    init(config: BydConfig) throws {
        self.config = config
        self.codec = try BangcleCodec()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: sessionConfig)
    }

    func setCredentials(username: String, password: String) {
        storedUsername = username
        storedPassword = password
        if !username.isEmpty {
            accountImeiMD5 = CryptoUtils.md5Hex(username)
        }
    }

    func restoreSession(userId: String, signToken: String, encryToken: String) {
        self.userId = userId
        self.signToken = signToken
        self.encryToken = encryToken
    }

    // MARK: - JSON Helpers

    private func toSortedJSON(_ map: [(key: String, value: Any?)]) -> String {
        var parts = [String]()
        for (key, value) in map {
            let valStr: String
            if let v = value as? String {
                let escaped = v.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
                valStr = "\"\(escaped)\""
            } else if let v = value {
                valStr = "\(v)"
            } else {
                valStr = "null"
            }
            parts.append("\"\(key)\":\(valStr)")
        }
        return "{\(parts.joined(separator: ","))}"
    }

    private func buildInnerBase(vin: String? = nil, requestSerial: String? = nil) -> [(key: String, value: Any?)] {
        var map: [(key: String, value: Any?)] = [
            ("deviceType",    deviceProfile["deviceType"] ?? ""),
            ("imeiMD5",       accountImeiMD5),
            ("networkType",   deviceProfile["networkType"] ?? ""),
            ("random",        String(CryptoUtils.md5Hex("\(Double.random(in: 0...1))").prefix(16))),
            ("timeStamp",     "\(Int64(Date().timeIntervalSince1970 * 1000))"),
            ("version",       deviceProfile["appInnerVersion"] ?? "")
        ]
        if let v = vin           { map.append(("vin", v)) }
        if let r = requestSerial { map.append(("requestSerial", r)) }
        return map
    }

    // MARK: - Authenticated Request

    private func postTokenSecure(endpoint: String, innerMap: [(key: String, value: Any?)], vin: String?) async throws -> [String: Any] {
        guard let uid = userId, let signTok = signToken, let encTok = encryToken else {
            throw BydError.notLoggedIn
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let reqTimestamp = "\(nowMs)"
        let innerJson = toSortedJSON(innerMap)
        let encryData = try CryptoUtils.aesEncryptHex(innerJson, keyHex: CryptoUtils.md5Hex(encTok))

        var signFields = [String: String]()
        for (k, v) in innerMap { signFields[k] = "\(v ?? "null")" }
        signFields["countryCode"]  = config.countryCode
        signFields["identifier"]   = uid
        signFields["imeiMD5"]      = accountImeiMD5
        signFields["language"]     = config.language
        signFields["reqTimestamp"] = reqTimestamp
        let sign = CryptoUtils.sha1Mixed(
            CryptoUtils.buildSignString(signFields, password: CryptoUtils.md5Hex(signTok))
        )

        var outerMap: [(key: String, value: Any?)] = [
            ("countryCode",  config.countryCode),
            ("encryData",    encryData),
            ("identifier",   uid),
            ("imeiMD5",      accountImeiMD5),
            ("language",     config.language),
            ("reqTimestamp", reqTimestamp),
            ("sign",         sign),
            ("ostype",       deviceProfile["ostype"]),
            ("imei",         deviceProfile["imei"]),
            ("mac",          deviceProfile["mac"]),
            ("model",        deviceProfile["model"]),
            ("sdk",          deviceProfile["sdk"]),
            ("mod",          deviceProfile["mod"]),
            ("serviceTime",  reqTimestamp)
        ]
        let outerJsonNoCheck = toSortedJSON(outerMap)
        let checkcode = CryptoUtils.computeCheckcode(outerJsonNoCheck)
        outerMap.append(("checkcode", checkcode))
        let finalOuterJson = toSortedJSON(outerMap)

        let encodedRequest = try codec.encodeEnvelope(finalOuterJson)
        let body = try JSONSerialization.data(withJSONObject: ["request": encodedRequest])
        guard let url = URL(string: config.baseURL + endpoint) else { throw BydError.invalidResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = body

        let (data, _) = try await session.data(for: req)
        guard let bodyJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encodedResponse = bodyJson["response"] as? String else {
            throw BydError.invalidResponse
        }
        var decoded = try codec.decodeEnvelope(encodedResponse).trimmingCharacters(in: .whitespaces)
        if decoded.hasPrefix("F{") || decoded.hasPrefix("F[") { decoded = String(decoded.dropFirst()) }

        guard let decodedData = decoded.data(using: .utf8),
              let outerResp = try JSONSerialization.jsonObject(with: decodedData) as? [String: Any] else {
            throw BydError.invalidResponse
        }
        let resCode = outerResp["code"] as? String ?? "0"

        if resCode != "0" {
            if ["1002", "1005", "1010"].contains(resCode) {
                // 세션 만료 → 자동 재로그인
                return try await silentReLogin(endpoint: endpoint, innerMap: innerMap, vin: vin)
            }
            throw BydError.serverError(outerResp["message"] as? String ?? "Unknown", resCode)
        }

        let respondData = outerResp["respondData"] as? String ?? ""
        if respondData.isEmpty { return outerResp }

        let innerText = try CryptoUtils.aesDecryptUTF8(respondData, keyHex: CryptoUtils.md5Hex(encTok))
        guard let innerData = innerText.data(using: .utf8) else { throw BydError.invalidResponse }
        if innerText.hasPrefix("[") {
            guard let arr = try JSONSerialization.jsonObject(with: innerData) as? [[String: Any]] else {
                throw BydError.invalidResponse
            }
            return ["list": arr]
        }
        guard let result = try JSONSerialization.jsonObject(with: innerData) as? [String: Any] else {
            throw BydError.invalidResponse
        }
        return result
    }

    private func silentReLogin(endpoint: String, innerMap: [(key: String, value: Any?)], vin: String?) async throws -> [String: Any] {
        // 재로그인 중 재진입 방지 (무한 재귀 차단)
        guard !isRelogging else { throw BydError.sessionExpired }
        guard let user = storedUsername, let pwd = storedPassword, !user.isEmpty else {
            onSessionExpired?()
            throw BydError.sessionExpired
        }
        isRelogging = true
        defer { isRelogging = false }
        _ = try await login(username: user, password: pwd)
        return try await postTokenSecure(endpoint: endpoint, innerMap: innerMap, vin: vin)
    }

    // MARK: - Login

    func login(username: String, password: String) async throws -> String {
        let derivedImeiMD5 = CryptoUtils.md5Hex(username)
        accountImeiMD5 = derivedImeiMD5
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let reqTimestamp = "\(nowMs)"
        let randomHex = String(CryptoUtils.md5Hex("\(Double.random(in: 0...1))").prefix(32))

        let innerMap: [(key: String, value: Any?)] = [
            ("agreeStatus",     "0"),
            ("agreementType",   "[1,2]"),
            ("appInnerVersion", deviceProfile["appInnerVersion"] ?? ""),
            ("appVersion",      deviceProfile["appVersion"] ?? ""),
            ("deviceName",      "\(deviceProfile["mobileBrand"] ?? "")\(deviceProfile["mobileModel"] ?? "")"),
            ("deviceType",      deviceProfile["deviceType"] ?? ""),
            ("imeiMD5",         derivedImeiMD5),
            ("isAuto",          "1"),
            ("mobileBrand",     deviceProfile["mobileBrand"] ?? ""),
            ("mobileModel",     deviceProfile["mobileModel"] ?? ""),
            ("networkType",     deviceProfile["networkType"] ?? ""),
            ("osType",          deviceProfile["osType"] ?? ""),
            ("osVersion",       deviceProfile["osVersion"] ?? ""),
            ("random",          randomHex),
            ("softType",        "0"),
            ("timeStamp",       reqTimestamp),
            ("timeZone",        config.timeZone)
        ]

        let innerJson = toSortedJSON(innerMap)
        let loginKey = CryptoUtils.pwdLoginKey(password)
        let encryData = try CryptoUtils.aesEncryptHex(innerJson, keyHex: loginKey)

        var signFields = [String: String]()
        for (k, v) in innerMap { signFields[k] = "\(v ?? "null")" }
        signFields["appName"]       = "pyBYD+0.1.dev2+ge0a1f5e27"
        signFields["countryCode"]   = config.countryCode
        signFields["functionType"]  = "pwdLogin"
        signFields["identifier"]    = username
        signFields["identifierType"] = "0"
        signFields["language"]      = config.language
        signFields["reqTimestamp"]  = reqTimestamp
        let sign = CryptoUtils.sha1Mixed(
            CryptoUtils.buildSignString(signFields, password: CryptoUtils.md5Hex(password))
        )

        var outerMap: [(key: String, value: Any?)] = [
            ("appName",       "pyBYD+0.1.dev2+ge0a1f5e27"),
            ("countryCode",   config.countryCode),
            ("encryData",     encryData),
            ("functionType",  "pwdLogin"),
            ("identifier",    username),
            ("identifierType","0"),
            ("imeiMD5",       derivedImeiMD5),
            ("isAuto",        "1"),
            ("language",      config.language),
            ("reqTimestamp",  reqTimestamp),
            ("sign",          sign),
            ("signKey",       password),
            ("ostype",        deviceProfile["ostype"]),
            ("imei",          deviceProfile["imei"]),
            ("mac",           deviceProfile["mac"]),
            ("model",         deviceProfile["model"]),
            ("sdk",           deviceProfile["sdk"]),
            ("mod",           deviceProfile["mod"]),
            ("serviceTime",   reqTimestamp)
        ]
        let outerJsonNoCheck = toSortedJSON(outerMap)
        let checkcode = CryptoUtils.computeCheckcode(outerJsonNoCheck)
        outerMap.append(("checkcode", checkcode))
        let finalOuterJson = toSortedJSON(outerMap)

        let encodedRequest = try codec.encodeEnvelope(finalOuterJson)
        let body = try JSONSerialization.data(withJSONObject: ["request": encodedRequest])
        guard let url = URL(string: config.baseURL + "/app/account/login") else { throw BydError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let (data, _) = try await session.data(for: request)
        guard let bodyJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encodedResponse = bodyJson["response"] as? String else {
            throw BydError.invalidResponse
        }
        var decoded = try codec.decodeEnvelope(encodedResponse).trimmingCharacters(in: .whitespaces)
        if decoded.hasPrefix("F{") { decoded = String(decoded.dropFirst()) }

        guard let decodedData = decoded.data(using: .utf8),
              let outerResp = try JSONSerialization.jsonObject(with: decodedData) as? [String: Any] else {
            throw BydError.invalidResponse
        }
        let resCode = outerResp["code"] as? String ?? "0"
        guard resCode == "0" else {
            throw BydError.serverError(outerResp["message"] as? String ?? "Login failed", resCode)
        }

        guard let respondData = outerResp["respondData"] as? String else { throw BydError.invalidResponse }
        let innerText = try CryptoUtils.aesDecryptUTF8(respondData, keyHex: loginKey)
        guard let innerData = innerText.data(using: .utf8),
              let innerResp = try JSONSerialization.jsonObject(with: innerData) as? [String: Any],
              let token = innerResp["token"] as? [String: Any] else {
            throw BydError.invalidResponse
        }

        guard let uid   = token["userId"]    as? String,
              let sign  = token["signToken"]  as? String,
              let encry = token["encryToken"] as? String else {
            throw BydError.invalidResponse
        }
        userId     = uid
        signToken  = sign
        encryToken = encry

        storedUsername = username
        storedPassword = password

        onSessionUpdated?(uid, sign, encry)
        return uid
    }

    // MARK: - Vehicle List

    func fetchVehicleList() async throws -> [String] {
        let result = try await postTokenSecure(endpoint: "/app/account/getAllListByUserId",
                                               innerMap: buildInnerBase(), vin: nil)
        let list = result["list"] as? [[String: Any]] ?? []
        return list.compactMap { $0["vin"] as? String }
    }

    // MARK: - Vehicle Status

    func fetchVehicleStatus(vin: String) async throws -> VehicleStatus {
        var inner = buildInnerBase(vin: vin)
        inner.append(("energyType", "0"))
        inner.append(("tboxVersion", "3"))

        let triggerResult = try await postTokenSecure(
            endpoint: "/vehicleInfo/vehicle/vehicleRealTimeRequest",
            innerMap: inner, vin: vin
        )
        let serial = triggerResult["requestSerial"] as? String

        var pollInner = buildInnerBase(vin: vin, requestSerial: serial)
        pollInner.append(("energyType", "0"))
        pollInner.append(("tboxVersion", "3"))

        let result = try await postTokenSecure(
            endpoint: "/vehicleInfo/vehicle/vehicleRealTimeResult",
            innerMap: pollInner, vin: vin
        )

        var status = VehicleStatus()
        status.batteryPercentage = (result["soc"] as? Int) ?? (result["elecPercent"] as? Int) ?? 0
        status.drivingRange      = (result["mileageEV"] as? Double) ?? (result["enduranceMileage"] as? Double) ?? 0.0

        let lf = result["leftFrontDoorLock"]  as? Int ?? 0
        let rf = result["rightFrontDoorLock"] as? Int ?? 0
        let lr = result["leftRearDoorLock"]   as? Int ?? 0
        let rr = result["rightRearDoorLock"]  as? Int ?? 0
        let hasAny = lf != 0 || rf != 0 || lr != 0 || rr != 0
        status.isLocked = hasAny && (lf == 2 && rf == 2 && lr == 2 && rr == 2)

        let rawTemp = (result["interiorTemp"] as? Double) ?? (result["tempInCar"] as? Double) ?? 0.0
        status.interiorTemperature = (rawTemp > -40 && rawTemp < 100) ? rawTemp : 0.0
        status.powerGear = result["powerGear"] as? Int ?? -1
        status.epb       = result["epb"]       as? Int ?? -1
        status.speed     = result["speed"]     as? Double ?? 0.0

        // HVAC 상태를 별도로 조회
        if let hvacResult = try? await fetchHvacStatusRaw(vin: vin) {
            status.isClimateOn = (hvacResult["status"] as? Int ?? 0) == 1
            if status.interiorTemperature == 0.0 {
                let hvacTemp = hvacResult["tempInCar"] as? Double ?? 0.0
                if hvacTemp != 0.0 && hvacTemp != -129.0 { status.interiorTemperature = hvacTemp }
            }
        }
        return status
    }

    // MARK: - HVAC

    func fetchHvacStatusRaw(vin: String) async throws -> [String: Any] {
        let result = try await postTokenSecure(
            endpoint: "/control/getStatusNow",
            innerMap: buildInnerBase(vin: vin), vin: vin
        )
        return (result["statusNow"] as? [String: Any]) ?? result
    }

    func fetchHvacStatus(vin: String) async throws -> HvacStatus {
        let target = try await fetchHvacStatusRaw(vin: vin)
        return HvacStatus(
            isAcOn:               (target["status"] as? Int ?? 0) == 1,
            interiorTemperature:  target["tempInCar"]          as? Double ?? 0.0,
            exteriorTemperature:  target["tempOutCar"]         as? Double ?? 0.0,
            targetTemperature:    target["mainSettingTempNew"] as? Double ?? 0.0,
            windLevel:            target["windPosition"]        as? Int    ?? 0,
            cycleMode:            target["cycleChoice"]         as? Int    ?? 0,
            airConditioningMode:  target["airConditioningMode"] as? Int    ?? 0
        )
    }

    // MARK: - GPS

    func fetchGpsInfo(vin: String) async throws -> GpsInfo {
        let trigger = try await postTokenSecure(
            endpoint: "/control/getGpsInfo",
            innerMap: buildInnerBase(vin: vin), vin: vin
        )
        let serial = trigger["requestSerial"] as? String

        let result = try await postTokenSecure(
            endpoint: "/control/getGpsInfoResult",
            innerMap: buildInnerBase(vin: vin, requestSerial: serial), vin: vin
        )

        let data = (result["data"] as? [String: Any]) ?? result
        return GpsInfo(
            latitude:  data["latitude"]     as? Double ?? 0.0,
            longitude: data["longitude"]    as? Double ?? 0.0,
            speed:     data["speed"]        as? Double ?? 0.0,
            direction: data["direction"]    as? Double ?? 0.0,
            timestamp: data["gpsTimeStamp"] as? Double ?? 0
        )
    }

    // MARK: - Charging

    func fetchChargingStatus(vin: String) async throws -> ChargingStatus {
        let result = try await postTokenSecure(
            endpoint: "/control/smartCharge/homePage",
            innerMap: buildInnerBase(vin: vin), vin: vin
        )
        return ChargingStatus(
            isCharging:        (result["chargingState"] as? Int ?? 0) == 1,
            isConnected:       (result["connectState"]  as? Int ?? 0) >= 1,
            batteryPercentage: (result["soc"] as? Int) ?? (result["elecPercent"] as? Int) ?? 0,
            remainingHours:    result["fullHour"]   as? Int ?? -1,
            remainingMinutes:  result["fullMinute"] as? Int ?? -1,
            chargeRate:        result["rate"]       as? Double ?? 0.0
        )
    }

    // MARK: - Remote Control

    private func pollControlResult(vin: String, commandType: String, serial: String, pin: String, attempt: Int) async throws -> Bool {
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2초 대기

        var inner = buildInnerBase(vin: vin, requestSerial: serial)
        inner.append(("commandType", commandType))
        inner.append(("commandPwd", CryptoUtils.md5Hex(pin)))

        let result = try await postTokenSecure(
            endpoint: "/control/remoteControlResult",
            innerMap: inner, vin: vin
        )

        let controlState = result["controlState"] as? Int ?? 0
        let res          = result["res"]          as? Int ?? 0

        if controlState == 1 || res == 2 { return true }
        if controlState == 2 || res > 2 {
            throw BydError.controlFailed(result["message"] as? String ?? result["msg"] as? String ?? "실패")
        }
        guard attempt < 10 else { throw BydError.controlTimeout }
        return try await pollControlResult(vin: vin, commandType: commandType, serial: serial, pin: pin, attempt: attempt + 1)
    }

    private func sendRemoteControl(vin: String, commandType: String, params: [String: Any]? = nil, pin: String, fireAndForget: Bool = false) async throws -> Bool {
        var inner = buildInnerBase(vin: vin)
        inner.append(("commandType", commandType))
        inner.append(("commandPwd", CryptoUtils.md5Hex(pin)))
        if let p = params {
            let paramsJson = try String(data: JSONSerialization.data(withJSONObject: p), encoding: .utf8) ?? "{}"
            inner.append(("controlParamsMap", paramsJson))
        }

        let result = try await postTokenSecure(
            endpoint: "/control/remoteControl",
            innerMap: inner, vin: vin
        )

        let controlState = result["controlState"] as? Int ?? 0
        let res          = result["res"]          as? Int ?? 0
        let serial       = result["requestSerial"] as? String ?? ""

        if controlState == 1 || res == 2 { return true }
        if controlState == 2 || res > 2 {
            throw BydError.controlFailed(result["message"] as? String ?? "실패")
        }
        // fire-and-forget: 명령 전송 후 폴링 없이 즉시 반환
        if fireAndForget { return true }
        guard !serial.isEmpty else { return false }
        return try await pollControlResult(vin: vin, commandType: commandType, serial: serial, pin: pin, attempt: 1)
    }

    // MARK: - Door Lock / Unlock

    func lock(vin: String, pin: String) async throws -> Bool {
        return try await sendRemoteControl(vin: vin, commandType: "LOCKDOOR", pin: pin)
    }

    func unlock(vin: String, pin: String) async throws -> Bool {
        return try await sendRemoteControl(vin: vin, commandType: "OPENDOOR", pin: pin)
    }

    /// 자동 동작용 fire-and-forget (폴링 없이 즉시 반환)
    func lockAuto(vin: String, pin: String) async throws {
        _ = try await sendRemoteControl(vin: vin, commandType: "LOCKDOOR", pin: pin, fireAndForget: true)
    }

    func unlockAuto(vin: String, pin: String) async throws {
        _ = try await sendRemoteControl(vin: vin, commandType: "OPENDOOR", pin: pin, fireAndForget: true)
    }

    // MARK: - Climate

    func startClimate(vin: String, temp: Double, durationMinutes: Int, cycleMode: Int = 2, windLevel: Int? = nil, pin: String) async throws -> Bool {
        var params: [String: Any] = [
            "mainSettingTemp":     celsiusToScale(temp),
            "mainSettingTempNew":  temp * 2.0,
            "copilotSettingTemp":  celsiusToScale(temp),
            "copilotSettingTempNew": temp * 2.0,
            "cycleMode":           cycleMode,
            "timeSpan":            minutesToTimeSpan(durationMinutes),
            "remoteMode":          4,
            "airAccuracy":         1
        ]
        if let wl = windLevel {
            params["airConditioningMode"] = 2
            params["windLevel"] = wl
        } else {
            params["airConditioningMode"] = 1
        }
        return try await sendRemoteControl(vin: vin, commandType: "OPENAIR", params: params, pin: pin)
    }

    func stopClimate(vin: String, pin: String) async throws -> Bool {
        return try await sendRemoteControl(vin: vin, commandType: "CLOSEAIR", pin: pin)
    }

    // MARK: - Other Commands

    func openWindows(vin: String, pin: String)  async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "OPENWINDOW", pin: pin) }
    func closeWindows(vin: String, pin: String) async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "CLOSEWINDOW", pin: pin) }
    func openTrunk(vin: String, pin: String)    async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "OPENTRUNK", pin: pin) }
    func closeTrunk(vin: String, pin: String)   async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "CLOSETRUNK", pin: pin) }
    func findCar(vin: String, pin: String)      async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "FINDCAR", pin: pin) }
    func flashLights(vin: String, pin: String)  async throws -> Bool { try await sendRemoteControl(vin: vin, commandType: "FLASHLIGHTNOWHISTLE", pin: pin) }

    func heatBattery(vin: String, on: Bool, pin: String) async throws -> Bool {
        return try await sendRemoteControl(vin: vin, commandType: "BATTERYHEAT",
                                           params: ["batteryHeatSwitch": on ? 1 : 0], pin: pin)
    }

    // MARK: - Helpers

    private func celsiusToScale(_ temp: Double) -> Int {
        return max(1, min(17, Int((temp - 14.0).rounded())))
    }

    private func minutesToTimeSpan(_ minutes: Int) -> Int {
        switch minutes {
        case 10: return 1
        case 15: return 2
        case 20: return 3
        case 25: return 4
        case 30: return 5
        default: return 2
        }
    }
}

// MARK: - Error Types

enum BydError: LocalizedError {
    case notLoggedIn
    case sessionExpired
    case invalidResponse
    case serverError(String, String)
    case controlFailed(String)
    case controlTimeout
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:            return "로그인이 필요합니다"
        case .sessionExpired:         return "세션이 만료되었습니다"
        case .invalidResponse:        return "잘못된 응답 형식"
        case .serverError(let m, let c): return "서버 오류: \(m) (\(c))"
        case .controlFailed(let m):   return "제어 실패: \(m)"
        case .controlTimeout:         return "제어 시간 초과"
        case .networkError(let e):    return "네트워크 오류: \(e.localizedDescription)"
        }
    }
}
