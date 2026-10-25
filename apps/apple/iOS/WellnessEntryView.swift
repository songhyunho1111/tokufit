import REPickShared
import SwiftUI

struct WellnessEntryView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var recordsSleep = false
    @State private var sleepHours = 0
    @State private var sleepMinutes = 0
    @State private var condition: Int?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var hasLoaded = false

    private var day: String { UsagiState.dayKey(for: date) }
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let earliest = Calendar.current.date(byAdding: .day, value: -365, to: today) ?? today
        return earliest...Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("기록 날짜", selection: $date, in: dateRange, displayedComponents: .date)
                        .accessibilityIdentifier("wellness.date")
                }
                .listRowBackground(Color.repickSurface)

                Section {
                    Toggle("수면 기록", isOn: $recordsSleep)
                        .accessibilityIdentifier("wellness.sleepEnabled")
                    if recordsSleep {
                        Stepper("\(sleepHours)시간", value: $sleepHours, in: 0...24)
                            .accessibilityLabel("수면 시간")
                            .accessibilityValue("\(sleepHours)시간")
                            .accessibilityIdentifier("wellness.sleepHours")
                        Stepper("\(sleepMinutes)분", value: $sleepMinutes, in: 0...59)
                            .accessibilityLabel("수면 분")
                            .accessibilityValue("\(sleepMinutes)분")
                            .accessibilityIdentifier("wellness.sleepMinutes")
                            .disabled(sleepHours == 24)
                    }
                } header: { Text("수면") } footer: {
                    Text("해당 날짜에 일어나기 전까지 잔 시간을 입력하세요. 0시간은 잠을 자지 않은 기록입니다.")
                }
                .listRowBackground(Color.repickSurface)

                Section {
                    Picker("컨디션", selection: $condition) {
                        Text("기록 안 함").tag(Int?.none)
                        ForEach(1...5, id: \.self) { value in
                            Text(conditionName(value)).tag(Optional(value))
                        }
                    }
                    .accessibilityIdentifier("wellness.condition")
                } header: { Text("컨디션") } footer: {
                    Text("내가 느낀 컨디션을 기록합니다. 입력하지 않은 항목은 리포트에서 기록 없음으로 표시됩니다.")
                }
                .listRowBackground(Color.repickSurface)
            }
            .disabled(isSaving || store.isSaving)
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote).foregroundStyle(Color.repickDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.pagePadding)
                        .background(Color.repickSurface)
                        .accessibilityIdentifier("wellness.validation")
                }
            }
            .navigationTitle("수면·컨디션 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "저장 중…" : "저장") { Task { await save() } }
                        .disabled(isSaving || store.isSaving || (!recordsSleep && condition == nil))
                        .accessibilityIdentifier("wellness.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                guard !hasLoaded else { return }
                loadSelectedDay()
                hasLoaded = true
            }
            .onChange(of: date) { _, _ in loadSelectedDay() }
            .onChange(of: sleepHours) { _, hours in
                if hours == 24 { sleepMinutes = 0 }
            }
        }
    }

    private func conditionName(_ value: Int) -> LocalizedStringKey {
        switch value {
        case 1: "1 · 매우 나쁨"
        case 2: "2 · 나쁨"
        case 3: "3 · 보통"
        case 4: "4 · 좋음"
        default: "5 · 매우 좋음"
        }
    }

    private func loadSelectedDay() {
        let entry = store.state.wellnessHistory.first { $0.day == day }
        recordsSleep = entry?.sleepMinutes != nil
        sleepHours = (entry?.sleepMinutes ?? 0) / 60
        sleepMinutes = (entry?.sleepMinutes ?? 0) % 60
        condition = entry?.condition
        errorMessage = nil
    }

    private func save() async {
        guard !isSaving else { return }
        let savedDay = day
        let savedSleep = recordsSleep ? sleepHours * 60 + sleepMinutes : nil
        let savedCondition = condition
        isSaving = true
        defer { isSaving = false }
        if await store.update({ state in
            try state.recordWellness(day: savedDay, sleepMinutes: savedSleep, condition: savedCondition)
        }) {
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
        }
    }
}
