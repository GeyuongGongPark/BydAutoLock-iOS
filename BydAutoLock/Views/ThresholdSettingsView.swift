import SwiftUI

struct ThresholdSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    private let storage = StorageManager.shared

    @State private var unlockRssi: Double
    @State private var lockRssi: Double
    @State private var rssiAlpha: Double
    @State private var bleScanMode: Int
    @State private var isGeofencingEnabled: Bool
    @State private var geofenceRadius: Double
    @State private var autoUnlock: Bool
    @State private var autoLock: Bool
    @State private var autoAcOnUnlock: Bool
    @State private var autoAcOffOnLock: Bool
    @State private var acTargetTemp: Double
    @State private var showRssiError = false

    init() {
        let s = StorageManager.shared
        _unlockRssi        = State(initialValue: Double(s.unlockRssi))
        _lockRssi          = State(initialValue: Double(s.lockRssi))
        _rssiAlpha         = State(initialValue: Double(s.rssiAlpha))
        _bleScanMode       = State(initialValue: s.bleScanMode)
        _isGeofencingEnabled = State(initialValue: s.isGeofencingEnabled)
        _geofenceRadius      = State(initialValue: Double(s.geofenceRadius))
        _autoUnlock        = State(initialValue: s.isAutoUnlockOnApproach)
        _autoLock          = State(initialValue: s.isAutoLockOnDeparture)
        _autoAcOnUnlock    = State(initialValue: s.isAutoAcOnUnlock)
        _autoAcOffOnLock   = State(initialValue: s.isAutoAcOffOnLock)
        _acTargetTemp      = State(initialValue: Double(s.acTargetTemp))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("잠금 해제 임계값")
                        Spacer()
                        Text("\(Int(unlockRssi)) dBm").foregroundStyle(.green).fontWeight(.medium)
                    }
                    Slider(value: $unlockRssi, in: -100 ... -40, step: 1)
                        .tint(.green)
                    Text("이 값 이상의 RSSI에서 잠금 해제 트리거").font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("잠금 임계값")
                        Spacer()
                        Text("\(Int(lockRssi)) dBm").foregroundStyle(.orange).fontWeight(.medium)
                    }
                    Slider(value: $lockRssi, in: -100 ... -40, step: 1)
                        .tint(.orange)
                    Text("이 값 이하의 RSSI에서 잠금 트리거").font(.caption2).foregroundStyle(.secondary)
                }

                rssiDiagram
            } header: { Text("RSSI 임계값") }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("EMA 평활화 계수 (α)")
                        Spacer()
                        Text(String(format: "%.2f", rssiAlpha)).fontWeight(.medium)
                    }
                    Slider(value: $rssiAlpha, in: 0.05...0.8, step: 0.05)
                    Text("낮을수록 더 부드럽게 (반응 느림). 높을수록 즉각 반응.").font(.caption2).foregroundStyle(.secondary)
                }

                Picker("BLE 스캔 모드", selection: $bleScanMode) {
                    Text("균형 (Balanced)").tag(0)
                    Text("저지연 (Low Latency)").tag(1)
                    Text("저전력 (Low Power)").tag(2)
                }
                .pickerStyle(.menu)
            } header: { Text("신호 필터링") }

            Section {
                Toggle("자동 잠금 해제 (접근 시)", isOn: $autoUnlock)
                Toggle("자동 잠금 (이탈 시)", isOn: $autoLock)
            } header: { Text("자동 제어") }

            Section {
                Toggle("지오펜싱 활성화", isOn: $isGeofencingEnabled)
                if isGeofencingEnabled {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("지오펜스 반경")
                            Spacer()
                            Text("\(Int(geofenceRadius))m").fontWeight(.medium)
                        }
                        Slider(value: $geofenceRadius, in: 50...500, step: 10)
                        Text("차량에서 이 거리 이상 이탈 시 BLE 스캔 자동 중단").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("지오펜싱") }

            Section {
                Toggle("잠금 해제 시 에어컨 자동 시작", isOn: $autoAcOnUnlock)
                Toggle("잠금 시 에어컨 자동 종료", isOn: $autoAcOffOnLock)

                if autoAcOnUnlock {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("에어컨 목표 온도")
                            Spacer()
                            Text(String(format: "%.1f°C", acTargetTemp)).fontWeight(.medium)
                        }
                        Slider(value: $acTargetTemp, in: 15...31, step: 0.5)
                    }
                }
            } header: { Text("에어컨 자동 제어") }

        }
        .navigationTitle("임계값 / 설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("저장") {
                    guard Int(unlockRssi) > Int(lockRssi) else { showRssiError = true; return }  // 같거나 역전 시 차단
                    save(); dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .alert("설정 오류", isPresented: $showRssiError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠금 해제 임계값(\(Int(unlockRssi)) dBm)이 잠금 임계값(\(Int(lockRssi)) dBm)보다 높아야 합니다.")
        }
        .onAppear { loadFromStorage() }
    }

    private var rssiDiagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
            HStack(spacing: 0) {
                Rectangle().fill(.red.opacity(0.3))
                    .overlay(Text("잠금\n구역").font(.caption2).multilineTextAlignment(.center))
                Rectangle().fill(.yellow.opacity(0.3))
                    .overlay(Text("중립\n구역").font(.caption2).multilineTextAlignment(.center))
                Rectangle().fill(.green.opacity(0.3))
                    .overlay(Text("해제\n구역").font(.caption2).multilineTextAlignment(.center))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 50)
    }

    private func loadFromStorage() {
        let s = storage
        unlockRssi        = Double(s.unlockRssi)
        lockRssi          = Double(s.lockRssi)
        rssiAlpha         = Double(s.rssiAlpha)
        bleScanMode       = s.bleScanMode
        isGeofencingEnabled = s.isGeofencingEnabled
        geofenceRadius    = Double(s.geofenceRadius)
        autoUnlock        = s.isAutoUnlockOnApproach
        autoLock          = s.isAutoLockOnDeparture
        autoAcOnUnlock    = s.isAutoAcOnUnlock
        autoAcOffOnLock   = s.isAutoAcOffOnLock
        acTargetTemp      = Double(s.acTargetTemp)
    }

    private func save() {
        storage.unlockRssi         = Int(unlockRssi)
        storage.lockRssi           = Int(lockRssi)
        storage.rssiAlpha          = Float(rssiAlpha)
        storage.bleScanMode        = bleScanMode
        storage.isGeofencingEnabled = isGeofencingEnabled
        storage.geofenceRadius      = Int(geofenceRadius)
        storage.isAutoUnlockOnApproach = autoUnlock
        storage.isAutoLockOnDeparture  = autoLock
        storage.isAutoAcOnUnlock    = autoAcOnUnlock
        storage.isAutoAcOffOnLock   = autoAcOffOnLock
        storage.acTargetTemp        = Float(acTargetTemp)
    }
}
