import SwiftUI

struct AcSettingsView: View {

    private let storage = StorageManager.shared

    @State private var autoAcOnUnlock:  Bool  = false
    @State private var autoAcOffOnLock: Bool  = false
    @State private var targetTemp:      Float = 22.0
    @State private var windLevel:       Int   = 0
    @State private var cycleMode:       Int   = 2

    var body: some View {
        NavigationStack {
            Form {
                // ── 자동 제어
                Section("자동 제어") {
                    Toggle("잠금 해제 시 자동 켜기", isOn: $autoAcOnUnlock)
                        .tint(.green)
                    Toggle("잠금 시 자동 끄기", isOn: $autoAcOffOnLock)
                        .tint(.orange)
                }

                // ── 온도
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("목표 온도")
                            Spacer()
                            Text(String(format: "%.1f°C", targetTemp))
                                .foregroundStyle(.blue)
                                .monospacedDigit()
                        }
                        Slider(value: $targetTemp, in: 16...30, step: 0.5)
                            .tint(.blue)
                        HStack {
                            Text("16°C").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("30°C").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("온도 설정")
                }

                // ── 바람 세기
                Section("바람 세기") {
                    Picker("바람 세기", selection: $windLevel) {
                        Text("자동").tag(0)
                        Text("1단").tag(1)
                        Text("2단").tag(2)
                        Text("3단").tag(3)
                        Text("4단").tag(4)
                    }
                    .pickerStyle(.segmented)
                }

                // ── 순환 모드
                Section("공기 순환") {
                    Picker("순환 모드", selection: $cycleMode) {
                        Text("내기 순환").tag(0)
                        Text("외기 유입").tag(1)
                        Text("자동").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("에어컨 켜기는 최대 20분간 동작합니다.\n바람 세기 '자동'은 차량이 결정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("에어컨 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSettings() }
            .onChange(of: autoAcOnUnlock)  { storage.isAutoAcOnUnlock  = $0 }
            .onChange(of: autoAcOffOnLock) { storage.isAutoAcOffOnLock = $0 }
            .onChange(of: targetTemp)      { storage.acTargetTemp      = $0 }
            .onChange(of: windLevel)       { storage.acWindLevel       = $0 }
            .onChange(of: cycleMode)       { storage.acCycleMode       = $0 }
        }
        .preferredColorScheme(.dark)
    }

    private func loadSettings() {
        autoAcOnUnlock  = storage.isAutoAcOnUnlock
        autoAcOffOnLock = storage.isAutoAcOffOnLock
        targetTemp      = storage.acTargetTemp
        windLevel       = storage.acWindLevel
        cycleMode       = storage.acCycleMode
    }
}
