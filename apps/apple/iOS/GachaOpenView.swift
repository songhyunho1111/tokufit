import SwiftUI
import REPickShared

struct GachaOpenView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 66.5
    @State private var isOpening = false
    @State private var errorMessage: String?

    let drawID: UUID
    let randomIndex: Int
    let payment: GachaPayment
    let character: CharacterKind
    let onOpened: (GachaReceipt) -> Void

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = min(geometry.size.width, 640)
            let scale = canvasWidth / 819
            ScrollView(.vertical) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleContent(scale: scale)
                    } else {
                        referenceCanvas(scale: scale)
                    }
                }
                .frame(width: canvasWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.white.ignoresSafeArea())
        .statusBarHidden()
        .interactiveDismissDisabled(isOpening)
        .accessibilityAction(.escape) { if !isOpening { dismiss() } }
        .alert("토쿠볼을 열지 못했어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("다시 시도", action: openBall)
            Button("닫기", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func referenceCanvas(scale: CGFloat) -> some View {
        let imageScale = 568.0 / 549.0
        let imageSize = 578 * imageScale
        return ZStack(alignment: .topLeading) {
            backButton(scale: scale)
                .position(x: 64 * scale, y: 84.5 * scale)
            Text("미션 보상")
                .font(AppFont.fixed(size: labelSize * scale, weight: .medium))
                .foregroundStyle(Color(red: 119 / 255, green: 113 / 255, blue: 113 / 255))
                .frame(width: 650 * scale)
                .position(x: 404 * scale, y: 172 * scale)
                .accessibilityIdentifier("gacha.subtitle")
            Text("토쿠볼 오픈")
                .font(AppFont.fixed(size: titleSize * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 720 * scale)
                .position(x: 420 * scale, y: 262.5 * scale)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("gacha.title")
            ballButton(scale: scale)
                .position(x: (115 - 21 * imageScale + imageSize / 2) * scale,
                          y: (556 - 38 * imageScale + imageSize / 2) * scale)
            Text("탭하여 열어보세요")
                .font(AppFont.fixed(size: labelSize * scale, weight: .medium))
                .foregroundStyle(Color(red: 119 / 255, green: 113 / 255, blue: 113 / 255))
                .frame(width: 740 * scale)
                .position(x: 414.5 * scale, y: 1342 * scale)
                .accessibilityIdentifier("gacha.prompt")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: 819 * scale, height: 1656 * scale)
    }

    private func accessibleContent(scale: CGFloat) -> some View {
        VStack(spacing: 24) {
            backButton(scale: scale)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("미션 보상")
                .font(AppFont.font(.title3, weight: .medium))
                .accessibilityIdentifier("gacha.subtitle")
            Text("토쿠볼 오픈")
                .font(AppFont.font(.largeTitle, weight: .bold))
                .foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("gacha.title")
            ballButton(scale: scale)
                .padding(.vertical, 24)
            Text("탭하여 열어보세요")
                .font(AppFont.font(.title3, weight: .medium))
                .accessibilityIdentifier("gacha.prompt")
        }
        .foregroundStyle(Color(red: 119 / 255, green: 113 / 255, blue: 113 / 255))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
    }

    private func backButton(scale: CGFloat) -> some View {
        Button { dismiss() } label: {
            GachaBackChevron()
                .stroke(Color(red: 28 / 255, green: 27 / 255, blue: 31 / 255),
                        style: StrokeStyle(lineWidth: 4.5 * scale, lineCap: .round, lineJoin: .round))
                .frame(width: 24 * scale, height: 41 * scale)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .accessibilityLabel("뒤로")
        .accessibilityIdentifier("gacha.back")
    }

    private func ballButton(scale: CGFloat) -> some View {
        // The reference measures the visible artwork; retain the source image's transparent padding.
        let imageScale = 568.0 / 549.0
        let imageSize = 578 * imageScale
        return Button(action: openBall) {
            Image("GachaBall")
                .resizable()
                .scaledToFit()
                .frame(width: imageSize * scale, height: imageSize * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening || store.isSaving)
        .accessibilityLabel("토쿠볼 열기")
        .accessibilityValue(isOpening ? String(localized: "저장 중") : "")
        .accessibilityHint(payment == .free ? Text("무료 뽑기 1회를 사용합니다.") : Text("100포인트를 사용합니다."))
        .accessibilityIdentifier("gacha.ball")
    }

    private func openBall() {
        guard !isOpening, !store.isSaving else { return }
        isOpening = true
        errorMessage = nil
        Task {
            var receipt: GachaReceipt?
            let saved = await store.update {
                receipt = try $0.openGacha(id: drawID, randomIndex: randomIndex, payment: payment, character: character)
            }
            isOpening = false
            if saved, let receipt {
                onOpened(receipt)
                dismiss()
            } else {
                errorMessage = store.errorMessage ?? String(localized: "저장하지 못했어요. 기회와 포인트는 그대로예요. 다시 시도해 주세요.")
                store.errorMessage = nil
            }
        }
    }
}

private struct GachaBackChevron: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}
