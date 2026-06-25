import WidgetKit
import SwiftUI

// MARK: - Entry

struct WatchComplicationEntry: TimelineEntry {
    let date:      Date
    let isRunning: Bool
    let isLocked:  Bool?
    let battery:   Int?
}

// MARK: - Provider

struct WatchComplicationProvider: TimelineProvider {

    private let defaults = UserDefaults(suiteName: "group.com.ggp.bydautolock")!

    func placeholder(in context: Context) -> WatchComplicationEntry {
        .init(date: Date(), isRunning: true, isLocked: true, battery: 85)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> WatchComplicationEntry {
        .init(
            date:      Date(),
            isRunning: defaults.bool(forKey: "watch_isRunning"),
            isLocked:  defaults.object(forKey: "watch_isLocked") as? Bool,
            battery:   defaults.object(forKey: "watch_battery")  as? Int
        )
    }
}

// MARK: - Views

struct WatchComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:     circularView
        case .accessoryRectangular:  rectangularView
        case .accessoryCorner:       cornerView
        default:                     circularView
        }
    }

    // 원형: 잠금 상태 아이콘 (탭 → 앱 열기)
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: lockIcon)
                    .font(.title3)
                    .foregroundStyle(lockColor)
                if let bat = entry.battery {
                    Text("\(bat)%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "bydautolock://main"))
        .containerBackground(.clear, for: .widget)
    }

    // 직사각형: 상태 + 잠금/해제 버튼
    private var rectangularView: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isRunning ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(entry.isRunning ? "ON" : "OFF")
                        .font(.caption2)
                }
                Label(lockLabel, systemImage: lockIcon)
                    .font(.caption2.bold())
                    .foregroundStyle(lockColor)
                if let bat = entry.battery {
                    Label("\(bat)%", systemImage: "battery.100")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Link(destination: URL(string: "bydautolock://unlock")!) {
                    Image(systemName: "lock.open.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Link(destination: URL(string: "bydautolock://lock")!) {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(width: 44)
        }
        .containerBackground(.clear, for: .widget)
    }

    // 코너: 서비스 상태 점
    private var cornerView: some View {
        Image(systemName: lockIcon)
            .foregroundStyle(lockColor)
            .widgetLabel(entry.isRunning ? "ON" : "OFF")
            .containerBackground(.clear, for: .widget)
    }

    private var lockIcon: String {
        guard let locked = entry.isLocked else { return "car.fill" }
        return locked ? "lock.fill" : "lock.open.fill"
    }

    private var lockColor: Color {
        guard let locked = entry.isLocked else { return .secondary }
        return locked ? .orange : .green
    }

    private var lockLabel: String {
        guard let locked = entry.isLocked else { return "상태 없음" }
        return locked ? "잠김" : "열림"
    }
}

// MARK: - Widget Configuration

struct BydComplication: Widget {
    let kind = "BydComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("BYD AutoLock")
        .description("차량 잠금 상태 및 서비스 상태")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner
        ])
    }
}

// MARK: - Bundle Entry Point

@main
struct BydWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        BydComplication()
    }
}
