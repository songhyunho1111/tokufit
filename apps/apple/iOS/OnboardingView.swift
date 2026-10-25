import SwiftUI
import REPickShared

struct OnboardingView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = OnboardingDraft()
    @State private var isLoaded = false
    @State private var isAdvancing = false
    @State private var errorMessage: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var disk = OnboardingDraftStore()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if isLoaded {
                    ScrollView {
                        VStack(spacing: 20) {
                            progressHeader
                            MapUsagiView(bodyScale: previewBodyScale, heading: 180, cameraHeading: 0,
                                         accessibilityIdentifier: "onboarding.usagi", onboardingPose: characterPose)
                                .frame(height: min(290, max(170, geometry.size.height * 0.34)))
                                .accessibilityHidden(true)
                            VStack(spacing: 8) {
                                Text(reply).font(.title3.weight(.medium)).foregroundStyle(OnboardingPalette.accent)
                                Text(question).font(.title2.weight(.semibold))
                                    .multilineTextAlignment(.center)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("onboarding.question")
                            input.disabled(isAdvancing)
                            if let errorMessage {
                                VStack(spacing: 8) {
                                    Text(errorMessage).font(.footnote).foregroundStyle(OnboardingPalette.error)
                                    Button("다시 저장") { saveDraftSoon(immediately: true) }
                                }
                            }
                        }
                        .frame(maxWidth: Design.contentWidth)
                        .padding(.horizontal, Design.pagePadding)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button(isAdvancing ? "저장 중…" : draft.step == .goal ? "시작하기" : "다음") {
                            Task { await advance() }
                        }
                        .buttonStyle(OnboardingContinueStyle())
                        .disabled(isAdvancing || store.isSaving || (draft.step == .gender && draft.gender == nil))
                        .accessibilityIdentifier("onboarding.next")
                        .frame(maxWidth: Design.contentWidth)
                        .padding(.horizontal, Design.pagePadding)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            LinearGradient(colors: [.clear, OnboardingPalette.night.opacity(0.96)],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom)
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("입력 내용을 불러오지 못했어요", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("다시 불러오기") { Task { await load() } }
                    }
                } else {
                    ProgressView("불러오는 중")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingBackdrop() }
            .foregroundStyle(OnboardingPalette.ivory)
            .tint(OnboardingPalette.accent)
        }
        .preferredColorScheme(.dark)
        .task {
            #if DEBUG
            do { try await disk.resetForUITestIfRequested() }
            catch { errorMessage = error.localizedDescription; return }
            #endif
            await load()
        }
        .onChange(of: draft) { _, _ in saveDraftSoon() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraftSoon(immediately: true) }
        }
        .onDisappear { autosaveTask?.cancel() }
    }

    private var progressHeader: some View {
        HStack {
            Button {
                Task { await move(to: OnboardingDraft.Step(rawValue: draft.step.rawValue - 1) ?? .height) }
            } label: {
                Label("이전", systemImage: "chevron.left").frame(minHeight: 44)
            }
            .disabled(draft.step == .height || isAdvancing)
            .opacity(draft.step == .height ? 0 : 1)
            .accessibilityHidden(draft.step == .height)
            .accessibilityIdentifier("onboarding.back")
            Spacer()
            Text("\(draft.step.rawValue + 1) / 4")
                .font(.subheadline).monospacedDigit().foregroundStyle(OnboardingPalette.secondary)
                .accessibilityLabel("4단계 중 \(draft.step.rawValue + 1)단계")
        }
    }

    private var characterPose: UsagiOnboardingPose {
        switch draft.step {
        case .height: .height
        case .weight: .weight
        case .gender: .gender
        case .goal: .goal
        }
    }

    private var reply: LocalizedStringKey {
        switch draft.step {
        case .height: "야하(반가워!)"
        case .weight: "푸루(알겠어)"
        case .gender: "우라(좋아!)"
        case .goal: "푸루(거의 다 됐어)"
        }
    }

    private var question: LocalizedStringKey {
        switch draft.step {
        case .height: "키가 얼마나 돼?"
        case .weight: "몸무게도 알려줘."
        case .gender: "성별을 고를래?"
        case .goal: "하루에 얼마나 걸을까?"
        }
    }

    @ViewBuilder
    private var input: some View {
        switch draft.step {
        case .height:
            OnboardingMeasure(value: $draft.heightCM, range: 80...250, divisor: 1,
                              label: "키", unit: "cm", identifier: "onboarding.height")
        case .weight:
            OnboardingMeasure(value: $draft.weightTenthsKG, range: 200...3_500, divisor: 10,
                              label: "몸무게", unit: "kg", identifier: "onboarding.weight")
        case .gender:
            VStack(spacing: 8) {
                ForEach(ProfileGender.allCases) { gender in
                    Button {
                        draft.gender = gender
                    } label: {
                        HStack {
                            Text(gender.name)
                            Spacer()
                            if draft.gender == gender { Image(systemName: "checkmark.circle.fill") }
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(draft.gender == gender ? OnboardingPalette.night : OnboardingPalette.ivory)
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .background(draft.gender == gender ? OnboardingPalette.accent : OnboardingPalette.control,
                                    in: RoundedRectangle(cornerRadius: Design.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.gender == gender ? .isSelected : [])
                    .accessibilityIdentifier("onboarding.gender.\(gender.rawValue)")
                }
            }
        case .goal:
            VStack(spacing: 12) {
                Text("\(draft.goalSteps.formatted())보").font(.largeTitle.weight(.semibold)).monospacedDigit()
                Stepper("하루 걸음 목표", value: $draft.goalSteps, in: 2_000...10_000, step: 1_000)
                    .labelsHidden()
                    .accessibilityLabel("하루 걸음 목표")
                    .accessibilityValue("\(draft.goalSteps)보")
                    .accessibilityIdentifier("onboarding.goal")
                Text("달성하면 \(draft.goalSteps / 1_000 * 50)P · 뽑기 최대 \(draft.goalSteps / 2_000)회")
                    .font(.footnote).foregroundStyle(OnboardingPalette.secondary)
                Text("목표는 나중에 바꿀 수 있어.")
                    .font(.footnote).foregroundStyle(OnboardingPalette.secondary)
            }
        }
    }

    private var previewBodyScale: Double {
        guard draft.step != .height else { return 1 }
        var preview = UsagiState()
        try? preview.setProfile(heightCM: Double(draft.heightCM), weightKG: draft.weightKG,
                                targetWeightKG: draft.weightKG, goalSteps: draft.goalSteps)
        return preview.bodyScale
    }

    private func load() async {
        do {
            let saved = try await disk.load()
            try Task.checkCancellation()
            draft = saved
            isLoaded = true
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDraftSoon(immediately: Bool = false) {
        guard isLoaded else { return }
        autosaveTask?.cancel()
        let snapshot = draft
        autosaveTask = Task {
            do {
                if !immediately { try await Task.sleep(for: .milliseconds(200)) }
                try await disk.save(snapshot)
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func move(to step: OnboardingDraft.Step) async {
        guard !isAdvancing else { return }
        autosaveTask?.cancel()
        isAdvancing = true
        defer { isAdvancing = false }
        var next = draft
        next.step = step
        do {
            try await disk.save(next)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { draft = next }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func advance() async {
        guard !isAdvancing else { return }
        if let next = OnboardingDraft.Step(rawValue: draft.step.rawValue + 1) {
            await move(to: next)
            return
        }
        autosaveTask?.cancel()
        isAdvancing = true
        defer { isAdvancing = false }
        do {
            try await disk.save(draft)
            let saved = draft
            if !(await store.update({ try $0.setProfile(heightCM: Double(saved.heightCM), weightKG: saved.weightKG,
                                                      targetWeightKG: saved.weightKG, goalSteps: saved.goalSteps,
                                                      gender: saved.gender) })) {
                errorMessage = store.errorMessage ?? String(localized: "저장하지 못했습니다. 다시 시도해 주세요.")
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct OnboardingMeasure: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let divisor: Int
    let label: LocalizedStringKey
    let unit: String
    let identifier: String

    private var number: String {
        (Double(value) / Double(divisor)).formatted(.number.precision(.fractionLength(divisor == 1 ? 0 : 1)))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number).font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text(unit).font(.title3).foregroundStyle(OnboardingPalette.secondary)
            }
            HStack(spacing: 16) {
                Button { value = max(range.lowerBound, value - 1) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered).buttonRepeatBehavior(.enabled)
                .disabled(value <= range.lowerBound)
                .accessibilityLabel(Text(label) + Text(" 줄이기"))
                .accessibilityIdentifier(identifier + ".decrease")
                Slider(value: Binding(get: { Double(value) }, set: { input in
                    guard input.isFinite else { return }
                    value = min(range.upperBound, max(range.lowerBound, Int(input.rounded())))
                }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .accessibilityLabel(label)
                    .accessibilityValue("\(number) \(unit)")
                    .accessibilityIdentifier(identifier)
                Button { value = min(range.upperBound, value + 1) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered).buttonRepeatBehavior(.enabled)
                .disabled(value >= range.upperBound)
                .accessibilityLabel(Text(label) + Text(" 늘리기"))
                .accessibilityIdentifier(identifier + ".increase")
            }
        }
    }
}
