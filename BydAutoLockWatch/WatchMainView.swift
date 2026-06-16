import SwiftUI

struct WatchMainView: View {

    @StateObject private var conn = WatchConnectivityManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                statusHeader
                Divider()
                lockControlRow
                serviceToggleButton
                if !conn.isReachable {
                    Label("iPhone 연결 안 됨", systemImage: "iphone.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("BYD AutoLock")
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 12) {
            // 서비스 ON/OFF
            VStack(spacing: 2) {
                Circle()
                    .fill(conn.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(conn.isRunning ? "ON" : "OFF")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 잠금 상태
            VStack(spacing: 2) {
                Image(systemName: lockIcon)
                    .font(.title3)
                    .foregroundStyle(lockColor)
                Text(lockLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 배터리
            if let bat = conn.battery {
                VStack(spacing: 2) {
                    Image(systemName: "battery.100")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("\(bat)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Controls

    private var lockControlRow: some View {
        HStack(spacing: 6) {
            controlButton(title: "해제", icon: "lock.open.fill", color: .green) {
                conn.sendCommand("unlock")
            }
            controlButton(title: "잠금", icon: "lock.fill", color: .orange) {
                conn.sendCommand("lock")
            }
        }
    }

    private var serviceToggleButton: some View {
        Button {
            conn.sendCommand(conn.isRunning ? "stop" : "start")
        } label: {
            Label(conn.isRunning ? "서비스 중지" : "서비스 시작",
                  systemImage: conn.isRunning ? "stop.circle" : "play.circle")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(conn.isRunning ? .red : .green)
        .disabled(!conn.isReachable)
    }

    private func controlButton(title: String, icon: String, color: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(!conn.isReachable)
    }

    // MARK: - Helpers

    private var lockIcon: String {
        guard let locked = conn.isLocked else { return "questionmark.circle" }
        return locked ? "lock.fill" : "lock.open.fill"
    }

    private var lockColor: Color {
        guard let locked = conn.isLocked else { return .secondary }
        return locked ? .orange : .green
    }

    private var lockLabel: String {
        guard let locked = conn.isLocked else { return "알 수 없음" }
        return locked ? "잠김" : "열림"
    }
}
