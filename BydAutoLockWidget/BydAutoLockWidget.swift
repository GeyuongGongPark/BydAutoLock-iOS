import WidgetKit
import SwiftUI

// MARK: - Data

struct BydStatusEntry: TimelineEntry {
    let date:         Date
    let isRunning:    Bool
    let isLocked:     Bool?
    let battery:      Int?
    let drivingRange: Int?
}

// MARK: - Provider

struct BydStatusProvider: TimelineProvider {

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.ggp.bydautolock")
    }

    func placeholder(in context: Context) -> BydStatusEntry {
        .init(date: Date(), isRunning: true, isLocked: true, battery: 85, drivingRange: 320)
    }

    func getSnapshot(in context: Context, completion: @escaping (BydStatusEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BydStatusEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> BydStatusEntry {
        .init(
            date:         Date(),
            isRunning:    sharedDefaults?.bool(forKey: "widget_isRunning") ?? false,
            isLocked:     sharedDefaults?.object(forKey: "widget_isLocked")     as? Bool,
            battery:      sharedDefaults?.object(forKey: "widget_battery")      as? Int,
            drivingRange: sharedDefaults?.object(forKey: "widget_drivingRange") as? Int
        )
    }
}

// MARK: - Views

struct BydWidgetEntryView: View {
    var entry: BydStatusEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:           smallView
        case .systemMedium:          mediumView
        case .accessoryCircular:     circularView
        case .accessoryRectangular:  rectangularView
        default:                     smallView
        }
    }

    // 2×2 홈 화면 위젯
    private var smallView: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill")
                .font(.title2)
                .foregroundStyle(entry.isRunning ? .green : .secondary)

            if let locked = entry.isLocked {
                Label(locked ? "잠김" : "열림",
                      systemImage: locked ? "lock.fill" : "lock.open.fill")
                    .font(.caption.bold())
                    .foregroundStyle(locked ? .orange : .green)
            } else {
                Text("BYD AutoLock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let bat = entry.battery {
                Label("\(bat)%", systemImage: "battery.100")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    // 4×2 홈 화면 위젯
    private var mediumView: some View {
        HStack(spacing: 0) {
            // 서비스 상태
            widgetCell(
                icon: "shield.lefthalf.filled",
                label: entry.isRunning ? "실행 중" : "중지됨",
                color: entry.isRunning ? .green : .secondary
            )

            Divider().padding(.vertical, 8)

            // 잠금 상태
            widgetCell(
                icon: entry.isLocked.map { $0 ? "lock.fill" : "lock.open.fill" } ?? "questionmark",
                label: entry.isLocked.map { $0 ? "잠김" : "열림" } ?? "알 수 없음",
                color: entry.isLocked.map { $0 ? .orange : .green } ?? .secondary
            )

            Divider().padding(.vertical, 8)

            // 배터리
            widgetCell(
                icon: "battery.100",
                label: entry.battery.map { "\($0)%" } ?? "--",
                color: .blue
            )

            // 주행 거리 (있을 때만)
            if let range = entry.drivingRange {
                Divider().padding(.vertical, 8)
                widgetCell(icon: "road.lanes", label: "\(range)km", color: .purple)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    // 잠금화면 원형 위젯
    private var circularView: some View {
        ZStack {
            if let locked = entry.isLocked {
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(.title2)
                    .foregroundStyle(locked ? .orange : .green)
            } else {
                Image(systemName: "car.fill").font(.title2)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    // 잠금화면 직사각형 위젯
    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .foregroundStyle(entry.isRunning ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isLocked.map { $0 ? "잠김" : "열림" } ?? "BYD AutoLock")
                    .font(.caption.bold())
                if let bat = entry.battery {
                    Text("배터리 \(bat)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private func widgetCell(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget Configuration

@main
struct BydAutoLockWidget: Widget {
    let kind = "BydAutoLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BydStatusProvider()) { entry in
            BydWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BYD AutoLock")
        .description("차량 잠금 상태와 서비스 상태를 확인합니다.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
