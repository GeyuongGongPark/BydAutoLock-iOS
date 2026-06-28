import SwiftUI
import WidgetKit

struct MainView: View {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var service = AutoLockService.shared
    @State private var showDrawer = false
    @State private var vehicleStatus: VehicleStatus?
    @State private var vehicleStatusError: String?
    @State private var isRefreshing = false

    private let storage = StorageManager.shared

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        serviceToggleCard
                        statusCard
                        rssiCard
                        vehicleStatusCard
                        quickActionsCard
                        acControlCard
                    }
                    .padding()
                }
                .navigationTitle("BYD AutoLock")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { showDrawer = true }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { WidgetCenter.shared.reloadAllTimelines() }
        }

            // ── 드로어 오버레이
            if showDrawer {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) { showDrawer = false }
                    }
                    .transition(.opacity)

                SettingsDrawerView(isOpen: $showDrawer)
                    .frame(width: min(UIScreen.main.bounds.width * 0.78, 320))
                    .ignoresSafeArea(edges: .vertical)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    // MARK: - Service Toggle Card

    private var serviceToggleCard: some View {
        CardView {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("자동 잠금 서비스", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                    Text(service.isRunning ? "실행 중" : "중지됨")
                        .font(.caption)
                        .foregroundStyle(service.isRunning ? .green : .secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.isRunning },
                    set: { on in
                        if on { service.start() }
                        else  { service.stop()  }
                    }
                ))
                .labelsHidden()
                .tint(.green)
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("서비스 상태", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Divider()
                statusRow("스캔 모드",    value: service.scanModeDescription)
                statusRow("근접 상태",    value: service.proximityState == .near ? "근접 (NEAR)" : "이탈 (FAR)",
                          color: service.proximityState == .near ? .green : .orange)
                if service.isInsideGeofence {
                    statusRow("지오펜스", value: "내부", color: .blue)
                }
                if service.isStationary {
                    statusRow("정지 감지", value: "정지 중 (스캔 일시 중단)", color: .yellow)
                }
                if let t = service.lastApiTime {
                    statusRow("마지막 API", value: service.lastApiResult ?? "없음",
                              subtitle: RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date()))
                }
            }
        }
    }

    // MARK: - RSSI Card

    private var rssiCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("BLE 신호", systemImage: "waveform")
                    .font(.headline)
                Divider()
                if let raw = service.rawRssi, let smooth = service.smoothedRssi {
                    HStack(spacing: 20) {
                        rssiGauge(title: "RAW", value: raw)
                        rssiGauge(title: "EMA", value: Int(smooth))
                    }
                    rssiBar(value: Int(smooth))
                } else {
                    Text("신호 없음")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                HStack {
                    Text("잠금 해제 임계값: \(storage.unlockRssi) dBm")
                        .font(.caption2).foregroundStyle(.green)
                    Spacer()
                    Text("잠금 임계값: \(storage.lockRssi) dBm")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func rssiGauge(title: String, value: Int) -> some View {
        VStack {
            Text(title)
                .font(.caption2).foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(rssiColor(value))
            Text("dBm")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func rssiBar(value: Int) -> some View {
        let clamped = Double(max(-100, min(-40, value)))
        let progress = (clamped + 100) / 60.0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                RoundedRectangle(cornerRadius: 4)
                    .fill(rssiColor(value))
                    .frame(width: geo.size.width * CGFloat(progress))
            }
        }
        .frame(height: 8)
    }

    private func rssiColor(_ value: Int) -> Color {
        if value >= storage.unlockRssi { return .green }
        if value >= storage.lockRssi   { return .yellow }
        return .red
    }

    // MARK: - Vehicle Status Card

    private var vehicleStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("차량 상태", systemImage: "car.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        refreshVehicleStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                       value: isRefreshing)
                    }
                    .disabled(isRefreshing)
                }
                Divider()
                if let status = vehicleStatus {
                    HStack(spacing: 16) {
                        vehicleStatItem(icon: "lock.fill",
                                        label: status.isLocked ? "잠김" : "열림",
                                        color: status.isLocked ? .orange : .green)
                        vehicleStatItem(icon: "battery.100",
                                        label: "\(status.batteryPercentage)%",
                                        color: .blue)
                        vehicleStatItem(icon: "road.lanes",
                                        label: "\(Int(status.drivingRange))km",
                                        color: .purple)
                        if status.isClimateOn {
                            vehicleStatItem(icon: "snowflake", label: "에어컨", color: .cyan)
                        }
                    }
                    if status.interiorTemperature != 0 {
                        statusRow("실내 온도", value: String(format: "%.1f°C", status.interiorTemperature))
                    }
                } else if let err = vehicleStatusError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("새로고침을 눌러 상태를 조회하세요")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 주차 위치
                if service.lastParkingLat != 0 || service.lastParkingLng != 0 {
                    Divider()
                    HStack(spacing: 4) {
                        Image(systemName: "parkingsign.circle.fill")
                            .font(.caption).foregroundStyle(.blue)
                        Text(String(format: "%.5f, %.5f",
                                    service.lastParkingLat,
                                    service.lastParkingLng))
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if let t = service.lastParkingTime {
                            Text(RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Button(action: openInMaps) {
                        Label("Apple 지도에서 보기", systemImage: "map.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.4), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func vehicleStatItem(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions

    private var quickActionsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("수동 제어", systemImage: "hand.tap")
                    .font(.headline)
                Divider()
                HStack(spacing: 12) {
                    actionButton(title: "잠금 해제", icon: "lock.open.fill", color: .green) {
                        service.manualUnlock()
                    }
                    actionButton(title: "잠금", icon: "lock.fill", color: .orange) {
                        service.manualLock()
                    }
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: - AC Control Card

    private var acControlCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("에어컨 / 공조", systemImage: "snowflake")
                    .font(.headline)
                Divider()
                HStack(spacing: 12) {
                    actionButton(title: "에어컨 켜기", icon: "snowflake", color: .cyan) {
                        service.manualStartClimate()
                    }
                    actionButton(title: "에어컨 끄기", icon: "snowflake.slash", color: .gray) {
                        service.manualStopClimate()
                    }
                }
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("목표 온도: \(String(format: "%.1f", storage.acTargetTemp))°C · 자동 켜기: \(storage.isAutoAcOnUnlock ? "ON" : "OFF")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusRow(_ key: String, value: String, color: Color = .primary, subtitle: String? = nil) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).foregroundStyle(color).font(.subheadline)
                if let sub = subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openInMaps() {
        let lat = service.lastParkingLat
        let lng = service.lastParkingLng
        guard let url = URL(string: "maps://?ll=\(lat),\(lng)&q=내+차량") else { return }
        UIApplication.shared.open(url)
    }

    private func refreshVehicleStatus() {
        guard !isRefreshing, let vin = storage.selectedVin else { return }
        isRefreshing = true
        service.refreshParkingLocation()
        Task {
            defer { isRefreshing = false }
            do {
                let status = try await service.fetchVehicleStatus(vin: vin)
                vehicleStatus = status
                vehicleStatusError = nil
                service.updateWidgetStatus(battery: status.batteryPercentage, drivingRange: Int(status.drivingRange))
            } catch {
                vehicleStatus = nil
                vehicleStatusError = error.localizedDescription
            }
        }
    }
}

// MARK: - Card View

struct CardView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

