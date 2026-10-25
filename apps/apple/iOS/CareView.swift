import SwiftUI
import REPickShared

struct CareView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let steps: StepTracker
    @State private var showProfile = false
    @State private var showMeal = false
    @State private var shareSnapshot: UsagiState?
    @State private var showComparison = false
    @State private var reaction: UsagiMotion?
    @State private var reactionID = 0
    @State private var nextReaction = 0

    private var displayedMotion: UsagiMotion { reaction ?? .idle }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                    goalHeading
                    characterStage
                    selectedMetrics
                    recordActions
                    goalCard
                    VStack(spacing: 12) {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showComparison.toggle() }
                        } label: {
                            HStack {
                                Text("체형 비교").font(.headline)
                                Spacer()
                                Image(systemName: showComparison ? "chevron.up" : "chevron.down").font(.subheadline)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(showComparison ? "펼침" : "접힘")
                        .accessibilityIdentifier("care.compare")
                        if showComparison { bodyComparison }
                    }
                }
                .frame(maxWidth: Design.contentWidth, alignment: .leading)
                .padding(.horizontal, Design.pagePadding)
                .padding(.vertical, Design.cardPadding)
                .frame(maxWidth: .infinity)
            }
            .background(Color.repickCream)
            .navigationTitle(store.state.preferences.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PointsToolbar(points: store.state.points)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shareSnapshot = store.state
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.state.profile == nil || store.isSaving)
                    .accessibilityLabel("기록 공유")
                    .accessibilityIdentifier("care.share")
                }
            }
            .sheet(isPresented: $showProfile) { ProfileEditor() }
            .sheet(isPresented: $showMeal) { MealView() }
            .sheet(isPresented: Binding(get: { shareSnapshot != nil }, set: { if !$0 { shareSnapshot = nil } })) {
                if let shareSnapshot { ShareCardView(snapshot: shareSnapshot) }
            }
            .task(id: reactionID) {
                guard reaction != nil else { return }
                do { try await Task.sleep(for: .milliseconds(2_400)) }
                catch { return }
                reaction = nil
            }
            .onChange(of: store.motion) { _, motion in
                guard motion != .idle else { return }
                playReaction(motion)
                store.motion = .idle
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { reaction = nil }
            }
            .onDisappear { reaction = nil }
            .sensoryFeedback(.selection, trigger: reactionID)
        }
    }

    private var goalHeading: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("목표").font(.caption.weight(.medium)).foregroundStyle(Color.repickSecondaryText)
                Text(store.state.preferences.goalTitle.isEmpty
                     ? String(localized: "하루 \(store.state.daily.goalSteps.formatted())보 걷기")
                     : store.state.preferences.goalTitle)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("home.goal")
            }
            Spacer(minLength: 0)
            Button { showProfile = true } label: {
                Image(systemName: "pencil").frame(width: 44, height: 44)
            }
            .accessibilityLabel("목표와 프로필 수정")
            .accessibilityIdentifier("care.editProfile")
        }
    }

    private var characterStage: some View {
        ZStack(alignment: .bottom) {
            CompanionRoomView()
            Button(action: reactToTap) {
                MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                             heading: 180, cameraHeading: 0, motion: displayedMotion,
                             waterLevel: Double(store.state.daily.waterML) / 2_000,
                             isAnimating: !showMeal && !showProfile && shareSnapshot == nil,
                             accessibilityIdentifier: "care.current3d", character: store.state.preferences.character,
                             equippedItems: store.state.equippedItems)
                    .frame(height: 236)
                    .frame(maxWidth: 280)
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .accessibilityLabel("\(store.state.preferences.name) 반응 보기")
            .accessibilityValue(displayedMotion.displayName)
            .accessibilityHint("누르면 짧은 동작으로 반응합니다.")
            .accessibilityIdentifier("care.character")
        }
        .frame(height: 264)
        .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius))
        .overlay(alignment: .topTrailing) { motionPicker.padding(4) }
    }

    private var bodyComparison: some View {
        HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                                 heading: 180, cameraHeading: 0, motion: displayedMotion,
                                 waterLevel: Double(store.state.daily.waterML) / 2_000,
                                 accessibilityIdentifier: "care.compareCurrent3d", character: store.state.preferences.character,
                                 equippedItems: store.state.equippedItems)
                        .frame(height: 190)
                        .accessibilityLabel("현재 체형: \(displayedMotion.displayName)")
                    Text("현재").font(.subheadline.weight(.semibold))
                    if let profile = store.state.profile {
                        Text("\(profile.weightKG.formatted()) kg")
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(Color.repickSecondaryText)
                    }
                }.frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    MapUsagiView(bodyScale: store.state.targetBodyScale, outfit: store.state.equippedOutfit,
                                 heading: 180, cameraHeading: 0, isAnimating: false,
                                 accessibilityIdentifier: "care.target3d", character: store.state.preferences.character,
                                 equippedItems: store.state.equippedItems)
                        .frame(height: 190)
                        .accessibilityLabel("목표 체형의 3D 캐릭터")
                    Text("목표").font(.subheadline.weight(.semibold))
                    if let profile = store.state.profile {
                        Text("\(profile.targetWeightKG.formatted()) kg")
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(Color.repickSecondaryText)
                    }
                }.frame(maxWidth: .infinity)
        }
    }

    private var selectedMetrics: some View {
        let columns = store.state.preferences.homeMetrics.count == 3 && dynamicTypeSize <= .large
            ? Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
            : [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 130), spacing: 16)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(store.state.preferences.homeMetrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.name).font(.caption).foregroundStyle(Color.repickSecondaryText)
                    Text(metricValue(metric))
                        .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier(metric == .water ? "water.total" : "home.metric.\(metric.rawValue)")
                    if let detail = metricDetail(metric) {
                        Text(detail).font(.caption).foregroundStyle(Color.repickSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(Design.cardPadding)
        .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
    }

    private func metricValue(_ metric: HomeMetric) -> String {
        switch metric {
        case .steps: String(localized: "\(store.state.daily.steps.formatted())보")
        case .calories: String(localized: "\(store.state.daily.meals.reduce(0) { $0 + $1.calories }.formatted()) kcal")
        case .water: String(localized: "\(store.state.daily.waterML) mL")
        case .workoutMinutes: String(localized: "\(store.state.workoutMinutesToday)분")
        case .weightChange:
            if let change = store.state.weightChangeKG {
                String(localized: "\(change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) kg")
            } else { "—" }
        }
    }

    private func metricDetail(_ metric: HomeMetric) -> String? {
        switch metric {
        case .steps: String(localized: "목표 \(store.state.daily.goalSteps.formatted())보")
        case .calories:
            if let minimum = store.state.preferences.calorieMinimum, let maximum = store.state.preferences.calorieMaximum {
                String(localized: "목표 \(minimum.formatted())–\(maximum.formatted()) kcal")
            } else { nil }
        case .water, .workoutMinutes: nil
        case .weightChange: String(localized: store.state.weightChangeKG == nil ? "비교 기록 없음" : "기준 기록 대비")
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("걸음 목표").font(.headline)
                if !store.state.preferences.homeMetrics.contains(.steps) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        stepTotal
                        goalTotal
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        stepTotal
                        goalTotal
                    }
                }
                }
                ProgressView(value: min(1, Double(store.state.daily.steps) / Double(store.state.daily.goalSteps)))
                    .tint(.repickGreen)
                    .accessibilityLabel("오늘 목표 달성률")
                Text("달성 보상 \(store.state.daily.goalReward)P · 뽑기 최대 \(store.state.daily.maximumDraws)회")
                    .font(.footnote).foregroundStyle(Color.repickSecondaryText)
                if store.state.daily.isGoalComplete {
                    if store.state.daily.rewardClaimed {
                        Label("보상 수령 완료", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.repickGreen)
                    } else {
                        Button("\(store.state.daily.goalReward)P 받기") {
                            Task { await store.update { try $0.claimReward() } }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("care.claimReward")
                    }
                }
                Text(steps.status).font(.footnote).foregroundStyle(Color.repickSecondaryText)
                if !steps.isTracking {
                    Button("걸음 수 연동", systemImage: "figure.walk") { steps.start() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                if let goal = store.state.nextGoalSteps {
                    Text("내일 목표 \(goal.formatted())보")
                        .font(.footnote).foregroundStyle(Color.repickSecondaryText)
                }
        }
    }

    private var stepTotal: some View {
        Text("\(store.state.daily.steps.formatted())보")
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .monospacedDigit()
    }

    private var goalTotal: some View {
        Text("목표 \(store.state.daily.goalSteps.formatted())보")
            .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
    }

    private var recordActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button { showMeal = true } label: { Label("음식 기록", systemImage: "fork.knife") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("addMeal")
            Button("물 +250 mL") {
                Task {
                    if await store.update({ try $0.addWater(250) }) { store.motion = .drinking }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.isSaving || store.state.daily.waterML >= 10_000)
            .accessibilityLabel("물 250밀리리터 추가")
            .accessibilityIdentifier("addWater")
        }
    }

    private var motionPicker: some View {
            Menu {
                ForEach(UsagiMotion.allCases) { motion in
                    Button {
                        playReaction(motion)
                    } label: {
                        HStack {
                            Text(motion.displayName)
                            if displayedMotion == motion { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("care.motion.\(motion.rawValue)")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.repickInk)
                    .background(Color.repickSurface.opacity(0.9), in: Circle())
            }
            .accessibilityLabel("캐릭터 동작 선택")
            .accessibilityValue(displayedMotion.displayName)
            .accessibilityIdentifier("care.motionMenu")
    }

    private func reactToTap() {
        let motions: [UsagiMotion] = [.exercising, .walking, .grazing, .drinking]
        var selected = motions[nextReaction % motions.count]
        nextReaction += 1
        if selected == displayedMotion {
            selected = motions[nextReaction % motions.count]
            nextReaction += 1
        }
        playReaction(selected)
    }

    private func playReaction(_ motion: UsagiMotion) {
        reaction = motion == .idle ? nil : motion
        reactionID += 1
    }
}

extension UsagiMotion {
    var displayName: String {
        switch self {
        case .idle: String(localized: "쉬기")
        case .walking: String(localized: "걷기")
        case .exercising: String(localized: "운동")
        case .grazing: String(localized: "풀 먹기")
        case .sweating: String(localized: "땀")
        case .eating: String(localized: "떡볶이 먹기")
        case .drinking: String(localized: "물 마시기")
        }
    }
}
