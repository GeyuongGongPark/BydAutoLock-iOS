import Foundation

/// BYD "Watch" 페어링 API 클라이언트 — BLE 직접 제어에 필요한 dkey를 확보하기 위한 별도 인증 도메인.
///
/// `BydVehicleService`(계정 로그인, `app/account/*`)와는 완전히 분리된 API다.
/// Android BydWatchKeyService.java를 Swift async/await로 포팅 (참고: PoorGrammerA/BydBleAutoLock, MIT License).
///
/// 이 API는 `BydVehicleService`와 달리 Bangcle envelope 래핑을 쓰지 않는다 — 평문 JSON을 그대로 주고받고,
/// 그 안의 `respondData` 필드만 AES-128-CBC(zero IV)로 암호화되어 있다.
actor BydWatchKeyService {

    private static let watchModel = "SM-R925N"      // 공식 Watch 앱을 스푸핑 (Galaxy Watch)
    private static let watchBrand = "SAMSUNG"
    private static let watchAppVersion = "341"

    private let config: BydConfig
    private let watchImei: String
    private let session: URLSession
    private var timeDifferenceMs: Int64 = 0

    /// - Parameters:
    ///   - config: `BydConfig.fromRegion(...)` — 메인 계정 API와 동일한 리전별 도메인을 그대로 재사용
    ///   - watchImei: 이 기기를 대표하는 로컬 식별자의 MD5 (실제 IMEI 아님, 호출부에서 시드값을 관리)
    init(config: BydConfig, watchImei: String) {
        self.config = config
        self.watchImei = watchImei
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    /// 서버 시간과의 오차를 보정 (선택적 — 실패해도 흐름을 막지 않음)
    func syncServerTime() async {
        do {
            let outer = try buildUnLoginParamsJson(.general)
            guard let decrypted = try await executeRequest(
                endpoint: "watch/login/getServerCurrentTime",
                outerJson: outer,
                decryptKeyHex: CryptoUtils.md5Hex(countryCode)
            ), let serverMs = Self.parseServerTime(decrypted) else { return }
            timeDifferenceMs = serverMs - Int64(Date().timeIntervalSince1970 * 1000)
        } catch {
            LogManager.shared.log("Watch", "서버 시간 동기화 실패 (무시하고 진행): \(error.localizedDescription)")
        }
    }

    func createQrCode() async throws -> (uuid: String, watchImei: String) {
        let outer = try buildUnLoginParamsJson(.general)
        guard let decrypted = try await executeRequest(
            endpoint: "watch/login/create/qrcode",
            outerJson: outer,
            decryptKeyHex: CryptoUtils.md5Hex(countryCode)
        ), let dict = Self.parseJSONObject(decrypted),
           let uuid = dict["uuid"] as? String, !uuid.isEmpty else {
            throw BydWatchError.invalidResponse
        }
        LogManager.shared.log("Watch", "QR 생성 완료 (uuid=\(uuid))")
        return (uuid, watchImei)
    }

    /// `codeStatus` 원본 값을 그대로 반환 ("2" == 공식 앱에서 승인됨. 그 외 값은 실기기 확인 전까지 미문서화)
    func getQrCodeStatus(uuid: String) async throws -> String {
        let outer = try buildUnLoginParamsJson(.qrStatus(uuid: uuid))
        guard let decrypted = try await executeRequest(
            endpoint: "watch/login/check/qrcode",
            outerJson: outer,
            decryptKeyHex: CryptoUtils.md5Hex(countryCode)
        ), let dict = Self.parseJSONObject(decrypted) else {
            throw BydWatchError.invalidResponse
        }
        let status = Self.stringValue(dict["codeStatus"] ?? dict["status"]) ?? "0"
        LogManager.shared.log("Watch", "QR 상태 확인: codeStatus=\(status)")
        return status
    }

    func getToken(uuid: String) async throws -> WatchToken {
        let outer = try buildUnLoginParamsJson(.token(uuid: uuid))
        guard let decrypted = try await executeRequest(
            endpoint: "watch/login/gain/token",
            outerJson: outer,
            decryptKeyHex: CryptoUtils.md5Hex(countryCode)
        ), let dict = Self.parseJSONObject(decrypted),
           let tokenInfo = dict["watchTokenInfo"] as? [String: Any] else {
            throw BydWatchError.invalidResponse
        }
        guard let encryToken = tokenInfo["encryToken"] as? String, !encryToken.isEmpty,
              let signToken = tokenInfo["signToken"] as? String, !signToken.isEmpty,
              let vin = tokenInfo["vin"] as? String, !vin.isEmpty else {
            throw BydWatchError.invalidResponse
        }
        let controlPwd = Self.stringValue(dict["controlPwd"]) ?? ""
        let userType = (tokenInfo["userType"] as? String) ?? ""
        // dkey/토큰 값 자체는 로그로 내보내지 않음(LogView 공유 기능이 있어 유출 위험) — 존재 여부만 남긴다.
        LogManager.shared.log("Watch", "토큰 교환 완료 (vin=***\(vin.suffix(4)), userType=\(userType), controlPwd 존재=\(!controlPwd.isEmpty))")
        return WatchToken(
            encryToken: encryToken,
            signToken: signToken,
            controlPwd: controlPwd,
            identifier: (tokenInfo["identifier"] as? String) ?? "",
            userType: userType,
            vin: vin
        )
    }

    /// 차량 정보 전체를 raw dictionary로 반환 (기존 `BydVehicleService` 관례와 동일).
    /// dkey/MAC 추출은 `BydWatchKeyService.extractBleInfo(fromVehicleConfig:)`를 사용.
    func getVehicleConfig(_ token: WatchToken) async throws -> [String: Any] {
        let inner = ["appVersion": "2", "vin": token.vin]
        let outer = try buildLoginParamsJson(inner, token: token)
        guard let decrypted = try await executeRequest(
            endpoint: "watch/login/gain/vehicle",
            outerJson: outer,
            decryptKeyHex: CryptoUtils.md5Hex(token.encryToken)
        ), let dict = Self.parseJSONObject(decrypted) else {
            throw BydWatchError.invalidResponse
        }
        // 값이 아니라 최상위 키 이름만 로그로 남긴다 — 응답 구조가 예상과 맞는지(예: watchBluetoothDto 존재)
        // 확인하는 용도. 값 자체(dkey 등)는 남기지 않는다.
        LogManager.shared.log("Watch", "차량정보 조회 완료 (최상위 키: \(dict.keys.sorted().joined(separator: ", ")))")
        return dict
    }

    func getWatchBlueInfo(_ token: WatchToken) async throws -> WatchBleKeyInfo {
        let inner = ["appVersion": "2", "vin": token.vin]
        let outer = try buildLoginParamsJson(inner, token: token)
        guard let decrypted = try await executeRequest(
            endpoint: "watch/login/gain/bluetooth",
            outerJson: outer,
            decryptKeyHex: CryptoUtils.md5Hex(token.encryToken)
        ), let dict = Self.parseJSONObject(decrypted) else {
            throw BydWatchError.invalidResponse
        }
        // Gson의 @SerializedName alternate처럼, 지역별로 필드명이 다르게 오는 경우를 모두 대응
        func firstString(_ keys: [String]) -> String? {
            for key in keys { if let v = dict[key] as? String, !v.isEmpty { return v } }
            return nil
        }
        func firstInt64(_ keys: [String]) -> Int64? {
            for key in keys {
                if let n = dict[key] as? NSNumber { return n.int64Value }
                if let s = dict[key] as? String, let n = Int64(s) { return n }
            }
            return nil
        }
        let result = WatchBleKeyInfo(
            dk: firstString(["dk", "DK", "dK", "dkey", "DKEY"]),
            bluetoothMacAddress: firstString(["bluetoothMacAddress", "bluetoothMACAddress", "bluetooth_mac_address", "macAddress", "mac"]),
            keyNumber: firstInt64(["empowerBluetoothKeyNo", "keyNumber", "keyNo"]),
            authBluetoothProtocol: firstInt64(["authBluetoothProtocol"]).map(Int.init),
            bluetoothPassword: firstString(["blueToothPassword", "bluetoothPassword", "BluetoothPassword", "blue_tooth_password"]),
            vin: firstString(["vin"]) ?? token.vin
        )
        // dk/password 값 자체는 남기지 않고 존재 여부만 — dkey는 물리적으로 차를 여는 키라 로그 유출 위험이 큼.
        LogManager.shared.log("Watch", "블루투스키 조회 완료 (dk 존재=\(result.dk != nil), mac 존재=\(result.bluetoothMacAddress != nil), keyNumber=\(result.keyNumber.map(String.init) ?? "없음"))")
        return result
    }

    /// 화면에 표시할 QR 코드 내용. 공식 BYD 앱(다른 기기)이 카메라로 스캔해 페어링을 승인한다.
    func buildQrCodeContent(uuid: String, watchImei: String) throws -> String {
        let plaintext = "watchImei=\(watchImei)&uuid=\(uuid)&countryCode=\(countryCode)"
        let qrKeyHex = CryptoUtils.md5Hex("watch.bydautolink")
        let encryptedHex = try CryptoUtils.aesEncryptHex(plaintext, keyHex: qrKeyHex)
        return "watchQRCode://" + encryptedHex.uppercased()
    }

    // MARK: - Vehicle config → BLE info 추출 (WatchCredentialManager.saveVehicle 포팅)

    static func extractBleInfo(fromVehicleConfig vehicle: [String: Any]) -> (dkey: String?, mac: String?, keyNumber: Int64?) {
        func object(_ dict: [String: Any], _ key: String) -> [String: Any]? { dict[key] as? [String: Any] }
        let dto = object(vehicle, "watchBluetoothDto") ?? object(vehicle, "cfVechicle").flatMap { object($0, "watchBluetoothDto") }
        guard let dto else { return (nil, nil, nil) }
        let mac = dto["macAddress"] as? String
        let info = object(dto, "watchBluetoothInfo")
        let dkey = info?["dkey"] as? String
        let keyNumber: Int64? = {
            guard let raw = info?["keyNumber"] else { return nil }
            if let n = raw as? NSNumber { return n.int64Value }
            if let s = raw as? String { return Int64(s) }
            return nil
        }()
        return (dkey, mac, keyNumber)
    }

    // MARK: - Request building

    private enum UnLoginKind {
        case general
        case qrStatus(uuid: String)
        case token(uuid: String)
    }

    /// 미인증 엔드포인트(QR 생성/상태확인/토큰획득)용 요청 바디.
    /// 원본은 num/uuid 두 플래그로 4-branch를 만들지만 실제로는 3가지 내부 파라미터 셋만 존재한다.
    private func buildUnLoginParamsJson(_ kind: UnLoginKind) throws -> String {
        let reqTimestamp = String(nowMs())
        let random = randomHex()

        var inner: [String: String]
        switch kind {
        case .general:
            inner = ["timeStamp": reqTimestamp, "random": random, "networkType": "wifi", "version": Self.watchAppVersion]
        case .qrStatus(let uuid):
            inner = ["timeStamp": reqTimestamp, "random": random, "networkType": "wifi", "version": Self.watchAppVersion, "uuid": uuid]
        case .token(let uuid):
            inner = ["timeStamp": reqTimestamp, "uuid": uuid, "timeZone": TimeZone.current.identifier]
        }

        let encryData = try encryptInner(inner, keyHex: CryptoUtils.md5Hex(countryCode))

        let outerAdd: [String: String] = [
            "identifier": countryCode,
            "watchImei": watchImei,
            "watchModel": Self.watchModel,
            "watchName": Self.watchBrand + Self.watchModel,
            "watchBrand": Self.watchBrand,
            "watchAppVersion": Self.watchAppVersion,
            "watchOs": "0",
            "reqTimestamp": reqTimestamp,
            "language": config.language,
            "countryCode": countryCode
        ]
        let sign = computeSign(inner: inner, outerAdd: outerAdd, passwordSource: countryCode)

        return try jsonString([
            "countryCode": countryCode,
            "encryData": encryData,
            "identifier": countryCode,
            "language": config.language,
            "reqTimestamp": reqTimestamp,
            "sign": sign,
            "watchAppVersion": Self.watchAppVersion,
            "watchBrand": Self.watchBrand,
            "watchImei": watchImei,
            "watchModel": Self.watchModel,
            "watchName": Self.watchBrand + Self.watchModel,
            "watchOs": "0"
        ])
    }

    /// 인증된 엔드포인트(차량정보/블루투스키)용 요청 바디.
    private func buildLoginParamsJson(_ rawParams: [String: String], token: WatchToken) throws -> String {
        let reqTimestamp = String(nowMs())
        let random = randomHex()

        var inner: [String: String] = [
            "timeStamp": reqTimestamp,
            "random": random,
            "watchImei": watchImei,
            "deviceType": "0",
            "networkType": "wifi"
        ]
        rawParams.forEach { inner[$0.key] = $0.value }

        let encryData = try encryptInner(inner, keyHex: CryptoUtils.md5Hex(token.encryToken))
        let identifier = token.identifier.isEmpty ? countryCode : token.identifier

        let outerAdd: [String: String] = [
            "identifier": identifier,
            "watchModel": Self.watchModel,
            "watchName": Self.watchBrand + Self.watchModel,
            "watchBrand": Self.watchBrand,
            "watchAppVersion": Self.watchAppVersion,
            "watchOs": "0",
            "reqTimestamp": reqTimestamp,
            "language": config.language,
            "countryCode": countryCode,
            "userType": token.userType
        ]
        let sign = computeSign(inner: inner, outerAdd: outerAdd, passwordSource: token.signToken)

        return try jsonString([
            "identifier": identifier,
            "watchImei": watchImei,
            "watchModel": Self.watchModel,
            "watchName": Self.watchBrand + Self.watchModel,
            "watchBrand": Self.watchBrand,
            "watchAppVersion": Self.watchAppVersion,
            "watchOs": "0",
            "reqTimestamp": reqTimestamp,
            "language": config.language,
            "countryCode": countryCode,
            "userType": token.userType,
            "encryData": encryData,
            "sign": sign
        ])
    }

    /// inner(암호화 대상) + outerAdd(서명에만 참여, 바디에는 별도로 포함)를 합쳐 알파벳순 서명 문자열을 만든다.
    /// `CryptoUtils.buildSignString`이 이미 key 정렬 + `&password=` 접미를 처리하므로 그대로 재사용.
    private func computeSign(inner: [String: String], outerAdd: [String: String], passwordSource: String) -> String {
        var merged = inner
        outerAdd.forEach { merged[$0.key] = $0.value }
        return CryptoUtils.sha1Mixed(
            CryptoUtils.buildSignString(merged, password: CryptoUtils.md5Hex(passwordSource))
        )
    }

    private func encryptInner(_ inner: [String: String], keyHex: String) throws -> String {
        try CryptoUtils.aesEncryptHex(try jsonString(inner as [String: Any]), keyHex: keyHex)
    }

    // MARK: - HTTP execution

    /// 평문 JSON POST → `{"response": "{...}"}` 파싱 → `respondData` 복호화.
    /// (`BydVehicleService`와 달리 Bangcle envelope 래핑이 없다.)
    private func executeRequest(endpoint: String, outerJson: String, decryptKeyHex: String) async throws -> String? {
        guard let url = URL(string: config.baseURL + "/" + endpoint) else { throw BydWatchError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = outerJson.data(using: .utf8)

        LogManager.shared.log("Watch", "[\(endpoint)] 요청 전송 (len=\(outerJson.count))")

        let (data, response) = try await session.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LogManager.shared.log("Watch", "[\(endpoint)] 응답 파싱 실패 (HTTP \(httpStatus), 최상위 JSON이 아님)")
            throw BydWatchError.invalidResponse
        }
        guard let responseStr = (top["response"] as? String) ?? (top["respondData"] as? String),
              let envelope = Self.parseJSONObject(responseStr) else {
            LogManager.shared.log("Watch", "[\(endpoint)] 응답 파싱 실패 (HTTP \(httpStatus), response/respondData 필드 없음) — 서버 스펙이 원본과 달라졌을 수 있음")
            throw BydWatchError.invalidResponse
        }
        let code = Self.stringValue(envelope["code"]) ?? "-1"
        guard code == "0" else {
            let message = Self.stringValue(envelope["message"]) ?? ""
            LogManager.shared.log("Watch", "[\(endpoint)] 서버 오류 code=\(code) message=\(message)")
            throw BydWatchError.serverError(message, code)
        }
        LogManager.shared.log("Watch", "[\(endpoint)] 응답 성공 (code=0)")
        guard let business = (envelope["respondData"] as? String) ?? (envelope["response"] as? String),
              !business.isEmpty else {
            return nil
        }
        return try CryptoUtils.aesDecryptUTF8(business, keyHex: decryptKeyHex)
    }

    // MARK: - Small helpers

    private var countryCode: String {
        let cc = config.countryCode
        return cc.isEmpty ? "KR" : cc
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000) + timeDifferenceMs
    }

    private func randomHex() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }

    private func jsonString(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let s = String(data: data, encoding: .utf8) else { throw BydWatchError.invalidResponse }
        return s
    }

    private static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func parseServerTime(_ text: String) -> Int64? {
        if let dict = parseJSONObject(text), let raw = dict["serverTime"] {
            if let n = raw as? NSNumber { return n.int64Value }
            if let s = raw as? String { return Int64(s) }
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return Int64(trimmed)
    }
}

// MARK: - Models (원본 22필드 모델 중 실제로 사용되는 필드만 포팅)

struct WatchToken: Sendable {
    let encryToken: String
    let signToken: String
    let controlPwd: String
    let identifier: String
    let userType: String
    let vin: String
}

struct WatchBleKeyInfo: Sendable {
    let dk: String?
    let bluetoothMacAddress: String?
    let keyNumber: Int64?
    let authBluetoothProtocol: Int?
    let bluetoothPassword: String?
    let vin: String?
}

// MARK: - Error Types

enum BydWatchError: LocalizedError {
    case invalidResponse
    case serverError(String, String)
    case qrNotApproved
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:        return "잘못된 응답 형식"
        case .serverError(let m, let c): return "서버 오류: \(m) (\(c))"
        case .qrNotApproved:          return "QR이 아직 승인되지 않았습니다"
        case .timeout:                return "승인 대기 시간 초과"
        }
    }
}
