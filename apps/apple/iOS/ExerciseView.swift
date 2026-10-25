import REPickShared
import SwiftUI

struct ExerciseView: View {
    @Environment(UsagiStore.self) private var store
    let steps: StepTracker
    @State private var mode: WorkoutMode = .outdoor
    @State private var showsHistory = false

    private var displayedMode: WorkoutMode { store.state.activeWorkout?.mode ?? mode }

    var body: some View {
        VStack(spacing: 0) {
            if store.state.activeWorkout == nil {
                HStack(spacing: 12) {
                    Picker("운동 장소", selection: $mode) {
                        Text("야외").tag(WorkoutMode.outdoor)
                        Text("실내").tag(WorkoutMode.indoor)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exercise.mode")
                    Button { showsHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("운동 기록")
                    .accessibilityIdentifier("exercise.history")
                }
                .padding(.horizontal, Design.pagePadding)
                .padding(.vertical, 6)
            }
            if displayedMode == .outdoor {
                WalkView(steps: steps)
            } else {
                IndoorExerciseView()
            }
        }
        .font(AppFont.font(.body))
        .background(Color.repickCream)
        .onChange(of: store.state.activeWorkout?.mode, initial: true) { _, activeMode in
            if let activeMode { mode = activeMode }
        }
        .sheet(isPresented: $showsHistory) { WorkoutHistoryView() }
    }
}

private struct IndoorExerciseView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var completion: Completion?
    @State private var activity: WorkoutActivity = .other

    private struct Completion: Identifiable {
        let session: WorkoutSession
        let endedAt: Date
        var id: UUID { session.id }
    }

    private var session: WorkoutSession? { store.state.activeWorkout }

    var body: some View {
        ScrollView {
            VStack(spacing: Design.sectionSpacing) {
                Text("실내 운동")
                    .font(AppFont.font(.headline))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if session == nil {
                    Picker("운동 종류", selection: $activity) {
                        ForEach(WorkoutActivity.allCases) { activity in
                            Text(activity.name).tag(activity)
                        }
                    }
                    .accessibilityIdentifier("exercise.indoor.activity")
                    .frame(minHeight: Design.controlHeight)
                    Text("종류를 선택하면 운동 시간과 체중으로 소모 칼로리를 추정해요. 기타는 추정하지 않아요.")
                        .font(AppFont.font(.footnote))
                        .foregroundStyle(Color.repickSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                             heading: 180, cameraHeading: 0,
                             motion: session == nil ? .idle : .exercising,
                             waterLevel: Double(store.state.daily.waterML) / 2_000,
                             accessibilityIdentifier: "exercise.indoor.character",
                             character: store.state.preferences.character, equippedItems: store.state.equippedItems,
                             muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                             nutritionMood: store.state.nutritionMood, costume: store.state.currentCostume)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 250)
                if let session {
                    Text(session.startedAt, style: .timer)
                        .font(AppFont.font(.largeTitle, weight: .semibold)).monospacedDigit()
                        .accessibilityLabel("운동 경과 시간")
                        .accessibilityValue(Text(session.startedAt, style: .timer))
                        .accessibilityIdentifier("exercise.elapsed")
                    WorkoutEnergySummary(session: session, weightKG: store.state.profile?.weightKG)
                }
                Label(store.sync.status, systemImage: "applewatch")
                    .font(AppFont.font(.footnote))
                    .foregroundStyle(Color.repickSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Design.pagePadding)
            .frame(maxWidth: Design.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.repickInk)
        .background(Color.repickCream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            workoutAction
                .padding(.horizontal, Design.pagePadding)
                .padding(.vertical, 12)
                .frame(maxWidth: Design.contentWidth)
                .frame(maxWidth: .infinity)
                .background(Color.repickCream)
        }
        .toolbar(session == nil ? .visible : .hidden, for: .tabBar)
        .sheet(item: $completion) { completion in
            WorkoutCompletionView(session: completion.session, endedAt: completion.endedAt)
        }
    }

    @ViewBuilder
    private var workoutAction: some View {
        if let session {
            Button("운동 완료") {
                completion = Completion(session: session, endedAt: Date())
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("exercise.complete")
        } else {
            Button("실내 운동 시작") {
                Task { await store.update { try $0.startWorkout(mode: .indoor, activity: activity) } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isSaving || store.state.profile == nil)
            .accessibilityIdentifier("exercise.indoor.start")
        }
    }
}

private struct WorkoutHistoryView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            List {
                if store.state.workouts.isEmpty {
                    ContentUnavailableView("아직 운동 기록이 없어요", systemImage: "figure.run",
                                           description: Text("운동을 완료하고 운동량을 저장해 주세요."))
                } else {
                    ForEach(store.state.workouts.reversed()) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            let headingLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout())
                            headingLayout {
                                Text(record.activity?.name ?? record.mode.name).font(AppFont.font(.headline))
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                Text("\(record.durationMinutes)분").font(AppFont.font(.headline)).monospacedDigit()
                            }
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                            let metricLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(spacing: 12))
                            metricLayout {
                                if let repetitions = record.repetitions { Text("\(repetitions)회") }
                                if let distance = record.distanceMeters {
                                    Text("\((distance / 1_000).formatted(.number.precision(.fractionLength(0...2)))) km")
                                }
                                if let calories = record.calories {
                                    if record.calorieSource == .estimated { Text("약 \(calories) kcal · 추정") }
                                    else { Text("\(calories) kcal") }
                                }
                            }.font(AppFont.font(.subheadline))
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("exercise.record.\(record.id.uuidString)")
                        .listRowBackground(Color.repickSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .font(AppFont.font(.body))
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("운동 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

struct WorkoutEnergySummary: View {
    let session: WorkoutSession
    let weightKG: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("운동 종류", value: session.activity?.name ?? String(localized: "선택 안 함"))
            TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(session.startedAt) / 60))
                LabeledContent("소모 칼로리 · 추정") {
                    if let activity = session.activity, let weightKG,
                       let estimate = ExerciseEnergy.estimateCalories(activity: activity, minutes: elapsed, weightKG: weightKG) {
                        Text("약 \(estimate) kcal").monospacedDigit()
                    }
                    else { Text("추정값 없음").foregroundStyle(Color.repickSecondaryText) }
                }
                .accessibilityIdentifier("exercise.liveEstimate")
            }
            Text("시간·종류·체중으로 계산한 추정치예요. 완료할 때 실제 운동 시간과 칼로리를 수정할 수 있어요.")
                .font(AppFont.font(.footnote))
                .foregroundStyle(Color.repickSecondaryText)
        }
        .font(AppFont.font(.body))
    }
}
