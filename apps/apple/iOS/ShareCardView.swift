import CoreText
import REPickShared
import SwiftUI
import UIKit

struct ShareCardView: View {
    let snapshot: UsagiState
    @Environment(\.dismiss) private var dismiss
    @State private var export: ShareCardExport?
    @State private var isRendering = false
    @State private var errorMessage: String?
    @State private var isOpeningInstagram = false
    @State private var instagramError: String?
    private let instagram = InstagramStoryShare()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.sectionSpacing) {
                    if let export {
                        let summary = ShareCardSummary(snapshot: snapshot)
                        Image(uiImage: export.image)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Design.controlRadius))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(snapshot.preferences.name), \(summary.date). 키 \(summary.height), 몸무게 \(summary.weight). 식사 \(summary.foodStatus), 운동 \(summary.exerciseStatus), 수면 \(summary.sleepStatus).")
                            .accessibilityIdentifier("share.preview")
                        Text("키·몸무게가 포함돼요.")
                            .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("이미지를 만들지 못했어요", systemImage: "photo.badge.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("다시 시도") { Task { await prepare() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRendering)
                                .accessibilityIdentifier("share.retry")
                        }
                    } else {
                        ProgressView("공유 이미지 만드는 중")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    }
                }
                .padding(Design.pagePadding)
                .frame(maxWidth: Design.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Color.repickCream)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let export { shareActions(export) }
            }
            .navigationTitle("기록 공유")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task { await prepare() }
            .alert("스토리를 열지 못했어요", isPresented: Binding(
                get: { instagramError != nil }, set: { if !$0 { instagramError = nil } }
            )) {
                Button("확인", role: .cancel) { instagramError = nil }
            } message: {
                Text(instagramError ?? "")
            }
        }
    }

    private func shareActions(_ export: ShareCardExport) -> some View {
        VStack(spacing: 4) {
            ShareLink(item: export.url, preview: SharePreview("RE:PICK 기록", image: Image(uiImage: export.image))) {
                Label("이미지 공유", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("share.export")
            if instagram.availability != .setupRequired {
            Button {
                Task { await shareToInstagram(export) }
            } label: {
                Label(isOpeningInstagram ? "Instagram 여는 중" : "Instagram 스토리", systemImage: "camera")
                    .font(AppFont.font(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(instagram.availability == .ready ? Color.repickGreen : Color.repickSecondaryText)
            .disabled(instagram.availability != .ready || isOpeningInstagram)
            .accessibilityIdentifier("share.instagram")
            }
            if instagram.availability == .setupRequired {
                Text("스토리 공유 준비 중")
                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    .accessibilityIdentifier("share.instagramUnavailable")
            } else if instagram.availability == .appUnavailable {
                Text("Instagram 설치 후 사용할 수 있어요.")
                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
            }
        }
        .padding(.horizontal, Design.pagePadding)
        .padding(.vertical, 12)
        .frame(maxWidth: Design.contentWidth)
        .frame(maxWidth: .infinity)
        .background(Color.repickCream)
    }

    @MainActor
    private func prepare() async {
        guard export == nil, !isRendering else { return }
        isRendering = true
        errorMessage = nil
        defer { isRendering = false }
        await Task.yield()
        guard !Task.isCancelled else { return }
        do {
            let generated = try ShareCardExport.make(snapshot: snapshot)
            guard !Task.isCancelled else { return }
            export = generated
        } catch {
            errorMessage = String(localized: "잠시 후 다시 시도해 주세요. 기록은 변경되지 않습니다.")
        }
    }

    @MainActor
    private func shareToInstagram(_ export: ShareCardExport) async {
        guard !isOpeningInstagram else { return }
        isOpeningInstagram = true
        defer { isOpeningInstagram = false }
        do {
            guard let data = export.image.pngData() else { throw InstagramStoryShare.Failure.invalidImage }
            try await instagram.share(pngData: data)
        } catch is CancellationError {
            return
        } catch InstagramStoryShare.Failure.setupRequired {
            instagramError = String(localized: "스토리 공유 준비 중입니다. 이미지 공유를 이용해 주세요.")
        } catch InstagramStoryShare.Failure.appUnavailable {
            instagramError = String(localized: "Instagram을 설치한 뒤 다시 시도해 주세요.")
        } catch {
            instagramError = String(localized: "다시 시도하거나 이미지 공유를 이용해 주세요.")
        }
    }
}

@MainActor
struct ShareCardExport {
    let image: UIImage
    let url: URL

    static func make(snapshot: UsagiState) throws -> ShareCardExport {
        try snapshot.validate()
        guard snapshot.profile != nil, ShareCardFont.register(),
              let character = UsagiSnapshotRenderer.render(state: snapshot, size: CGSize(width: 640, height: 900)) else {
            throw ShareCardError.renderingFailed
        }
        let renderer = ImageRenderer(content: ActivityCard(snapshot: snapshot, character: character)
            .frame(width: 900, height: 550)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .dynamicTypeSize(.large))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else { throw ShareCardError.renderingFailed }
        let directory = URL.temporaryDirectory.appending(path: "REPickShare", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "repick-\(snapshot.daily.day).png")
        // Share targets can read the file after this preview closes; the OS manages its temporary lifetime.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return ShareCardExport(image: image, url: url)
    }
}

private enum ShareCardError: Error {
    case renderingFailed
}

private struct ActivityCard: View {
    let snapshot: UsagiState
    let character: UIImage

    private let background = Color(red: 212 / 255, green: 206 / 255, blue: 144 / 255)
    private let ink = Color(red: 53 / 255, green: 36 / 255, blue: 20 / 255)
    private let outline = Color(red: 88 / 255, green: 84 / 255, blue: 38 / 255)
    private let panel = Color(red: 226 / 255, green: 221 / 255, blue: 173 / 255)
    private var summary: ShareCardSummary { ShareCardSummary(snapshot: snapshot) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 44).fill(background)
            RoundedRectangle(cornerRadius: 42)
                .strokeBorder(outline, lineWidth: 2)
                .padding(.horizontal, 44).padding(.vertical, 36)
            HStack(alignment: .top, spacing: 24) {
                portrait
                    .frame(width: 292, height: 406)
                VStack(alignment: .leading, spacing: 0) {
                    title.frame(height: 64)
                    Spacer().frame(height: 20)
                    basicInformation.frame(height: 104)
                    Spacer().frame(height: 28)
                    HStack(spacing: 14) {
                        statusPanel.frame(width: 145)
                        Text(summary.message)
                            .font(ShareCardFont.fixed(size: 19))
                            .lineSpacing(3)
                            .lineLimit(6).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(20)
                            .background(panel, in: RoundedRectangle(cornerRadius: 30))
                    }
                    .frame(height: 154)
                    Spacer().frame(height: 18)
                    Text(summary.date)
                        .font(ShareCardFont.fixed(size: 27)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 32)
                }
                .frame(width: 460)
            }
            .padding(.leading, 62).padding(.top, 68)
        }
        .foregroundStyle(ink)
        .background(Color.white)
    }

    private var portrait: some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.98, blue: 0.89),
                                         Color(red: 0.80, green: 0.76, blue: 0.64)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(uiImage: character).resizable().scaledToFit()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(outline.opacity(0.55), lineWidth: 1.5) }
            .shadow(color: ink.opacity(0.24), radius: 4, x: 0, y: 6)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(snapshot.preferences.name)
                .font(ShareCardFont.fixed(size: 52))
                .lineLimit(2).minimumScaleFactor(0.35)
                .shadow(color: outline.opacity(0.22), radius: 0, x: 2, y: 2)
                .frame(maxWidth: 250, alignment: .leading)
            Text(summary.costumeName)
                .font(ShareCardFont.fixed(size: 23))
                .lineLimit(2).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var basicInformation: some View {
        VStack(spacing: 6) {
            Text("기본 정보").font(ShareCardFont.fixed(size: 24))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("키 : \(summary.height)")
                Spacer(minLength: 8)
                Text("몸무게 : \(summary.weight)")
            }
            .font(ShareCardFont.fixed(size: 23))
            .lineLimit(1).minimumScaleFactor(0.7)
            if let change = summary.weightChange {
                Text("체중 변화 \(change)")
                    .font(ShareCardFont.fixed(size: 12))
                    .foregroundStyle(ink.opacity(0.8))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panel, in: RoundedRectangle(cornerRadius: 30))
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("식사 \(summary.foodStatus)")
            Text("운동 \(summary.exerciseStatus)")
            Text("수면 \(summary.sleepStatus)")
        }
        .font(ShareCardFont.fixed(size: 23))
        .lineLimit(1).minimumScaleFactor(0.6)
        .padding(.horizontal, 17).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 30))
    }
}

private enum ShareCardFont {
    private static let postScriptName = "Griun_Yeeun-Rg"
    private static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: postScriptName, withExtension: "ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: postScriptName, size: 17)?.fontName == postScriptName
    }()

    static func register() -> Bool { registered }

    static func fixed(size: CGFloat) -> Font {
        _ = register()
        return .custom(postScriptName, fixedSize: size)
    }
}
