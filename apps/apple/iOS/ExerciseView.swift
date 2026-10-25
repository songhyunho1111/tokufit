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
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                             heading: 180, cameraHeading: 0,
                             motion: session == nil ? .idle : .exercising,
                             waterLevel: Double(store.state.daily.waterML) / 2_000,
                             accessibilityIdentifier: "exercise.indoor.character",
                             character: store.state.preferences.character, equippedItems: store.state.equippedItems)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 250)
                if let session {
                    Text(session.startedAt, style: .timer)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .accessibilityLabel("운동 경과 시간")
                        .accessibilityValue(Text(session.startedAt, style: .timer))
                        .accessibilityIdentifier("exercise.elapsed")
                }
                Label(store.sync.status, systemImage: "applewatch")
                    .font(.footnote)
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
                Task { await store.update { try $0.startWorkout(mode: .indoor) } }
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
                                Text(record.mode.name).font(.headline)
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                Text("\(record.durationMinutes)분").font(.headline).monospacedDigit()
                            }
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(Color.repickSecondaryText)
                            let metricLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(spacing: 12))
                            metricLayout {
                                if let repetitions = record.repetitions { Text("\(repetitions)회") }
                                if let distance = record.distanceMeters {
                                    Text("\((distance / 1_000).formatted(.number.precision(.fractionLength(0...2)))) km")
                                }
                                if let calories = record.calories { Text("\(calories) kcal") }
                            }.font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("exercise.record.\(record.id.uuidString)")
                        .listRowBackground(Color.repickSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("운동 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}
