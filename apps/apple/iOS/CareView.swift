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
    @State private var showAttendance = false
    @State private var showMissions = false
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
                    VStack(spacing: 8) {
                        characterStage
                        if let growthSummary {
                            Text(growthSummary)
                                .font(AppFont.font(.caption, weight: .medium))
                                .foregroundStyle(Color.repickSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("care.growth")
                        }
                    }
                    nutritionCard
                    selectedMetrics
                    missionEntry
                    attendanceEntry
                    recordActions
                    goalCard
                    VStack(spacing: 12) {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showComparison.toggle() }
                        } label: {
                            HStack {
                                Text("기록에 따른 캐릭터 비교").font(AppFont.font(.headline))
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
            .fullScreenCover(isPresented: $showAttendance) { AttendanceView() }
            .fullScreenCover(isPresented: $showMissions) { DailyMissionView() }
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
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    Circle().stroke(Color.repickBorder, lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, Double(store.state.daily.steps) / Double(store.state.daily.goalSteps)))
                        .stroke(Color.repickGold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: store.state.daily.isGoalComplete ? "checkmark" : "figure.walk")
                        .font(.title3.weight(.semibold)).foregroundStyle(Color.repickGold)
                }
                .frame(width: 48, height: 48)
                .padding(3)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("목표").font(AppFont.font(.caption, weight: .medium)).foregroundStyle(Color.repickSecondaryText)
                Text(store.state.preferences.goalTitle.isEmpty
                     ? String(localized: "하루 \(store.state.daily.goalSteps.formatted())보 걷기")
                     : store.state.preferences.goalTitle)
                    .font(AppFont.font(.title3, weight: .semibold))
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
                             isAnimating: !showMeal && !showProfile && !showAttendance && !showMissions && shareSnapshot == nil,
                             accessibilityIdentifier: "care.current3d", character: store.state.preferences.character,
                             equippedItems: store.state.equippedItems,
                             muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                             nutritionMood: store.state.nutritionMood, costume: store.state.currentCostume)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                                 heading: 180, cameraHeading: 0, motion: displayedMotion,
                                 waterLevel: Double(store.state.daily.waterML) / 2_000,
                                 accessibilityIdentifier: "care.compareCurrent3d", character: store.state.preferences.character,
                                 equippedItems: store.state.equippedItems,
                                 muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                                 nutritionMood: store.state.nutritionMood, costume: store.state.currentCostume)
                        .frame(height: 190)
                        .accessibilityLabel("오늘 기록에 따른 캐릭터: \(displayedMotion.displayName)")
                    Text("오늘 기록").font(AppFont.font(.subheadline, weight: .semibold))
                    Text(nutritionTitle).font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                }.frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    MapUsagiView(bodyScale: store.state.targetBodyScale, outfit: store.state.equippedOutfit,
                                 heading: 180, cameraHeading: 0, isAnimating: false,
                                 accessibilityIdentifier: "care.target3d", character: store.state.preferences.character,
                                 equippedItems: store.state.equippedItems, muscleLevel: store.state.muscleLevel,
                                 costume: store.state.currentCostume)
                        .frame(height: 190)
                        .accessibilityLabel("섭취 칼로리 범위 안의 기준 캐릭터")
                    Text("범위 내 기준").font(AppFont.font(.subheadline, weight: .semibold))
                    Text("비교용 모습").font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                }.frame(maxWidth: .infinity)
            }
            Text("오늘 기록한 섭취량에 따른 게임 속 표현이며, 실제 몸무게나 체형을 뜻하지 않아요.")
                .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
        }
    }

    private var nutritionCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("오늘의 섭취 기록").font(AppFont.font(.caption, weight: .medium)).foregroundStyle(Color.repickSecondaryText)
                        Text(nutritionTitle)
                            .font(AppFont.font(.title3, weight: .bold))
                            .accessibilityIdentifier("care.nutrition.status")
                    }
                    Spacer(minLength: 8)
                    Image(systemName: nutritionIcon).font(.title2).foregroundStyle(Color.repickGold).accessibilityHidden(true)
                }
                if !store.state.daily.meals.isEmpty {
                    Text("\(store.state.recordedCaloriesToday.formatted()) kcal 기록")
                        .font(AppFont.font(.title2, weight: .semibold)).monospacedDigit()
                        .accessibilityIdentifier("care.nutrition.calories")
                }
                if let minimum = store.state.dailyCalorieMinimum, let maximum = store.state.dailyCalorieMaximum {
                    Text("오늘 적용 범위 \(minimum.formatted())–\(maximum.formatted()) kcal")
                        .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                    if !store.state.daily.meals.isEmpty { calorieTrack(minimum: minimum, maximum: maximum) }
                }
                mealMarkers
                if let nutritionDetail {
                    Text(nutritionDetail)
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.state.calorieRangeChangesTomorrow {
                    Text("변경한 칼로리 범위는 내일부터 적용돼요.")
                        .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                }
                if store.state.nutritionStatus == .unconfigured {
                    Button("나의 칼로리 범위 설정") { showProfile = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("care.nutrition.configure")
                }
            }
        }
    }

    private var nutritionTitle: String {
        switch store.state.nutritionStatus {
        case .unconfigured: String(localized: "나의 범위를 설정해 주세요")
        case .unrecorded: String(localized: "아직 식사 기록이 없어요")
        case .below: String(localized: "기록한 섭취량이 범위보다 적어요")
        case .within: String(localized: "기록한 섭취량이 범위 안에 있어요")
        case .above: String(localized: "기록한 섭취량이 범위보다 많아요")
        }
    }

    private func calorieTrack(minimum: Int, maximum: Int) -> some View {
        let total = store.state.recordedCaloriesToday
        let scale = Double(max(maximum, total)) * 1.12
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.repickBorder.opacity(0.6))
                Capsule().fill(Color.repickYellow)
                    .frame(width: max(4, geometry.size.width * Double(maximum - minimum) / scale))
                    .offset(x: geometry.size.width * Double(minimum) / scale)
                Circle().fill(Color.repickGold)
                    .overlay { Circle().strokeBorder(Color.repickSurface, lineWidth: 3) }
                    .frame(width: 18, height: 18)
                    .offset(x: min(geometry.size.width - 18, max(0, geometry.size.width * Double(total) / scale - 9)))
            }
            .frame(height: 10)
            .frame(height: geometry.size.height)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private var mealMarkers: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach([MealKind.breakfast, .lunch, .dinner]) { kind in
                let recorded = store.state.daily.meals.contains { $0.kind == kind }
                Label(kind.name, systemImage: recorded ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.font(.caption, weight: .medium))
                    .foregroundStyle(recorded ? Color.repickGold : Color.repickSecondaryText)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(recorded ? Color.repickYellow.opacity(0.32) : Color.repickCream,
                                in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("\(kind.name), \(recorded ? String(localized: "기록 완료") : String(localized: "기록 없음"))")
            }
        }
    }

    private var nutritionIcon: String {
        switch store.state.nutritionStatus {
        case .unconfigured: "slider.horizontal.3"
        case .unrecorded: "fork.knife"
        case .below: "moon.zzz"
        case .within: "sparkles"
        case .above: "chart.bar.fill"
        }
    }

    private var nutritionDetail: String? {
        switch store.state.nutritionStatus {
        case .unconfigured: String(localized: "직접 정한 하루 칼로리 범위와 식사 기록으로 캐릭터의 오늘 모습을 확인해요.")
        case .unrecorded: String(localized: "미기록을 적게 먹은 날로 판단하지 않아요. 식사를 기록하면 오늘의 상태를 볼 수 있어요.")
        case .below: String(localized: "현재 입력한 기록만 반영한 모습이에요. 빠진 식사가 있다면 기록해 주세요. 최소보다 적은 기록은 칼로리 미션 보상 대상이 아니에요.")
        case .within: String(localized: "캐릭터가 반짝여요. 세 끼를 모두 기록했다면 미션에서 오늘 식사를 마무리할 수 있어요.")
        case .above: nil
        }
    }

    private var missionEntry: some View {
        Button { showMissions = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.title2).frame(width: 44, height: 44)
                    .background(Color.repickRewardSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘의 미션").font(AppFont.font(.headline))
                    Text("칼로리 범위 · 계단 5칸 · 세 끼 기록")
                        .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    Text("미션마다 \(store.state.missionRewardPoints)P · \(DailyMissionKind.allCases.filter { store.state.missionRewardClaimed($0) }.count)/3 수령")
                        .font(AppFont.font(.caption, weight: .medium)).foregroundStyle(Color.repickGold)
                    HStack(spacing: 6) {
                        ForEach(DailyMissionKind.allCases) { mission in
                            Capsule().fill(store.state.missionRewardClaimed(mission) ? Color.repickGold : Color.repickBorder)
                                .frame(height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .padding(Design.cardPadding)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Design.cardRadius).strokeBorder(Color.repickBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("care.missions")
    }

    private var selectedMetrics: some View {
        let columns = store.state.preferences.homeMetrics.count == 3 && dynamicTypeSize <= .large
            ? Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
            : [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 130), spacing: 16)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(store.state.preferences.homeMetrics) { metric in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: metricIcon(metric))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(metric == .water ? Color.blue : Color.repickGold)
                        .frame(width: 36, height: 36)
                        .background(metric == .water ? Color.blue.opacity(0.09) : Color.repickYellow.opacity(0.3), in: Circle())
                        .accessibilityHidden(true)
                    Text(metric.name).font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    Text(metricValue(metric))
                        .font(AppFont.font(.title3, weight: .semibold)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier(metric == .water ? "water.total" : "home.metric.\(metric.rawValue)")
                    if let detail = metricDetail(metric) {
                        Text(detail).font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                .overlay { RoundedRectangle(cornerRadius: Design.controlRadius).strokeBorder(Color.repickBorder, lineWidth: 0.5) }
            }
        }
    }

    private func metricIcon(_ metric: HomeMetric) -> String {
        switch metric {
        case .steps: "figure.walk"
        case .calories: "fork.knife"
        case .water: "drop.fill"
        case .workoutMinutes: "stopwatch"
        case .weightChange: "scalemass"
        }
    }

    private var attendanceEntry: some View {
        Button { showAttendance = true } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.repickRewardSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            attendanceTitle
                            attendanceStatus
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            attendanceTitle
                            attendanceStatus
                        }
                    }
                    Text(attendanceMilestone)
                        .font(AppFont.font(.caption, weight: .medium))
                        .foregroundStyle(Color.repickSecondaryText)
                    Text("10·20·30일… 출석과 당일 걸음 목표 달성 시 무료 뽑기 1회")
                        .font(AppFont.font(.caption2, weight: .medium))
                        .foregroundStyle(Color.repickSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.repickSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(Design.cardPadding)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Design.cardRadius).strokeBorder(Color.repickBorder, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("care.attendance")
    }

    private var growthSummary: String? {
        var parts: [String] = []
        if store.state.totalExerciseCalories > 0 {
            parts.append(String(localized: "누적 운동 소모 \(store.state.totalExerciseCalories.formatted()) kcal (입력·추정)"))
        }
        if store.state.totalStrengthMinutes > 0 {
            parts.append(String(localized: "근력 \(store.state.totalStrengthMinutes.formatted())분"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var attendanceTitle: some View {
        Text("연속 \(store.state.attendanceStreak)일 출석")
            .font(AppFont.font(.subheadline, weight: .bold))
    }

    private var attendanceStatus: some View {
        Text(store.state.hasCheckedInToday ? "오늘 완료" : "출석 전")
            .font(AppFont.font(.caption2, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.repickRewardSurface, in: Capsule())
    }

    private var attendanceMilestone: String {
        let streak = store.state.attendanceStreak
        if store.state.hasCheckedInToday, streak > 0, streak.isMultiple(of: 10),
           store.state.attendance.lastRewardDay != store.state.daily.day {
            return String(localized: "오늘 \(store.state.daily.goalSteps.formatted())보를 채우면 무료 1회 · 보유 \(store.state.freeDraws)회")
        }
        if store.state.attendance.lastRewardDay == store.state.daily.day {
            return String(localized: "오늘 무료 뽑기 1회 획득 · 보유 \(store.state.freeDraws)회")
        }
        let nextMilestone = (streak / 10 + 1) * 10
        return String(localized: "다음 \(nextMilestone)일까지 \(nextMilestone - streak)일 · 무료 뽑기 \(store.state.freeDraws)회 보유")
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
            if let minimum = store.state.dailyCalorieMinimum, let maximum = store.state.dailyCalorieMaximum {
                String(localized: "오늘 범위 \(minimum.formatted())–\(maximum.formatted()) kcal")
            } else { nil }
        case .water, .workoutMinutes: nil
        case .weightChange: String(localized: store.state.weightChangeKG == nil ? "비교 기록 없음" : "기준 기록 대비")
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("걸음 목표").font(AppFont.font(.headline))
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
                    .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                if store.state.daily.isGoalComplete {
                    if store.state.daily.rewardClaimed {
                        Label("보상 수령 완료", systemImage: "checkmark.circle.fill")
                            .font(AppFont.font(.subheadline, weight: .medium)).foregroundStyle(Color.repickGreen)
                    } else {
                        Button("\(store.state.daily.goalReward)P 받기") {
                            Task { await store.update { try $0.claimReward() } }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("care.claimReward")
                    }
                }
                Text(steps.status).font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                if !steps.isTracking {
                    Button("걸음 수 연동", systemImage: "figure.walk") { steps.start() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                if let goal = store.state.nextGoalSteps {
                    Text("내일 목표 \(goal.formatted())보")
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                }
        }
    }

    private var stepTotal: some View {
        Text("\(store.state.daily.steps.formatted())보")
            .font(AppFont.font(.title2, weight: .semibold))
            .monospacedDigit()
    }

    private var goalTotal: some View {
        Text("목표 \(store.state.daily.goalSteps.formatted())보")
            .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
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
