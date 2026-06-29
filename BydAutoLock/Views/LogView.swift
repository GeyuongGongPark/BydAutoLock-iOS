import SwiftUI
import UIKit

struct LogView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LogEntry]
    @State private var selectedTag: String? = nil
    @State private var showClearAlert = false

    private let tags = ["", "BLE", "API", "Geofence", "AutoLockService", "GPS", "Session", "Watchdog", "Motion", "BG"]
    private let logManager = LogManager.shared

    init() {
        _entries = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            tagFilterBar

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        logRow(entry)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(tagColor(entry.tag).opacity(0.04))
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .refreshable { reload() }
            .overlay {
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("로그 없음").font(.headline)
                        Text("서비스가 실행 중일 때 로그가 기록됩니다.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .navigationTitle("로그")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shareLog() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    let text = entries.map { "[\($0.formattedTime)] [\($0.tag)] \($0.message)" }.joined(separator: "\n")
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                Button(role: .destructive) { showClearAlert = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("로그 삭제", isPresented: $showClearAlert) {
            Button("삭제", role: .destructive) {
                logManager.clearAll()
                entries.removeAll()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 로그를 삭제하시겠습니까?")
        }
        .onAppear { reload() }
        .preferredColorScheme(.dark)
    }

    private func shareLog() {
        let all = logManager.fetchLogs(limit: 5000)
        let text = all.reversed()
            .map { "[\($0.formattedTime)] [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = df.string(from: Date())

        let storage = StorageManager.shared
        let rawName = storage.deviceName ?? storage.selectedVin ?? "unknown"
        let safeName = rawName
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
            .joined(separator: "_")
        let modelPart = storage.vehicleModel.isEmpty ? "" : "_\(storage.vehicleModel.replacingOccurrences(of: " ", with: "_"))"

        let fileName = "byd_log_\(dateStr)\(modelPart)_\(safeName).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard (try? text.write(to: tempURL, atomically: true, encoding: .utf8)) != nil else { return }

        let vc = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(vc, animated: true)
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        selectedTag = tag.isEmpty ? nil : tag
                        reload()
                    } label: {
                        Text(tag.isEmpty ? "전체" : tag)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected(tag) ? tagColor(tag) : .secondary.opacity(0.2))
                            .foregroundStyle(isSelected(tag) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.tag)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tagColor(entry.tag).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(tagColor(entry.tag))
                Spacer()
                Text(entry.formattedTime)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "BLE":             return .blue
        case "API":             return .purple
        case "Geofence":        return .green
        case "AutoLockService": return .orange
        case "GPS":             return .teal
        case "Session":         return .yellow
        case "Watchdog":        return .pink
        case "Motion":          return .mint
        case "BG":              return .indigo
        default:                return .gray
        }
    }

    private func isSelected(_ tag: String) -> Bool {
        if tag.isEmpty { return selectedTag == nil }
        return selectedTag == tag
    }

    private func reload() {
        entries = logManager.fetchLogs(limit: 500, tag: selectedTag)
    }
}
