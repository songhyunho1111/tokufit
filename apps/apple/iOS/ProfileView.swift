import SwiftUI
import REPickShared

struct ProfileView: View {
    @Environment(UsagiStore.self) private var store
    @State private var editing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("캐릭터") {
                    LabeledContent("이름", value: store.state.preferences.name)
                        .accessibilityIdentifier("settings.name")
                    LabeledContent("캐릭터", value: store.state.preferences.character.name)
                        .accessibilityIdentifier("settings.character")
                    Button("프로필과 목표 편집") { editing = true }
                        .accessibilityIdentifier("profile.edit")
                }
                .listRowBackground(Color.repickSurface)
                Section("건강 리포트") {
                    NavigationLink {
                        HealthReportsView()
                    } label: {
                        Label("주간·월간 리포트", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityIdentifier("settings.healthReports")
                }
                .listRowBackground(Color.repickSurface)
                Section("신체 정보") {
                    if let profile = store.state.profile {
                        LabeledContent("키", value: "\(profile.heightCM.formatted()) cm")
                        LabeledContent("몸무게", value: "\(profile.weightKG.formatted()) kg")
                        LabeledContent("목표 몸무게", value: "\(profile.targetWeightKG.formatted()) kg")
                        LabeledContent("BMI", value: profile.bmi.formatted(.number.precision(.fractionLength(1))))
                        LabeledContent("성별", value: (profile.gender ?? .notSpecified).name)
                    }
                }
                .listRowBackground(Color.repickSurface)
                if store.state.profile != nil {
                    Section("걸음 목표") {
                        if !store.state.preferences.goalTitle.isEmpty {
                            Text(store.state.preferences.goalTitle)
                        }
                        LabeledContent("오늘", value: "\(store.state.daily.goalSteps.formatted())보")
                        if let next = store.state.nextGoalSteps {
                            LabeledContent("내일부터", value: "\(next.formatted())보")
                        }
                    }
                    .listRowBackground(Color.repickSurface)
                }
                Section("섭취 칼로리 목표") {
                    if let minimum = store.state.preferences.calorieMinimum, let maximum = store.state.preferences.calorieMaximum {
                        LabeledContent("하루 범위", value: "\(minimum.formatted())–\(maximum.formatted()) kcal")
                            .accessibilityIdentifier("settings.calorieRange")
                    } else {
                        Text("설정 안 함").foregroundStyle(Color.repickSecondaryText)
                    }
                }
                .listRowBackground(Color.repickSurface)
                Section("홈에서 볼 기록") {
                    Text(store.state.preferences.homeMetrics.map(\.name).joined(separator: " · "))
                        .accessibilityIdentifier("settings.homeMetrics")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    LabeledContent("캐릭터 목소리", value: "꺼짐")
                } footer: { Text("실제 음성이 준비되면 사용할 수 있습니다.") }
                .listRowBackground(Color.repickSurface)
                Section {
                    Text(store.sync.status).font(.subheadline)
                    Button("다시 동기화") { store.sync.publish(store.state) }
                        .disabled(store.isSaving)
                } header: { Text("Apple Watch") } footer: {
                    Text("Watch에는 마지막으로 받은 상태가 표시됩니다.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    Text(store.widget.status).font(.subheadline)
                    Button("위젯 새로고침") { store.widget.publish(store.state, forceReload: true) }
                        .disabled(store.isSaving)
                } header: { Text("홈 화면 위젯") } footer: {
                    Text("홈 화면을 길게 눌러 RE:PICK 위젯을 추가하세요. 마지막 저장 상태가 표시됩니다.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    LabeledContent("기본 기록", value: "이 iPhone")
                } header: { Text("데이터") } footer: {
                    Text("식사·수면·컨디션은 최근 1년, 운동은 최근 200건을 보관합니다. 리포트를 만들 때 선택한 기간의 기록만 전송됩니다.")
                }
                .listRowBackground(Color.repickSurface)
                #if DEBUG
                Section {
                    NavigationLink("개발 설정") { DeveloperSettingsView() }
                        .accessibilityIdentifier("profile.developerSettings")
                }
                .listRowBackground(Color.repickSurface)
                #endif
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .sheet(isPresented: $editing) { ProfileEditor() }
        }
    }
}

struct ProfileEditor: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var height = ""
    @State private var weight = ""
    @State private var target = ""
    @State private var goal = 6_000
    @State private var gender: ProfileGender = .notSpecified
    @State private var preferences = CompanionPreferences()
    @State private var calorieEnabled = false
    @State private var calorieMinimum = ""
    @State private var calorieMaximum = ""
    @State private var hasLoaded = false
    @State private var validationMessage: String?
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("캐릭터") {
                    TextField("이름", text: $preferences.name)
                        .focused($focusedField, equals: "name")
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profile.name")
                    Picker("캐릭터", selection: Binding(
                        get: { preferences.character },
                        set: { character in
                            if preferences.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preferences.name == preferences.character.name {
                                preferences.name = character.name
                            }
                            preferences.character = character
                        }
                    )) {
                        ForEach(CharacterKind.allCases) { character in
                            Text(character.name).tag(character)
                        }
                    }
                    .accessibilityIdentifier("profile.character")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    measurement("키 (cm)", text: $height, id: "profile.height")
                    measurement("몸무게 (kg)", text: $weight, id: "profile.weight")
                    measurement("목표 몸무게 (kg)", text: $target, id: "profile.target")
                    Picker("성별", selection: $gender) {
                        ForEach(ProfileGender.allCases) { value in Text(value.name).tag(value) }
                    }
                    .accessibilityIdentifier("profile.gender")
                } header: { Text("신체 정보") } footer: {
                    Text("음식 기록은 캐릭터에만 반영됩니다. 몸무게는 직접 수정할 때만 바뀝니다.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    TextField("예: 매일 저녁 30분 걷기", text: $preferences.goalTitle)
                        .focused($focusedField, equals: "goal")
                        .accessibilityLabel("홈에 표시할 목표")
                        .accessibilityIdentifier("profile.goalTitle")
                    Stepper("하루 \(goal.formatted())보", value: $goal, in: 2_000...10_000, step: 1_000)
                        .accessibilityIdentifier("profile.goal")
                    LabeledContent("달성 보상", value: "\(goal / 1_000 * 50)P")
                    LabeledContent("하루 최대 뽑기", value: "\(goal / 2_000)회")
                } header: { Text("걸음 목표") } footer: {
                    if store.state.profile != nil { Text("변경한 목표는 내일부터 적용됩니다.") }
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    Toggle("칼로리 범위 설정", isOn: $calorieEnabled)
                        .accessibilityIdentifier("profile.calorieEnabled")
                    if calorieEnabled {
                        calorieField("최소 (kcal)", text: $calorieMinimum, id: "profile.calorieMinimum")
                        calorieField("최대 (kcal)", text: $calorieMaximum, id: "profile.calorieMaximum")
                    }
                } header: { Text("섭취 칼로리 목표") } footer: {
                    Text("하루 섭취 목표를 직접 입력하세요.")
                }
                .listRowBackground(Color.repickSurface)
                Section {
                    ForEach(HomeMetric.allCases) { metric in
                        Toggle(metric.name, isOn: Binding(
                            get: { preferences.homeMetrics.contains(metric) },
                            set: { included in
                                if included {
                                    if !preferences.homeMetrics.contains(metric) { preferences.homeMetrics.append(metric) }
                                } else {
                                    preferences.homeMetrics.removeAll { $0 == metric }
                                }
                            }
                        ))
                        .accessibilityIdentifier("profile.metric.\(metric.rawValue)")
                    }
                } header: { Text("홈에서 볼 기록") } footer: {
                    Text("캐릭터 아래에 표시할 기록을 한 개 이상 선택하세요.")
                }
                .listRowBackground(Color.repickSurface)
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.repickDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.pagePadding)
                        .background(Color.repickSurface)
                        .accessibilityIdentifier("profile.validation")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle(store.state.profile == nil ? "프로필 등록" : "프로필 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedField = nil }
                        .accessibilityIdentifier("profile.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSaving ? "저장 중" : "저장", action: save)
                        .fontWeight(.semibold)
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("save.profile")
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                if let profile = store.state.profile {
                    height = profile.heightCM.formatted(.number.grouping(.never))
                    weight = profile.weightKG.formatted(.number.grouping(.never))
                    target = profile.targetWeightKG.formatted(.number.grouping(.never))
                    gender = profile.gender ?? .notSpecified
                }
                goal = store.state.nextGoalSteps ?? store.state.daily.goalSteps
                preferences = store.state.preferences
                calorieEnabled = preferences.calorieMinimum != nil
                calorieMinimum = preferences.calorieMinimum.map(String.init) ?? ""
                calorieMaximum = preferences.calorieMaximum.map(String.init) ?? ""
                hasLoaded = true
            }
        }
    }

    @ViewBuilder
    private func measurement(_ label: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                measurementField(label, text: text, id: id)
            }
        } else {
            HStack(spacing: 16) {
                Text(label)
                measurementField(label, text: text, id: id)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func measurementField(_ label: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        TextField("입력", text: text)
            .focused($focusedField, equals: id)
            .keyboardType(.decimalPad)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }

    private func calorieField(_ label: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        return layout {
            Text(label)
            TextField("입력", text: text)
                .focused($focusedField, equals: id)
                .keyboardType(.numberPad)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        guard let height = Double(height.replacingOccurrences(of: ",", with: ".")),
              let weight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let target = Double(target.replacingOccurrences(of: ",", with: ".")) else {
            validationMessage = String(localized: "키와 몸무게를 숫자로 입력해 주세요.")
            return
        }
        do {
            _ = try UserProfile(heightCM: height, weightKG: weight, targetWeightKG: target)
            var savedPreferences = preferences
            savedPreferences.name = savedPreferences.name.trimmingCharacters(in: .whitespacesAndNewlines)
            savedPreferences.goalTitle = savedPreferences.goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            savedPreferences.voiceEnabled = false
            if calorieEnabled {
                guard let minimum = Int(calorieMinimum.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let maximum = Int(calorieMaximum.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    validationMessage = String(localized: "최소·최대 칼로리를 정수로 입력해 주세요.")
                    return
                }
                savedPreferences.calorieMinimum = minimum
                savedPreferences.calorieMaximum = maximum
            } else {
                savedPreferences.calorieMinimum = nil
                savedPreferences.calorieMaximum = nil
            }
            try savedPreferences.validate()
            validationMessage = nil
            let savedGoal = goal
            let savedGender = gender
            Task {
                if await store.update({ state in
                    try state.setProfile(heightCM: height, weightKG: weight, targetWeightKG: target, goalSteps: savedGoal, gender: savedGender)
                    try state.setPreferences(savedPreferences)
                }) { dismiss() }
                else { validationMessage = store.errorMessage }
            }
        } catch { validationMessage = error.localizedDescription }
    }
}

#if DEBUG
private struct DeveloperSettingsView: View {
    @State private var api = APIConnection()
    @AppStorage("apiBaseURL") private var apiBaseURL = Bundle.main.object(forInfoDictionaryKey: "REPickAPIBaseURL") as? String ?? ""
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("https://api.example.com", text: $apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("API 서버 주소")
                Button(api.isLoading ? "확인 중…" : "연결 확인") {
                    checkTask = Task { await api.check(baseURL: apiBaseURL) }
                }
                .disabled(api.isLoading || apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("API 서버") } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !api.isLoading { Text(api.status) }
                    Text("연결 상태만 확인하며 프로필과 기록은 전송하지 않습니다.")
                }
            }
            .listRowBackground(Color.repickSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Color.repickCream)
        .foregroundStyle(Color.repickInk)
        .navigationTitle("개발 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { checkTask?.cancel() }
    }
}
#endif
