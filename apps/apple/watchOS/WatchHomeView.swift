import REPickShared
import SwiftUI

struct WatchHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: UsagiMotion = .idle
    @State private var selectedPage = 0
    let companion: WatchCompanion

    private let yellow = Color(red: 0.98, green: 0.85, blue: 0.38)

    var body: some View {
        TabView(selection: $selectedPage) {
            characterPage.tag(0)
            activityPage.tag(1)
            motionPage.tag(2)
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(.black, for: .tabView)
        .foregroundStyle(.white)
        .onChange(of: companion.state?.activeWorkout?.id) { _, id in
            if id != nil { selectedPage = 0 }
        }
        .onChange(of: supportsSpriteMotions) { _, supported in
            if !supported { motion = .idle }
        }
    }

    private var characterPage: some View {
        GeometryReader { geometry in
            TimelineView(.everyMinute) { context in
                VStack(spacing: 6) {
                    if let workout = companion.state?.activeWorkout {
                        workoutDashboard(workout, at: context.date)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(companion.state?.preferences.name ?? String(localized: "나의 캐릭터"))
                                .font(AppFont.font(.caption, weight: .bold))
                                .foregroundStyle(yellow)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                .font(AppFont.font(.largeTitle, weight: .bold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .accessibilityIdentifier("watch.clock")
                        }
                        character
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("watch.usagi")
                        calorieSummary(at: context.date)
                    }
                    if companion.state?.profile == nil {
                        Text("iPhone에서 프로필을 등록하세요")
                            .font(AppFont.font(.caption2))
                            .multilineTextAlignment(.center)
                    } else if companion.isCharacterImageStale {
                        Text("이전 모습 · 동기화 대기")
                            .font(AppFont.font(.caption2)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityIdentifier("watch.character.stale")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 36)
                .padding(.bottom, 12)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private func calorieSummary(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let state = companion.state, state.profile != nil {
                let isToday = state.daily.day == UsagiState.dayKey(for: date)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(state.daily.meals.isEmpty ? "—" : state.recordedCaloriesToday.formatted())
                        .font(AppFont.font(.title2, weight: .bold)).monospacedDigit()
                    Text("kcal").font(AppFont.font(.headline, weight: .bold))
                    Spacer(minLength: 0)
                    Text(isToday ? "섭취" : "지난 기록")
                        .font(AppFont.font(.caption2))
                        .foregroundStyle(isToday ? Color.secondary : Color.orange)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                if let maximum = state.dailyCalorieMaximum, !state.daily.meals.isEmpty {
                    ProgressView(value: min(1, Double(state.recordedCaloriesToday) / Double(maximum)))
                        .tint(state.nutritionStatus == .above ? .orange : yellow)
                        .accessibilityLabel("기록한 섭취량")
                        .accessibilityValue("\(state.recordedCaloriesToday) / \(maximum) kcal")
                } else {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("watch.calories")
    }

    private func workoutDashboard(_ workout: WorkoutSession, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(workout.activity?.name ?? workout.mode.name) 중")
                .font(AppFont.font(.caption, weight: .bold)).foregroundStyle(yellow)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(workout.startedAt, style: .timer)
                .font(AppFont.font(.largeTitle, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("운동 경과 시간")
                .accessibilityIdentifier("watch.workout.elapsed")
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(companion.state?.daily.steps.formatted() ?? "—")보")
                        .font(AppFont.font(.title3, weight: .bold)).monospacedDigit()
                    Text("\(companion.state?.exerciseCaloriesToday.formatted() ?? "—") kcal")
                        .font(AppFont.font(.title3, weight: .bold)).monospacedDigit()
                        .foregroundStyle(yellow)
                    Text(companion.state?.daily.day == UsagiState.dayKey(for: date) ? "오늘 기록" : "지난 기록")
                        .font(AppFont.font(.caption2)).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                character
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("watch.usagi")
            }
            .frame(maxHeight: .infinity)
            Button("기록 보기") { selectedPage = 1 }
                .font(AppFont.font(.headline, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(yellow, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.workout.records")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var displayedMotion: UsagiMotion {
        guard let workout = companion.state?.activeWorkout else { return motion }
        return workout.mode == .indoor ? .exercising : .walking
    }

    private var canAnimate: Bool {
        selectedPage == 0 && scenePhase == .active && !isLuminanceReduced && !reduceMotion
    }

    private var supportsSpriteMotions: Bool {
        companion.state?.preferences.character == .usagi && companion.state?.equippedItems.isEmpty == true
            && (companion.state?.muscleLevel ?? 0) == 0 && companion.state?.attendanceNeedsAttention != true
            && companion.state?.currentCostume == nil && (companion.state?.nutritionMood ?? .neutral) == .neutral
    }

    @ViewBuilder
    private var character: some View {
        if supportsSpriteMotions, displayedMotion != .idle {
            UsagiView(bodyScale: companion.state?.bodyScale ?? 1,
                      outfit: companion.state?.equippedOutfit ?? .basic,
                      motion: displayedMotion,
                      waterLevel: Double(companion.state?.daily.waterML ?? 0) / 2_000,
                      isAnimating: canAnimate)
        } else if let image = companion.characterImage {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !canAnimate)) { context in
                let isResting = displayedMotion == .idle
                let phase = canAnimate ? sin(context.date.timeIntervalSinceReferenceDate * (isResting ? 2 : 4)) : 0
                // shortcut: animate the dressed snapshot until a Watch-native articulated rig is needed.
                Image(uiImage: image).resizable().scaledToFit()
                    .scaleEffect(x: 1 + phase * (isResting ? 0.008 : 0.012),
                                 y: 1 + phase * (isResting ? 0.02 : 0.012), anchor: .bottom)
                    .rotationEffect(.degrees(phase * (isResting ? 0.7 : 2)))
                    .offset(y: -abs(phase) * (isResting ? 1.5 : 3))
                    .accessibilityLabel(companion.isCharacterImageStale ? Text("이전 캐릭터 모습") : Text("현재 캐릭터"))
            }
        } else if supportsSpriteMotions {
            UsagiView(bodyScale: companion.state?.bodyScale ?? 1,
                      outfit: companion.state?.equippedOutfit ?? .basic,
                      motion: displayedMotion,
                      waterLevel: Double(companion.state?.daily.waterML ?? 0) / 2_000,
                      isAnimating: canAnimate)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.title2)
                Text("캐릭터 동기화 대기").font(AppFont.font(.caption2))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var activityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(companion.state?.preferences.name ?? String(localized: "나의 캐릭터"))
                    .font(AppFont.font(.title3, weight: .semibold)).foregroundStyle(yellow)
                Text("오늘 기록")
                    .font(AppFont.font(.headline))
                if let workout = companion.state?.activeWorkout {
                    HStack {
                        Label(workout.mode.name, systemImage: "figure.run")
                        Spacer(minLength: 4)
                        Text(workout.startedAt, style: .timer).monospacedDigit()
                    }
                    .font(AppFont.font(.caption))
                    .accessibilityIdentifier("watch.workout")
                    Text(companion.isReachable ? "iPhone에서 완료" : "저장된 운동 상태 · iPhone에서 확인")
                        .font(AppFont.font(.caption2)).foregroundStyle(.secondary)
                }
                if let state = companion.state, state.profile != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let isToday = state.daily.day == UsagiState.dayKey(for: context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isToday ? LocalizedStringKey("걸음 수") : LocalizedStringKey("지난 기록 · iPhone에서 동기화하세요"))
                                .font(AppFont.font(.caption2))
                                .foregroundStyle(isToday ? yellow : .orange)
                            Text("\(state.daily.steps.formatted()) / \(state.daily.goalSteps.formatted())걸음")
                                .font(AppFont.font(.body, weight: .bold))
                                .minimumScaleFactor(0.75)
                            ProgressView(value: min(1, Double(state.daily.steps) / Double(state.daily.goalSteps)))
                                .tint(yellow)
                            Label("\(state.daily.waterML) mL", systemImage: "drop.fill")
                                .font(AppFont.font(.caption))
                                .foregroundStyle(.cyan)
                            Label("\(state.points) P", systemImage: "sparkles")
                                .font(AppFont.font(.caption))
                            Label("운동 \(companion.workoutMinutesToday)분", systemImage: "figure.run")
                                .font(AppFont.font(.caption))
                            if let updatedAt = companion.updatedAt {
                                Text("마지막 동기화 \(updatedAt, style: .relative) 전")
                                    .font(AppFont.font(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("iPhone에서 키와 몸무게를 등록하세요.")
                        .font(AppFont.font(.caption))
                }
                Label(companion.isReachable ? "iPhone 연결됨" : "저장된 상태", systemImage: companion.isReachable ? "iphone" : "iphone.slash")
                    .font(AppFont.font(.caption2))
                    .foregroundStyle(.secondary)
                if companion.isCharacterImageStale {
                    Text("캐릭터는 이전 모습이에요. iPhone 앱을 열어 새 모습을 동기화하세요.")
                        .font(AppFont.font(.caption2)).foregroundStyle(.secondary)
                }
                if let error = companion.errorMessage {
                    Text(error).font(AppFont.font(.caption2)).foregroundStyle(.orange)
                    Button("다시 연결") { companion.activate() }
                }
                if let error = companion.complicationError {
                    Text(error).font(AppFont.font(.caption2)).foregroundStyle(.orange)
                    Button("워치페이스 새로고침") { companion.refreshConnection() }
                }
                Text("기록·의상은 iPhone에서 변경할 수 있어요.")
                    .font(AppFont.font(.caption2))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
    }

    private var motionPage: some View {
        List {
            Section("모션") {
                ForEach(supportsSpriteMotions ? UsagiMotion.allCases : [.idle, .exercising]) { choice in
                    Button {
                        motion = choice
                        selectedPage = 0
                    } label: {
                        HStack {
                            Label(choice.title, systemImage: choice.symbol)
                            Spacer(minLength: 2)
                            if motion == choice {
                                Image(systemName: "checkmark").foregroundStyle(yellow)
                            }
                        }
                    }
                    .disabled(companion.state?.activeWorkout != nil)
                    .accessibilityAddTraits(motion == choice ? .isSelected : [])
                }
            }
            Text("모션을 바꿔도 운동·식사 기록은 바뀌지 않아요.")
                .font(AppFont.font(.caption2))
                .foregroundStyle(.secondary)
        }
    }

}

private extension UsagiMotion {
    var title: LocalizedStringKey {
        switch self {
        case .idle: "쉬기"
        case .walking: "걷기"
        case .exercising: "운동"
        case .grazing: "풀 먹기"
        case .sweating: "땀"
        case .eating: "떡볶이 먹기"
        case .drinking: "물 마시기"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "sparkles"
        case .walking: "figure.walk"
        case .exercising: "dumbbell.fill"
        case .grazing: "leaf.fill"
        case .sweating: "drop.fill"
        case .eating: "fork.knife"
        case .drinking: "waterbottle.fill"
        }
    }
}

#Preview {
    WatchHomeView(companion: WatchCompanion(defaults: UserDefaults(suiteName: "REPick.preview.watch") ?? .standard))
}
