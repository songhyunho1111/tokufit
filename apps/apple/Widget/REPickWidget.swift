import ImageIO
import REPickShared
import SwiftUI
import UIKit
import WidgetKit

struct UsagiWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload?
    let message: String?
}

struct UsagiWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsagiWidgetEntry {
        UsagiWidgetEntry(date: .now, payload: nil, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsagiWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsagiWidgetEntry>) -> Void) {
        let entry = readEntry()
        let nextCheck = entry.date.addingTimeInterval(30 * 60)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: entry.date))
        let freshness = entry.payload?.snapshot.updatedAt.addingTimeInterval(15 * 60 + 1)
        let boundaries = Set([midnight, freshness].compactMap { $0 })
            .filter { $0 > entry.date && $0 <= nextCheck }.sorted()
        let entries = [entry] + boundaries.map { UsagiWidgetEntry(date: $0, payload: entry.payload, message: entry.message) }
        completion(Timeline(entries: entries, policy: .after(nextCheck)))
    }

    private func readEntry() -> UsagiWidgetEntry {
        let now = Date()
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.appGroup) else {
            return UsagiWidgetEntry(date: now, payload: nil, message: String(localized: "위젯 연결 설정을 확인해 주세요"))
        }
        do {
            let file = directory.appending(path: WidgetStorage.filename)
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= WidgetStorage.maximumPayloadBytes else { throw WidgetPayloadError.invalidImage }
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(WidgetPayload.self, from: data)
            try payload.validate()
            if let png = payload.characterPNG {
                guard let image = CGImageSourceCreateWithData(png as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...1_024).contains(width), (1...1_024).contains(height) else { throw WidgetPayloadError.invalidImage }
            }
            return UsagiWidgetEntry(date: now, payload: payload, message: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return UsagiWidgetEntry(date: now, payload: nil, message: nil)
        } catch {
            return UsagiWidgetEntry(date: now, payload: nil, message: String(localized: "기록을 읽지 못했어요. 앱을 열어 주세요"))
        }
    }
}

struct UsagiWidgetView: View {
    let entry: UsagiWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.payload?.snapshot.name ?? String(localized: "나의 캐릭터"))
                    .font(AppFont.font(.headline)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                if let snapshot = entry.payload?.snapshot, snapshot.hasProfile {
                    Text("\(snapshot.points)P").font(AppFont.font(.subheadline, weight: .semibold))
                }
            }
            if let payload = entry.payload, payload.snapshot.hasProfile {
                character(payload)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(payload.snapshot.steps.formatted())보")
                        .font(AppFont.font(.title2, weight: .semibold))
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("목표 \(payload.snapshot.goalSteps.formatted())보")
                        .font(AppFont.font(.caption))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, Double(payload.snapshot.steps) / Double(payload.snapshot.goalSteps)))
                    .tint(Color(red: 0.30, green: 0.43, blue: 0.29))
                HStack {
                    Label("\(payload.snapshot.waterML) mL", systemImage: "drop")
                    Spacer()
                    if payload.snapshot.isStale(at: entry.date) {
                        Text("마지막 기록")
                    } else {
                        Text("오늘")
                    }
                }
                .font(AppFont.font(.caption))
                .foregroundStyle(.secondary)
                Text("업데이트 \(payload.snapshot.updatedAt.formatted(.dateTime.month().day().hour().minute()))")
                    .font(AppFont.font(.caption2)).foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "pawprint").font(.system(size: 40)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Text(entry.message ?? String(localized: "앱에서 우사기를 만들어 주세요"))
                    .font(AppFont.font(.subheadline)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .font(AppFont.font(.body))
        .widgetURL(URL(string: "repick://care"))
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    @ViewBuilder
    private func character(_ payload: WidgetPayload) -> some View {
        if let data = payload.characterPNG, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(payload.snapshot.name))
        } else {
            Text("우사기 이미지를 불러올 수 없어요")
                .font(AppFont.font(.caption)).foregroundStyle(.secondary)
        }
    }
}

@main
struct REPickWidgets: WidgetBundle {
    init() { AppFont.register() }
    var body: some Widget { REPickUsagiWidget() }
}

struct REPickUsagiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStorage.kind, provider: UsagiWidgetProvider()) { entry in
            UsagiWidgetView(entry: entry)
        }
        .configurationDisplayName("나의 캐릭터")
        .description("내 캐릭터와 오늘의 기록")
        .supportedFamilies([.systemLarge])
    }
}
