import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {

    private let storage = StorageManager.shared

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var notifyLockUnlock: Bool = false
    @State private var notifySignalLost: Bool = false
    @State private var notifyAc: Bool = false
    @State private var notifyService: Bool = false
    @State private var notifyLowBattery: Bool = false
    @State private var lowBatteryThreshold: Double = 20

    var body: some View {
        Form {
            // 권한 상태 섹션
            Section {
                HStack {
                    Label("알림 권한", systemImage: "bell.badge")
                    Spacer()
                    authStatusBadge
                }
                if authStatus != .authorized {
                    Button("시스템 설정에서 권한 허용") {
                        openSettings()
                    }
                    .foregroundStyle(.blue)
                }
            } header: {
                Text("권한")
            }

            // 알림 종류
            Section {
                Toggle(isOn: $notifyLockUnlock) {
                    Label("잠금 / 해제", systemImage: "lock.fill")
                }
                .onChange(of: notifyLockUnlock) { storage.notifyLockUnlock = $0 }

                Toggle(isOn: $notifySignalLost) {
                    Label("신호 끊김 / 복구", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
                .onChange(of: notifySignalLost) { storage.notifySignalLost = $0 }

                Toggle(isOn: $notifyAc) {
                    Label("에어컨 켜기 / 끄기", systemImage: "snowflake")
                }
                .onChange(of: notifyAc) { storage.notifyAc = $0 }

                Toggle(isOn: $notifyService) {
                    Label("서비스 시작 / 중지", systemImage: "shield.lefthalf.filled")
                }
                .onChange(of: notifyService) { storage.notifyService = $0 }

                Toggle(isOn: $notifyLowBattery) {
                    Label("차량 배터리 부족", systemImage: "battery.25percent")
                }
                .onChange(of: notifyLowBattery) { storage.notifyLowBattery = $0 }
            } header: {
                Text("알림 종류")
            }

            // 배터리 임계값
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("알림 기준")
                        Spacer()
                        Text("\(Int(lowBatteryThreshold))% 이하")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $lowBatteryThreshold, in: 5...50, step: 5)
                        .tint(.orange)
                        .onChange(of: lowBatteryThreshold) { storage.lowBatteryThreshold = Int($0) }
                }
            } header: {
                Text("배터리 부족 기준")
            } footer: {
                Text("차량 배터리가 설정값 이하로 떨어지면 알림을 보냅니다.")
            }
        }
        .navigationTitle("알림 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadValues() }
    }

    // MARK: - Private

    private var authStatusBadge: some View {
        Group {
            switch authStatus {
            case .authorized:
                Text("허용됨").foregroundStyle(.green).font(.subheadline)
            case .denied:
                Text("거부됨").foregroundStyle(.red).font(.subheadline)
            case .provisional:
                Text("임시 허용").foregroundStyle(.orange).font(.subheadline)
            default:
                Text("미설정").foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }

    private func loadValues() {
        notifyLockUnlock      = storage.notifyLockUnlock
        notifySignalLost      = storage.notifySignalLost
        notifyAc              = storage.notifyAc
        notifyService         = storage.notifyService
        notifyLowBattery      = storage.notifyLowBattery
        lowBatteryThreshold   = Double(storage.lowBatteryThreshold)

        NotificationManager.shared.authorizationStatus { status in
            authStatus = status
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
