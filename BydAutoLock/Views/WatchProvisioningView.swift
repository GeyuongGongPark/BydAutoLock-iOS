import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// BLE 직접 제어에 필요한 dkey를 확보하는 화면.
/// ID/PW 저장 시 → 자가 승인(QR 스캔 불필요). 없으면 → 기존 QR 스캔 경로.
struct WatchProvisioningView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WatchProvisioningViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if case .waitingApproval = viewModel.stage {
                    Text("QR을 **다른 기기**의 공식 BYD 앱 카메라로 스캔해 승인해 주세요. 같은 폰에서는 이 화면과 BYD 앱을 동시에 열 수 없어요 — 다른 폰/태블릿으로 스캔하거나, 이 화면을 스크린샷으로 찍어 다른 기기에서 스캔하세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                content

                Spacer()
            }
            .padding()
            .navigationTitle("BLE 직접 제어 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear { viewModel.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stage {
        case .idle, .creatingQr:
            ProgressView("준비 중...")

        case .selfApproving(let message):
            VStack(spacing: 12) {
                ProgressView(message)
                Text("계정 정보로 자동 등록 중입니다")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .waitingApproval(let qrImage, let uuid):
            VStack(spacing: 12) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                ProgressView("승인 대기 중...")
                Text(uuid).font(.caption2).foregroundStyle(.secondary)
            }

        case .exchangingToken:
            ProgressView("토큰 교환 중...")

        case .fetchingVehicle:
            ProgressView("차량 정보 조회 중...")

        case .fetchingBluetoothKey:
            ProgressView("BLE 키 조회 중...")

        case .done:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("등록 완료 — BLE 직접 제어를 사용할 수 있습니다")
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("다시 시도") { viewModel.start() }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class WatchProvisioningViewModel: ObservableObject {

    enum Stage {
        case idle
        case creatingQr
        case selfApproving(String)   // 자가 승인 진행 메시지
        case waitingApproval(qrImage: UIImage, uuid: String)
        case exchangingToken
        case fetchingVehicle
        case fetchingBluetoothKey
        case done
        case failed(String)
    }

    @Published private(set) var stage: Stage = .idle

    private let storage = StorageManager.shared
    private var runTask: Task<Void, Never>?

    func start() {
        runTask?.cancel()
        stage = .creatingQr
        let hasCreds = !(storage.username ?? "").isEmpty && !(storage.password ?? "").isEmpty
        runTask = Task {
            if hasCreds {
                await runSelfApprove()
            } else {
                await runQr()
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    private func makeWatchService() -> BydWatchKeyService {
        let watchImei = CryptoUtils.md5Hex(storage.watchImeiSeed)
        return BydWatchKeyService(config: BydConfig.fromRegion(storage.region), watchImei: watchImei)
    }

    private func makeVehicleService() async throws -> BydVehicleService {
        let svc = try BydVehicleService(config: BydConfig.fromRegion(storage.region))
        await svc.setCredentials(username: storage.username ?? "", password: storage.password ?? "")
        if let uid = storage.userId, let sign = storage.signToken, let encry = storage.encryToken {
            await svc.restoreSession(userId: uid, signToken: sign, encryToken: encry)
        }
        return svc
    }

    // MARK: - 자가 승인 경로 (ID/PW 있을 때)

    private func runSelfApprove() async {
        LogManager.shared.log("Watch", "자가 승인 경로 시작 (ID/PW 저장됨)")
        let watchService = makeWatchService()
        await watchService.syncServerTime()

        do {
            // 1. QR uuid 생성
            let (uuid, watchImei) = try await watchService.createQrCode()
            storage.watchQrUuid = uuid

            // 2. 계정 API로 재로그인 + 자가 승인
            stage = .selfApproving("계정 인증 중…")
            let vehicleService = try await makeVehicleService()
            _ = try await vehicleService.login(username: storage.username ?? "", password: storage.password ?? "")

            stage = .selfApproving("차량 승인 중…")
            try await vehicleService.scanWatchLoginAction(uuid: uuid, watchImei: watchImei)

            // 3. VIN 조회 → determine
            let vins = try await vehicleService.fetchVehicleList()
            guard let vin = vins.first else {
                throw BydWatchError.serverError("계정에 등록된 차량이 없습니다", "")
            }
            try await vehicleService.scanWatchLoginDetermine(
                uuid: uuid, watchImei: watchImei, vin: vin,
                carType: nil, controlPwd: storage.pin
            )
            LogManager.shared.log("Watch", "자가 승인 완료 → 토큰 교환 시작")

            // 4. 나머지는 QR 경로와 동일
            try await exchangeTokenAndSave(watchService: watchService, uuid: uuid)
        } catch is CancellationError {
            LogManager.shared.log("Watch", "자가 승인 취소됨")
        } catch {
            LogManager.shared.log("Watch", "자가 승인 실패 (\(error.localizedDescription)) → QR 경로 fallback")
            await runQr()
        }
    }

    // MARK: - QR 경로

    private func runQr() async {
        LogManager.shared.log("Watch", "QR 등록 경로 시작")
        let service = makeWatchService()
        await service.syncServerTime()

        do {
            let (uuid, watchImei) = try await service.createQrCode()
            storage.watchQrUuid = uuid

            let qrContent = try await service.buildQrCodeContent(uuid: uuid, watchImei: watchImei)
            guard let qrImage = Self.qrImage(from: qrContent) else {
                stage = .failed("QR 이미지 생성 실패")
                return
            }
            stage = .waitingApproval(qrImage: qrImage, uuid: uuid)
            try await pollUntilApproved(service: service, uuid: uuid)
            try Task.checkCancellation()
            LogManager.shared.log("Watch", "QR 승인 확인됨 → 토큰 교환 시작")
            try await exchangeTokenAndSave(watchService: service, uuid: uuid)
        } catch is CancellationError {
            LogManager.shared.log("Watch", "등록 취소됨 (화면 닫힘)")
        } catch {
            LogManager.shared.log("Watch", "등록 실패: \(error.localizedDescription)")
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - 공통: 토큰 교환 → 차량정보 → BLE키 저장

    private func exchangeTokenAndSave(watchService: BydWatchKeyService, uuid: String) async throws {
        stage = .exchangingToken
        let token = try await watchService.getToken(uuid: uuid)
        storage.watchEncryToken = token.encryToken
        storage.watchSignToken  = token.signToken
        storage.watchControlPwd = token.controlPwd
        storage.watchIdentifier = token.identifier
        storage.watchUserType   = token.userType
        storage.watchVin        = token.vin

        stage = .fetchingVehicle
        do {
            let vehicle = try await watchService.getVehicleConfig(token)
            if let data = try? JSONSerialization.data(withJSONObject: vehicle),
               let text = String(data: data, encoding: .utf8) {
                storage.watchVehicleInfoJson = text
            }
            let extracted = BydWatchKeyService.extractBleInfo(fromVehicleConfig: vehicle)
            if let d = extracted.dkey, !d.isEmpty { storage.bleDkey = d }
            if let m = extracted.mac, !m.isEmpty { storage.bleMacAddress = m }
            if let k = extracted.keyNumber { storage.bleKeyNumber = k }
            let vDkeyHint = extracted.dkey.map { d -> String in
                let t = d.trimmingCharacters(in: .whitespaces)
                return t.count >= 8 ? "\(t.prefix(4))…\(t.suffix(4))" : "len\(t.count)"
            } ?? "없음"
            LogManager.shared.log("Watch", "gain/vehicle 저장: dkey=\(extracted.dkey != nil ? "있음(\(extracted.dkey?.count ?? 0)자) hint=\(vDkeyHint)" : "없음"), keyNumber=\(extracted.keyNumber.map(String.init) ?? "미추출→유지 \(storage.bleKeyNumber)"), mac=\(extracted.mac ?? "없음")")
        } catch {
            LogManager.shared.log("Watch", "gain/vehicle 실패 (\(error.localizedDescription)) — gain/bluetooth 폴백 시도")
        }

        stage = .fetchingBluetoothKey
        let bleKey = try await watchService.getWatchBlueInfo(token)
        if let d = bleKey.dk, !d.isEmpty { storage.bleDkey = d }
        if let m = bleKey.bluetoothMacAddress, !m.isEmpty { storage.bleMacAddress = m }
        if let k = bleKey.keyNumber { storage.bleKeyNumber = k }
        if let p = bleKey.authBluetoothProtocol { storage.bleAuthProtocol = p }
        if let pw = bleKey.bluetoothPassword, !pw.isEmpty { storage.blePassword = pw }

        let bDkeyHint = bleKey.dk.map { d -> String in
            let t = d.trimmingCharacters(in: .whitespaces)
            return t.count >= 8 ? "\(t.prefix(4))…\(t.suffix(4))" : "len\(t.count)"
        } ?? "없음"
        LogManager.shared.log("Watch", "gain/bluetooth 저장: dk=\(bleKey.dk != nil ? "있음(\(bleKey.dk?.count ?? 0)자) hint=\(bDkeyHint)" : "없음"), keyNumber=\(bleKey.keyNumber.map(String.init) ?? "미추출"), protocol=\(bleKey.authBluetoothProtocol.map(String.init) ?? "없음"), password=\(bleKey.bluetoothPassword != nil ? "있음" : "없음"), mac=\(bleKey.bluetoothMacAddress ?? "없음")")

        guard storage.hasBleDkey else {
            LogManager.shared.log("Watch", "등록 실패 - 차량정보/블루투스키 응답에 dkey 없음")
            stage = .failed("차량정보/블루투스키 응답에 dkey가 없습니다")
            return
        }
        LogManager.shared.log("Watch", "BLE 직접 제어 등록 완료 (dkey 확보됨, keyNumber저장=\(storage.hasStoredBleKeyNumber) keyNumber=\(storage.bleKeyNumber), protocol저장=\(storage.hasStoredBleAuthProtocol) protocol=\(storage.bleAuthProtocol), password=\(storage.blePassword != nil ? "있음" : "없음"), mac=\(storage.bleMacAddress ?? "없음"))")
        stage = .done
    }

    private func pollUntilApproved(service: BydWatchKeyService, uuid: String) async throws {
        for attempt in 0..<150 {  // 2초 간격 * 150회 = 최대 5분 대기
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let status = try await service.getQrCodeStatus(uuid: uuid)
            if status == "2" { return }
            if status == "3" || status == "4" {
                throw BydWatchError.serverError("QR이 만료되었거나 거부되었습니다 (codeStatus=\(status))", status)
            }
            if attempt % 10 == 0 {
                LogManager.shared.log("Watch", "QR 승인 대기 중... (\(attempt * 2)초 경과, codeStatus=\(status))")
            }
        }
        throw BydWatchError.timeout
    }

    private static func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
