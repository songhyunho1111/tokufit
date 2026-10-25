import REPickShared
import SwiftUI

struct WorkoutCompletionView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WorkoutSession
    let endedAt: Date
    @State private var minutes: String
    @State private var repetitions = ""
    @State private var distanceKM = ""
    @State private var calories = ""
    @State private var activity: WorkoutActivity?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmsDiscard = false
    @FocusState private var focusedField: String?

    init(session: WorkoutSession, endedAt: Date) {
        self.session = session
        self.endedAt = endedAt
        let elapsed = max(1, Int(ceil(max(0, endedAt.timeIntervalSince(session.startedAt)) / 60)))
        _minutes = State(initialValue: String(elapsed))
        _activity = State(initialValue: session.activity)
    }

    private var estimatedCalories: Int? {
        WorkoutCompletionInput.estimateCalories(minutes: minutes, activity: activity, weightKG: store.state.profile?.weightKG)
    }

    private var hasManualCalories: Bool {
        !calories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("운동", value: session.mode.name)
                    Picker("운동 종류", selection: $activity) {
                        if session.activity == nil {
                            Text("선택 안 함").tag(WorkoutActivity?.none)
                        }
                        ForEach(WorkoutActivity.allCases) { activity in
                            Text(activity.name).tag(Optional(activity))
                        }
                    }
                    .accessibilityIdentifier("exercise.activity")
                    LabeledContent("시작", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    amountField("운동 시간", text: $minutes, unit: "분", id: "exercise.minutes")
                } footer: {
                    Text("경과 시간을 분 단위로 올림했습니다. 실제 운동한 시간으로 수정할 수 있어요.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    amountField("횟수", text: $repetitions, unit: "회", id: "exercise.repetitions")
                    amountField("거리", text: $distanceKM, unit: "km", id: "exercise.distance", decimal: true)
                } header: { Text("운동량 · 선택") } footer: {
                    Text("직접 확인한 값만 입력하세요. 횟수와 거리는 자동 측정되지 않습니다.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    if hasManualCalories {
                        Label("직접 입력한 칼로리를 저장해요", systemImage: "pencil")
                            .accessibilityIdentifier("exercise.calorieSource.manual")
                    } else if let estimatedCalories {
                        LabeledContent("소모 칼로리 · 추정", value: "약 \(estimatedCalories) kcal")
                            .accessibilityIdentifier("exercise.estimatedCalories")
                    } else {
                        Text("추정값 없음 · 칼로리 없이 기록해요")
                            .foregroundStyle(Color.repickSecondaryText)
                            .accessibilityIdentifier("exercise.estimatedCalories.unavailable")
                    }
                    amountField("칼로리 직접 입력", text: $calories, unit: "kcal", id: "exercise.calories")
                    if hasManualCalories {
                        Button(estimatedCalories == nil ? "직접 입력 지우기" : "추정치 사용") { calories = "" }
                            .accessibilityIdentifier("exercise.useEstimate")
                    }
                } header: { Text("소모 칼로리") } footer: {
                    Text("운동 종류·시간·체중을 바탕으로 안정 시 소모량을 뺀 활동 칼로리를 추정해요. 측정값이 아니며 실제 강도에 따라 달라요. 직접 입력하면 그 값을 우선 저장하고, 기타 운동은 추정하지 않아요.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    Button("기록하지 않고 종료", role: .destructive) { confirmsDiscard = true }
                        .accessibilityIdentifier("exercise.discard")
                }
                .listRowBackground(Color.repickSurface)
            }
            .font(AppFont.font(.body))
            .disabled(isSaving || store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.pagePadding)
                        .background(Color.repickSurface)
                        .accessibilityIdentifier("exercise.validation")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("운동 완료")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "저장 중…" : "저장") { Task { await save() } }
                        .font(AppFont.font(.body, weight: .semibold))
                        .disabled(isSaving || store.isSaving)
                        .accessibilityLabel("운동 기록 저장")
                        .accessibilityIdentifier("exercise.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedField = nil }
                        .accessibilityIdentifier("exercise.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("계속 운동") { dismiss() }.disabled(isSaving)
                        .accessibilityIdentifier("exercise.resume")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .confirmationDialog("이번 운동을 기록하지 않고 종료할까요?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("기록하지 않고 종료", role: .destructive) {
                    Task {
                        if await store.update({ state in
                            guard state.activeWorkout?.id == session.id else { return }
                            state.cancelWorkout()
                        }) { dismiss() }
                    }
                }
                Button("취소", role: .cancel) { }
            }
        }
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>, unit: String, id: String, decimal: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title)
            HStack(spacing: 8) {
                TextField("", text: text)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .focused($focusedField, equals: id)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .accessibilityLabel(title).accessibilityIdentifier(id)
                Text(unit).foregroundStyle(Color.repickSecondaryText)
            }
        }
        .frame(minHeight: Design.controlHeight)
    }

    private func save() async {
        guard !isSaving else { return }
        do {
            let input = try WorkoutCompletionInput(minutes: minutes, repetitions: repetitions,
                                                   distanceKM: distanceKM, calories: calories)
            let savedActivity = activity
            isSaving = true
            defer { isSaving = false }
            if await store.update({ state in
                try state.finishWorkout(durationMinutes: input.minutes, repetitions: input.repetitions,
                                        distanceMeters: input.distanceMeters, calories: input.calories,
                                        now: endedAt, sessionID: session.id, activity: savedActivity)
            }) {
                dismiss()
            } else {
                errorMessage = store.errorMessage ?? String(localized: "기록을 저장하지 못했어요. 다시 시도해 주세요.")
            }
        } catch {
            errorMessage = String(localized: "시간은 1~1,440분, 횟수는 0~100,000회, 거리는 0~200km, 칼로리는 0~10,000kcal로 입력하세요.")
        }
    }
}

struct WorkoutCompletionInput {
    let minutes: Int
    let repetitions: Int?
    let distanceMeters: Double?
    let calories: Int?

    init(minutes: String, repetitions: String, distanceKM: String, calories: String, locale: Locale = .current) throws {
        guard let minutes = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)), (1...1_440).contains(minutes) else {
            throw InputError.invalid
        }
        self.minutes = minutes
        self.repetitions = try Self.optionalInteger(repetitions, range: 0...100_000)
        self.calories = try Self.optionalInteger(calories, range: 0...10_000)
        let distance = distanceKM.trimmingCharacters(in: .whitespacesAndNewlines)
        if distance.isEmpty { distanceMeters = nil }
        else {
            let normalized = distance.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
            guard let kilometers = Double(normalized), kilometers.isFinite, (0...200).contains(kilometers) else { throw InputError.invalid }
            distanceMeters = kilometers * 1_000
        }
    }

    static func estimateCalories(minutes: String, activity: WorkoutActivity?, weightKG: Double?) -> Int? {
        guard let activity, let weightKG,
              let minutes = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return ExerciseEnergy.estimateCalories(activity: activity, minutes: minutes, weightKG: weightKG)
    }

    private static func optionalInteger(_ text: String, range: ClosedRange<Int>) throws -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = Int(text), range.contains(value) else { throw InputError.invalid }
        return value
    }

    private enum InputError: Error { case invalid }
}
