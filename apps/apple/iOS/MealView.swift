import SwiftUI
import REPickShared

struct MealView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var estimator = CalorieEstimator()
    @State private var food = ""
    @State private var calories = ""
    @State private var showsNutrients = false
    @State private var carbohydrates = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var mealKind = MealKind.breakfast
    @State private var validationMessage: String?
    @State private var estimateTask: Task<Void, Never>?
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("식사 종류") {
                    Picker("식사 종류", selection: $mealKind) {
                        ForEach(MealKind.allCases) { kind in Text(kind.name).tag(kind) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("meal.kind")
                }
                .listRowBackground(Color.repickSurface)

                Section {
                    TextField("예: 엽떡 1인분, 삶은 달걀 2개", text: $food, axis: .vertical)
                        .focused($focusedField, equals: "food")
                        .lineLimit(1...4)
                        .frame(minHeight: Design.controlHeight)
                        .accessibilityLabel("음식과 양")
                        .accessibilityIdentifier("meal.name")
                    calorieField
                } header: {
                    Text("먹은 음식")
                }
                .listRowBackground(Color.repickSurface)

                Section {
                    DisclosureGroup(isExpanded: $showsNutrients) {
                        nutrientField("탄수화물", text: $carbohydrates, id: "meal.carbs")
                        nutrientField("단백질", text: $protein, id: "meal.protein")
                        nutrientField("지방", text: $fat, id: "meal.fat")
                    } label: {
                        Text("영양소 · 선택").accessibilityIdentifier("meal.nutrients")
                    }
                } footer: {
                    if showsNutrients { Text("영양정보를 보고 세 항목을 입력하세요. 모르면 모두 비워 두어도 됩니다.") }
                }
                .listRowBackground(Color.repickSurface)

                Section {
                    Button {
                        estimateTask?.cancel()
                        estimateTask = Task {
                            await estimator.estimate(food: food)
                            if !Task.isCancelled, let result = estimator.result { calories = String(result.calories) }
                        }
                    } label: {
                        HStack {
                            Text(estimator.isLoading ? "추정 중…" : "AI로 칼로리 추정")
                            Spacer()
                            if estimator.isLoading { ProgressView() }
                        }
                        .frame(minHeight: Design.controlHeight)
                    }
                    .disabled(!estimator.canEstimate || food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || estimator.isLoading)
                    .accessibilityIdentifier("meal.estimate")
                } footer: {
                    estimateInformation
                }
                .listRowBackground(Color.repickSurface)

                if !store.state.daily.meals.isEmpty {
                    Section("오늘 기록") {
                        ForEach(store.state.daily.meals.reversed()) { meal in
                            LabeledContent {
                                Text("\(meal.calories) kcal").monospacedDigit()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name)
                                    if let kind = meal.kind {
                                        Text(kind.name).font(AppFont.font(.caption, weight: .semibold))
                                            .accessibilityIdentifier("meal.recordKind.\(meal.id)")
                                    }
                                    if meal.source == .onDeviceAI {
                                        Text("칼로리 AI 추정").font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                                    } else if meal.source == .photoAI {
                                        Text("사진 AI 추정 · 직접 확인").font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                                    } else {
                                        Text("직접 입력").font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                                    }
                                    if let nutrients = meal.nutrients {
                                        Text("탄수화물 \(nutrients.carbohydratesG.formatted())g · 단백질 \(nutrients.proteinG.formatted())g · 지방 \(nutrients.fatG.formatted())g")
                                            .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.repickSurface)
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if let validationMessage {
                    Text(validationMessage)
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.pagePadding)
                        .background(Color.repickSurface)
                        .accessibilityIdentifier("meal.validation")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("음식 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedField = nil }
                        .accessibilityIdentifier("meal.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가", action: save)
                        .font(AppFont.font(.body, weight: .semibold))
                        .disabled(store.isSaving || estimator.isLoading)
                        .accessibilityLabel("음식 기록 추가")
                        .accessibilityIdentifier("save.meal")
                }
            }
            .onChange(of: food) { _, _ in estimator.reset(); estimateTask?.cancel() }
            .onDisappear { estimateTask?.cancel(); estimator.reset() }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    private var calorieField: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("칼로리")
            HStack(spacing: 8) {
                TextField("직접 입력", text: $calories)
                    .focused($focusedField, equals: "calories")
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .accessibilityLabel("칼로리, 킬로칼로리")
                    .accessibilityIdentifier("meal.calories")
                Text("kcal").foregroundStyle(Color.repickSecondaryText)
            }
        }
        .frame(minHeight: Design.controlHeight)
    }

    @ViewBuilder
    private var estimateInformation: some View {
        if let result = estimator.result {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 추정 결과: \(result.calories) kcal").font(AppFont.font(.body, weight: .medium))
                Text(result.explanation)
                Text("영양정보를 확인하고 수정할 수 있습니다.")
            }
        } else if !estimator.isLoading {
            Text(estimator.status.isEmpty ? estimator.availabilityText : estimator.status)
        }
    }

    private func nutrientField(_ title: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title)
            HStack(spacing: 8) {
                TextField("기록 안 함", text: text)
                    .focused($focusedField, equals: id)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(id)
                Text("g").foregroundStyle(Color.repickSecondaryText)
            }
        }
        .frame(minHeight: Design.controlHeight)
    }

    private func save() {
        guard let amount = Int(calories.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            validationMessage = String(localized: "칼로리를 정수로 입력해 주세요.")
            return
        }
        let name = food.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: MealSource = estimator.result?.calories == amount ? .onDeviceAI : .manual
        do {
            let nutrients = try MealNutrientInput.parse(carbohydrates: carbohydrates, protein: protein, fat: fat)
            _ = try MealEntry(name: name, calories: amount, source: source, recordedAt: Date(), nutrients: nutrients, kind: mealKind)
            let kind = mealKind
            Task {
                if await store.update({ try $0.addMeal(name: name, calories: amount, source: source, nutrients: nutrients, kind: kind) }) {
                    store.motion = .eating
                    dismiss()
                } else { validationMessage = store.errorMessage }
            }
        } catch { validationMessage = error.localizedDescription }
    }
}

enum MealNutrientInput {
    static func parse(carbohydrates: String, protein: String, fat: String, locale: Locale = .current) throws -> MealNutrients? {
        let values = [carbohydrates, protein, fat].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if values.allSatisfy(\.isEmpty) { return nil }
        guard values.allSatisfy({ !$0.isEmpty }) else { throw InputError.incomplete }
        let grams = try values.map { value in
            guard let grams = Double(value.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")),
                  grams.isFinite, (0...2_000).contains(grams) else { throw InputError.invalid }
            return grams
        }
        return try MealNutrients(carbohydratesG: grams[0], proteinG: grams[1], fatG: grams[2])
    }

    private enum InputError: LocalizedError {
        case incomplete, invalid
        var errorDescription: String? {
            switch self {
            case .incomplete: String(localized: "영양소는 세 항목을 모두 입력하거나 모두 비워 주세요.")
            case .invalid: String(localized: "각 영양소를 0~2,000g 사이의 숫자로 입력해 주세요.")
            }
        }
    }
}
