import SwiftUI
import WidgetKit

// 정적 위젯 1개. 디데이 표시는 Task 12에서 채운다.
struct DateEntry: TimelineEntry {
    let date: Date
}

struct DateProvider: TimelineProvider {
    func placeholder(in context: Context) -> DateEntry { DateEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (DateEntry) -> Void) {
        completion(DateEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DateEntry>) -> Void) {
        completion(Timeline(entries: [DateEntry(date: .now)], policy: .never))
    }
}

struct DateWidgetView: View {
    var entry: DateEntry

    var body: some View {
        Text("달콤")
            .containerBackground(.pink.opacity(0.2), for: .widget)
    }
}

@main
struct DateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DateWidget", provider: DateProvider()) { entry in
            DateWidgetView(entry: entry)
        }
        .configurationDisplayName("달콤")
        .supportedFamilies([.systemSmall])
    }
}
