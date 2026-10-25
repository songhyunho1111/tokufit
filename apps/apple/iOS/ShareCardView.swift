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
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: Design.sectionSpacing) {
                        if let export {
                            Image(uiImage: export.image)
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: Design.controlRadius))
                                .frame(height: max(160, geometry.size.height - 110))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(snapshot.preferences.name), \(snapshot.daily.day) 기록. 체중 변화 \(ShareCardText.weightChange(snapshot.weightChangeKG)). \(snapshot.daily.steps)보, 목표 \(snapshot.daily.goalSteps)보, 물 \(snapshot.daily.waterML)밀리리터")
                                .accessibilityIdentifier("share.preview")
                            Group {
                                if snapshot.weightChangeKG == nil {
                                    Text("키·몸무게·성별·위치는 포함하지 않습니다.")
                                } else {
                                    Text("체중 변화량이 포함됩니다. 키·현재 몸무게·성별·위치는 포함하지 않습니다.")
                                }
                            }.font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
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
            }
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
        guard snapshot.profile != nil,
              let character = UsagiSnapshotRenderer.render(state: snapshot, size: CGSize(width: 512, height: 640)) else {
            throw ShareCardError.renderingFailed
        }
        let renderer = ImageRenderer(content: ActivityCard(snapshot: snapshot, character: character)
            .frame(width: 360, height: 640)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .dynamicTypeSize(.large))
        renderer.scale = 3
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

enum ShareCardText {
    static func weightChange(_ value: Double?) -> String {
        guard let value else { return String(localized: "비교 기록 없음") }
        // Normalize sub-tenth changes to zero so rounding cannot produce a misleading -0.0.
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0.0 kg" }
        return String(format: "%+.1f kg", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}

private struct ActivityCard: View {
    let snapshot: UsagiState
    let character: UIImage

    private let background = Color(red: 0.055, green: 0.085, blue: 0.067)
    private let accent = Color(red: 0.73, green: 0.90, blue: 0.50)
    private let muted = Color(red: 0.67, green: 0.73, blue: 0.67)
    private var completion: Int { Int((Double(snapshot.daily.steps) / Double(snapshot.daily.goalSteps) * 100).rounded(.down)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RE:PICK").font(AppFont.fixed(size: 17, weight: .bold))
                Spacer()
                Text(snapshot.daily.day.replacingOccurrences(of: "-", with: "."))
                    .font(AppFont.fixed(size: 11, weight: .medium)).foregroundStyle(muted)
            }
            Spacer().frame(height: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.preferences.name)
                    .font(AppFont.fixed(size: 30, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .frame(height: 66, alignment: .bottomLeading)
                Text("\(snapshot.preferences.character.name) · \(snapshot.equippedOutfit.name)")
                    .font(AppFont.fixed(size: 12, weight: .medium)).foregroundStyle(muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Image(uiImage: character).resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("체중 변화").foregroundStyle(.white)
                    if snapshot.weightChangeKG != nil {
                        Text("기준 기록 대비").foregroundStyle(muted)
                    }
                }.font(AppFont.fixed(size: 12, weight: .medium))
                Text(ShareCardText.weightChange(snapshot.weightChangeKG))
                    .font(AppFont.fixed(size: snapshot.weightChangeKG == nil ? 27 : 40, weight: .bold))
                    .monospacedDigit().foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 16)
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            Spacer().frame(height: 18)
            HStack(alignment: .top, spacing: 8) {
                metric("걸음 수", value: "\(snapshot.daily.steps.formatted())보")
                metric("목표 달성률", value: "\(completion)%")
                metric("물", value: "\(snapshot.daily.waterML.formatted())mL")
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 34)
        .foregroundStyle(.white)
        .background(background)
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.fixed(size: 11, weight: .medium)).foregroundStyle(muted)
            Text(value).font(AppFont.fixed(size: 17, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
