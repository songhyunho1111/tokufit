import ImageIO
import REPickShared
import SwiftUI
import WidgetKit

struct UsagiComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let image: CGImage?
    let message: String?
}

struct UsagiComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsagiComplicationEntry {
        UsagiComplicationEntry(date: .now, snapshot: nil, image: nil, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsagiComplicationEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsagiComplicationEntry>) -> Void) {
        let entry = readEntry()
        let nextCheck = entry.date.addingTimeInterval(30 * 60)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: entry.date))
        let freshness = entry.snapshot?.updatedAt.addingTimeInterval(15 * 60 + 1)
        let boundaries = Set([midnight, freshness].compactMap { $0 })
            .filter { $0 > entry.date && $0 <= nextCheck }.sorted()
        let entries = [entry] + boundaries.map {
            UsagiComplicationEntry(date: $0, snapshot: entry.snapshot, image: entry.image, message: entry.message)
        }
        completion(Timeline(entries: entries, policy: .after(nextCheck)))
    }

    func readEntry(directory: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: WidgetStorage.appGroup
    )) -> UsagiComplicationEntry {
        let now = Date()
        guard let directory else {
            return UsagiComplicationEntry(date: now, snapshot: nil, image: nil,
                                          message: String(localized: "Watch 앱을 열어 주세요"))
        }
        do {
            let file = directory.appending(path: WidgetStorage.filename)
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= WidgetStorage.maximumPayloadBytes else {
                throw WidgetPayloadError.invalidImage
            }
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(WidgetPayload.self, from: data)
            try payload.validate()
            var image: CGImage?
            if let png = payload.characterPNG {
                guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...1_024).contains(width), (1...1_024).contains(height),
                      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw WidgetPayloadError.invalidImage
                }
                image = decoded
            }
            return UsagiComplicationEntry(date: now, snapshot: payload.snapshot, image: image, message: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return UsagiComplicationEntry(date: now, snapshot: nil, image: nil, message: nil)
        } catch {
            return UsagiComplicationEntry(date: now, snapshot: nil, image: nil,
                                          message: String(localized: "기록을 읽지 못했어요"))
        }
    }
}

struct UsagiComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: UsagiComplicationEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.hasProfile {
                if family == .accessoryCircular {
                    Gauge(value: min(1, Double(snapshot.steps) / Double(snapshot.goalSteps))) {
                        Text(snapshot.name)
                    } currentValueLabel: {
                        character.frame(width: 31, height: 38)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .privacySensitive()
                    .widgetLabel {
                        Text(snapshot.isStale(at: entry.date) ? String(localized: "마지막 기록") : snapshot.name)
                    }
                    .accessibilityLabel(statusLabel(snapshot))
                } else {
                    HStack(spacing: 7) {
                        character.frame(width: 53).privacySensitive()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.isStale(at: entry.date) ? String(localized: "마지막 기록") : snapshot.name)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(snapshot.steps.formatted())보")
                                .font(.headline).minimumScaleFactor(0.65).lineLimit(1)
                            Label("\(snapshot.waterML) mL", systemImage: "drop")
                                .font(.caption2).minimumScaleFactor(0.7).lineLimit(1)
                        }
                        .privacySensitive()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statusLabel(snapshot))
                }
            } else {
                if family == .accessoryCircular {
                    Image(systemName: "pawprint").font(.title2)
                        .accessibilityLabel(entry.message ?? String(localized: "iPhone에서 우사기를 만들어 주세요"))
                } else {
                    HStack {
                        Image(systemName: "pawprint").font(.title2)
                        Text(entry.message ?? String(localized: "iPhone에서 우사기를 만들어 주세요"))
                            .font(.caption2)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var character: some View {
        if let image = entry.image {
            if #available(watchOS 11, *) {
                Image(decorative: image, scale: 1).resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFit()
            } else if renderingMode == .accented {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .luminanceToAlpha()
            } else {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            }
        } else {
            Image(systemName: "pawprint")
                .font(.title2)
                .accessibilityLabel("이미지 동기화 대기")
        }
    }

    private func statusLabel(_ snapshot: WidgetSnapshot) -> String {
        let freshness = snapshot.isStale(at: entry.date)
            ? String(localized: "마지막 기록") : snapshot.name
        return String(localized: "\(freshness), \(snapshot.steps)걸음, 물 \(snapshot.waterML)밀리리터, 목표 \(snapshot.goalSteps)걸음")
    }
}

@main
struct REPickWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStorage.watchKind, provider: UsagiComplicationProvider()) { entry in
            UsagiComplicationView(entry: entry)
        }
        .configurationDisplayName("나의 캐릭터")
        .description("내 캐릭터와 걸음·물 기록")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}
