import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// BLE 직접 제어에 필요한 dkey를 확보하는 화면 — QR 생성 → 공식 BYD 앱으로 승인 → 토큰/차량정보/BLE키 순차 조회.
struct WatchProvisioningView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WatchProvisioningViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("QR을 **다른 기기**의 공식 BYD 앱 카메라로 스캔해 승인해 주세요. 같은 폰에서는 이 화면과 BYD 앱을 동시에 열 수 없어요 — 다른 폰/태블릿으로 스캔하거나, 이 화면을 스크린샷으로 찍어 다른 기기에서 스캔하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

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
            ProgressView("QR 생성 중...")

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
        runTask = Task { await run() }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    private func makeService() -> BydWatchKeyService {
        let watchImei = CryptoUtils.md5Hex(storage.watchImeiSeed)
        return BydWatchKeyService(config: BydConfig.fromRegion(storage.region), watchImei: watchImei)
    }

    private func run() async {
        LogManager.shared.log("Watch", "BLE 직접 제어 등록 시작")
        let service = makeService()
        await service.syncServerTime()

        do {
            let (uuid, watchImei) = try await service.createQrCode()
            storage.watchQrUuid = uuid

            let qrContent = try await service.buildQrCodeContent(uuid: uuid, watchImei: watchImei)
            guard let qrImage = Self.qrImage(from: qrContent) else {
                LogManager.shared.log("Watch", "등록 실패 - QR 이미지 생성 실패")
                stage = .failed("QR 이미지 생성 실패")
                return
            }
            stage = .waitingApproval(qrImage: qrImage, uuid: uuid)

            try await pollUntilApproved(service: service, uuid: uuid)
            try Task.checkCancellation()
            LogManager.shared.log("Watch", "QR 승인 확인됨 - 토큰 교환 시작")

            stage = .exchangingToken
            let token = try await service.getToken(uuid: uuid)
            storage.watchEncryToken = token.encryToken
            storage.watchSignToken  = token.signToken
            storage.watchControlPwd = token.controlPwd
            storage.watchIdentifier = token.identifier
            storage.watchUserType   = token.userType
            storage.watchVin        = token.vin

            stage = .fetchingVehicle
            let vehicle = try await service.getVehicleConfig(token)
            if let data = try? JSONSerialization.data(withJSONObject: vehicle),
               let text = String(data: data, encoding: .utf8) {
                storage.watchVehicleInfoJson = text
            }
            // 일부 지역은 gain/vehicle에서만 dkey가 오므로, gain/bluetooth가 비어 있어도 덮어쓰지 않는다.
            let extracted = BydWatchKeyService.extractBleInfo(fromVehicleConfig: vehicle)
            if let d = extracted.dkey, !d.isEmpty { storage.bleDkey = d }
            if let m = extracted.mac, !m.isEmpty { storage.bleMacAddress = m }
            if let k = extracted.keyNumber { storage.bleKeyNumber = k }

            stage = .fetchingBluetoothKey
            let bleKey = try await service.getWatchBlueInfo(token)
            if let d = bleKey.dk, !d.isEmpty { storage.bleDkey = d }
            if let m = bleKey.bluetoothMacAddress, !m.isEmpty { storage.bleMacAddress = m }
            if let k = bleKey.keyNumber { storage.bleKeyNumber = k }
            if let p = bleKey.authBluetoothProtocol { storage.bleAuthProtocol = p }
            if let pw = bleKey.bluetoothPassword, !pw.isEmpty { storage.blePassword = pw }

            guard storage.hasBleDkey else {
                LogManager.shared.log("Watch", "등록 실패 - 차량정보/블루투스키 응답에 dkey 없음")
                stage = .failed("차량정보/블루투스키 응답에 dkey가 없습니다")
                return
            }
            LogManager.shared.log("Watch", "BLE 직접 제어 등록 완료 (dkey 확보됨)")
            stage = .done
        } catch is CancellationError {
            LogManager.shared.log("Watch", "등록 취소됨 (화면 닫힘)")
        } catch {
            LogManager.shared.log("Watch", "등록 실패: \(error.localizedDescription)")
            stage = .failed(error.localizedDescription)
        }
    }

    private func pollUntilApproved(service: BydWatchKeyService, uuid: String) async throws {
        for attempt in 0..<150 {  // 2초 간격 * 150회 = 최대 5분 대기
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let status = try await service.getQrCodeStatus(uuid: uuid)
            if status == "2" { return }
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
