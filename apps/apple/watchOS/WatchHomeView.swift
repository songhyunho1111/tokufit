import REPickShared
import SwiftUI

struct WatchHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: UsagiMotion = .idle
    @State private var selectedPage = 0
    let companion: WatchCompanion

    private let green = Color(red: 0.67, green: 0.80, blue: 0.47)

    var body: some View {
        TabView(selection: $selectedPage) {
            characterPage.tag(0)
            activityPage.tag(1)
            motionPage.tag(2)
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Color(red: 0.10, green: 0.14, blue: 0.10).gradient, for: .tabView)
        .onChange(of: companion.state?.activeWorkout?.id) { _, id in
            if id != nil { selectedPage = 0 }
        }
        .onChange(of: supportsSpriteMotions) { _, supported in
            if !supported { motion = .idle }
        }
    }

    private var characterPage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                character
                    .frame(width: max(1, geometry.size.width - 12),
                           height: max(1, geometry.size.height - 38))
                    .padding(.bottom, 4)
                    .offset(y: 10)
                    .accessibilityIdentifier("watch.usagi")
                    .accessibilityLabel(Text(companion.state?.preferences.name ?? String(localized: "캐릭터")) + Text(", ") + Text(displayedMotion.title))
                if companion.state?.profile == nil {
                    Text("iPhone에서 프로필을 등록하세요")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6).background(.black.opacity(0.8), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var displayedMotion: UsagiMotion {
        companion.state?.activeWorkout?.mode == .indoor ? .exercising : motion
    }

    private var canAnimate: Bool {
        selectedPage == 0 && scenePhase == .active && !isLuminanceReduced && !reduceMotion
    }

    private var supportsSpriteMotions: Bool {
        companion.state?.preferences.character == .usagi && companion.state?.equippedItems.isEmpty == true
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
                    .accessibilityLabel("현재 캐릭터")
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
                Text("캐릭터 동기화 대기").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var activityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(companion.state?.preferences.name ?? String(localized: "나의 캐릭터"))
                    .font(.title3.weight(.semibold)).foregroundStyle(green)
                Text("오늘 기록")
                    .font(.headline)
                if let workout = companion.state?.activeWorkout {
                    HStack {
                        Label(workout.mode.name, systemImage: "figure.run")
                        Spacer(minLength: 4)
                        Text(workout.startedAt, style: .timer).monospacedDigit()
                    }
                    .font(.caption)
                    .accessibilityIdentifier("watch.workout")
                    Text(companion.isReachable ? "iPhone에서 완료" : "저장된 운동 상태 · iPhone에서 확인")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let state = companion.state, state.profile != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let isToday = state.daily.day == UsagiState.dayKey(for: context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isToday ? LocalizedStringKey("걸음 수") : LocalizedStringKey("지난 기록 · iPhone에서 동기화하세요"))
                                .font(.caption2)
                                .foregroundStyle(isToday ? green : .orange)
                            Text("\(state.daily.steps.formatted()) / \(state.daily.goalSteps.formatted())걸음")
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .minimumScaleFactor(0.75)
                            ProgressView(value: min(1, Double(state.daily.steps) / Double(state.daily.goalSteps)))
                                .tint(green)
                            Label("\(state.daily.waterML) mL", systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                            Label("\(state.points) P", systemImage: "sparkles")
                                .font(.caption)
                            Label("운동 \(companion.workoutMinutesToday)분", systemImage: "figure.run")
                                .font(.caption)
                            if let updatedAt = companion.updatedAt {
                                Text("마지막 동기화 \(updatedAt, style: .relative) 전")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("iPhone에서 키와 몸무게를 등록하세요.")
                        .font(.caption)
                }
                Label(companion.isReachable ? "iPhone 연결됨" : "저장된 상태", systemImage: companion.isReachable ? "iphone" : "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let error = companion.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                    Button("다시 연결") { companion.activate() }
                }
                if let error = companion.complicationError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                    Button("워치페이스 새로고침") { companion.refreshConnection() }
                }
                Text("기록·의상은 iPhone에서 변경할 수 있어요.")
                    .font(.caption2)
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
                                Image(systemName: "checkmark").foregroundStyle(green)
                            }
                        }
                    }
                    .disabled(companion.state?.activeWorkout != nil)
                    .accessibilityAddTraits(motion == choice ? .isSelected : [])
                }
            }
            Text("모션을 바꿔도 운동·식사 기록은 바뀌지 않아요.")
                .font(.caption2)
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
