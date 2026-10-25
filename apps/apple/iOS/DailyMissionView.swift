import REPickShared
import SwiftUI

struct DailyMissionView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: DailyMissionKind = .stairs
    @State private var showAttendance = false
    @State private var showMeal = false
    @State private var showProfile = false
    @State private var showStairs = false
    @State private var confirmFoodDay = false
    @State private var stairCount = ""
    @State private var stairDay = ""
    @State private var stairValidation: String?
    @State private var errorMessage: String?

    private var progress: Int { store.state.missionProgress(for: selected) }
    private var target: Int { store.state.missionTarget(for: selected) }
    private var complete: Bool { progress >= target }
    private var claimed: Bool { store.state.missionRewardClaimed(selected) }
    private var canConfirmFood: Bool {
        store.state.nutritionStatus == .within && store.state.missionProgress(for: .threeMeals) == 3
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        return value
    }
    private var today: Date {
        let parts = store.state.daily.day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }
    private var week: [Date] {
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    attendanceCard
                    missionSelector
                    VStack(spacing: -24) {
                        hero
                        progressPanel
                    }
                }
                .frame(maxWidth: Design.contentWidth)
                .padding(.horizontal, Design.pagePadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("오늘의 미션")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("mission.close")
                }
                PointsToolbar(points: store.state.points)
            }
            .fullScreenCover(isPresented: $showAttendance) { AttendanceView() }
            .sheet(isPresented: $showMeal) { MealView() }
            .sheet(isPresented: $showProfile) { ProfileEditor() }
            .sheet(isPresented: $showStairs) { stairEditor }
            .confirmationDialog("오늘의 식사를 모두 기록했나요?", isPresented: $confirmFoodDay, titleVisibility: .visible) {
                Button("오늘 식사 마무리") {
                    Task { await save { try $0.confirmFoodDay() } }
                }
                .accessibilityIdentifier("mission.confirmFoodDay")
            } message: {
                Text("아침·점심·저녁 기록과 현재 칼로리 범위를 확인하고 미션을 완료해요. 이후 추가 기록은 캐릭터 상태에 계속 반영돼요.")
            }
            .alert("미션을 저장하지 못했어요", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task { await store.refreshDay() }
        }
        .font(AppFont.font(.body))
    }

    private var attendanceCard: some View {
        Button { showAttendance = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(calendar.component(.month, from: today))월 출석 현황")
                        .font(AppFont.font(.title3, weight: .bold))
                    Image(systemName: "chevron.right").font(.caption)
                    Spacer()
                    Text(store.state.hasCheckedInToday ? "오늘 완료" : "출석하기")
                        .font(AppFont.font(.caption, weight: .medium))
                        .foregroundStyle(Color.repickGold)
                }
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { date in
                        let key = UsagiState.dayKey(for: date, calendar: calendar)
                        let checked = store.state.attendance.days.contains(key)
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.repickCream)
                                    .overlay { Circle().strokeBorder(key == store.state.daily.day ? Color.repickGold : Color.repickBorder, lineWidth: key == store.state.daily.day ? 2 : 1) }
                                if checked && key != store.state.daily.day {
                                    Image(systemName: "carrot.fill").foregroundStyle(Color.repickGold)
                                } else {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(AppFont.font(.caption, weight: .medium))
                                }
                            }
                            .frame(width: 34, height: 34)
                            Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR"))))
                                .font(AppFont.font(.caption2, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(date.formatted(.dateTime.month().day().weekday(.wide))), \(checked ? String(localized: "출석 완료") : String(localized: "출석 기록 없음"))"))
                    }
                }
            }
            .padding(18)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.repickBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mission.attendance")
    }

    private var missionSelector: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            ForEach(DailyMissionKind.allCases) { kind in
                Button { selected = kind } label: {
                    Text(kind.shortTitle)
                        .font(AppFont.font(.caption, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected == kind ? Color.repickActionFill : Color.repickSurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(selected == kind ? Color.repickGold : Color.repickBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == kind ? .isSelected : [])
                .accessibilityIdentifier("mission.\(kind.rawValue)")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(selected == .stairs ? "일일 운동 미션" : "일일 식사 미션", systemImage: selected.icon)
                .font(AppFont.font(.caption, weight: .bold))
                .foregroundStyle(Color.repickGold)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.repickRewardSurface, in: Capsule())
            Text(selected.title)
                .font(AppFont.font(.title, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if selected == .stairs {
                Image("DailyMissionStairs")
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
            } else {
                ZStack(alignment: .bottom) {
                    Ellipse().fill(Color.repickRewardSurface).frame(height: 52).padding(.horizontal, 25)
                    MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                                 heading: 180, motion: .idle,
                                 isAnimating: !showAttendance && !showMeal && !showProfile,
                                 accessibilityIdentifier: "mission.character", character: store.state.preferences.character,
                                 equippedItems: store.state.equippedItems, muscleLevel: store.state.muscleLevel,
                                 fieryEyes: store.state.attendanceNeedsAttention,
                                 nutritionMood: store.state.nutritionMood, costume: store.state.currentCostume)
                        .frame(width: 190, height: 205)
                        .offset(y: -25)
                }
                .frame(height: 210)
                .accessibilityHidden(true)
            }
        }
        .padding(18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.repickSurface, .repickCream], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(Color.repickBorder, lineWidth: 1) }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            let progressLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            progressLayout {
                Label {
                    Text("\(progress) / \(target)").monospacedDigit()
                        .font(AppFont.font(.title2, weight: .bold))
                        .accessibilityIdentifier("mission.progress")
                } icon: {
                    Image(systemName: selected.icon)
                        .frame(width: 44, height: 44)
                        .background(Color.repickCream, in: Circle())
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(0..<target, id: \.self) { index in
                        Circle().fill(index < progress ? Color.repickGold : Color.repickCream)
                            .overlay { Circle().strokeBorder(Color.repickBorder, lineWidth: 2) }
                            .frame(width: 16, height: 16)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(progressDetail)
                .font(AppFont.font(.footnote))
                .foregroundStyle(Color.repickSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if selected != .stairs { mealKinds }
            rewardCard
            if claimed {
                Label("오늘 보상 수령 완료", systemImage: "checkmark.circle.fill")
                    .font(AppFont.font(.body, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.repickRewardSurface, in: Capsule())
                    .accessibilityIdentifier("mission.claimed")
            } else {
                Button(action: performAction) {
                    Label(actionTitle, systemImage: complete ? "gift.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isSaving)
                .accessibilityIdentifier("mission.action")
            }
            Label(selected == .stairs ? "작은 움직임이 더 나은 오늘을 만들어요" : "빠짐없는 식사 기록으로 하루를 돌아봐요", systemImage: "leaf")
                .font(AppFont.font(.caption, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.repickCream, in: Capsule())
        }
        .padding(20)
        .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.repickBorder, lineWidth: 1) }
    }

    private var mealKinds: some View {
        HStack(spacing: 8) {
            ForEach([MealKind.breakfast, .lunch, .dinner]) { kind in
                let recorded = store.state.daily.meals.contains { $0.kind == kind }
                Label(kind.name, systemImage: recorded ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.font(.caption, weight: .medium))
                    .foregroundStyle(recorded ? Color.repickGold : Color.repickSecondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var rewardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let rewardLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
            rewardLayout {
                Image("GachaBall").resizable().scaledToFit().frame(width: 64, height: 72).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘 미션마다").font(AppFont.font(.caption))
                    Text("\(store.state.missionRewardPoints)P")
                        .font(AppFont.font(.title, weight: .bold)).monospacedDigit()
                        .accessibilityIdentifier("mission.rewardPoints")
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("연속 보상 수령").font(AppFont.font(.caption))
                    Text("\(store.state.missionRewardStreak)일")
                        .font(AppFont.font(.title2, weight: .bold)).monospacedDigit()
                }
            }
            Text("출석하고 미션 보상을 받으면 다음 날 각 미션 보상이 5P 늘어요. 하루를 쉬면 5P부터 다시 시작해요.")
                .font(AppFont.font(.caption))
                .foregroundStyle(Color.repickSecondaryText)
            Text("미션별 하루 한 번 · 10일 출석 무료 뽑기는 별도")
                .font(AppFont.font(.caption2))
                .foregroundStyle(Color.repickSecondaryText)
        }
        .padding(16)
        .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var progressDetail: String {
        switch selected {
        case .stairs:
            String(localized: "오늘 직접 기록한 계단 \(store.state.todayStairSteps)칸 · 자동 측정이 아니에요.")
        case .threeMeals:
            String(localized: "아침·점심·저녁을 각각 기록해요. 간식이나 같은 종류의 추가 기록은 끼니 수에 더하지 않아요.")
        case .calorieRange:
            if let minimum = store.state.dailyCalorieMinimum, let maximum = store.state.dailyCalorieMaximum {
                String(localized: "오늘 기록 \(store.state.recordedCaloriesToday.formatted()) kcal · 범위 \(minimum.formatted())–\(maximum.formatted()) kcal. 세 끼를 기록하고 범위 안에서 오늘 식사를 마무리해 주세요.")
            } else {
                String(localized: "먼저 나의 칼로리 범위를 설정해 주세요. 최소보다 적은 섭취 기록으로는 이 미션을 완료할 수 없어요.")
            }
        }
    }

    private var actionTitle: String {
        if complete {
            return store.state.hasCheckedInToday ? String(localized: "\(store.state.missionRewardPoints)P 받기") : String(localized: "출석하고 보상 받기")
        }
        switch selected {
        case .stairs: return progress == 0 ? String(localized: "미션 시작하기") : String(localized: "계단 수 이어서 기록")
        case .threeMeals: return String(localized: "식사 기록하기")
        case .calorieRange:
            if store.state.dailyCalorieMinimum == nil { return String(localized: "칼로리 범위 설정하기") }
            return canConfirmFood ? String(localized: "오늘 식사 마무리") : String(localized: "식사 기록하기")
        }
    }

    private func performAction() {
        if complete {
            if !store.state.hasCheckedInToday { showAttendance = true; return }
            let kind = selected
            Task { await save { try $0.claimMission(kind) } }
        } else {
            switch selected {
            case .stairs:
                stairCount = String(store.state.todayStairSteps)
                stairDay = store.state.daily.day
                stairValidation = nil
                showStairs = true
            case .threeMeals: showMeal = true
            case .calorieRange:
                if store.state.dailyCalorieMinimum == nil { showProfile = true }
                else if canConfirmFood { confirmFoodDay = true }
                else { showMeal = true }
            }
        }
    }

    private var stairEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("오늘 오른 계단 수", text: $stairCount)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("오늘 직접 확인한 계단 수")
                        .accessibilityIdentifier("mission.stairCount")
                    Text("직접 오른 계단의 오늘 누적 수를 입력해 주세요. 1층이 아닌 계단 1칸을 세며, 이미 저장한 수보다 작게 줄일 수 없어요.")
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                    if let stairValidation {
                        Text(stairValidation).foregroundStyle(Color.repickDanger)
                    }
                } header: { Text("직접 기록 · 자동 측정 아님") }
                .listRowBackground(Color.repickSurface)
                Button("계단 기록 저장") {
                    let recordedAt = Date()
                    guard stairDay == UsagiState.dayKey(for: recordedAt) else {
                        stairValidation = String(localized: "날짜가 바뀌었어요. 창을 닫고 오늘 오른 계단 수를 다시 입력해 주세요.")
                        return
                    }
                    guard let count = Int(stairCount.trimmingCharacters(in: .whitespacesAndNewlines)),
                          (store.state.todayStairSteps...100_000).contains(count) else {
                        stairValidation = String(localized: "현재 기록 이상, 100,000칸 이하의 정수를 입력해 주세요.")
                        return
                    }
                    Task {
                        if await store.update({ try $0.recordStairSteps(count, now: recordedAt) }) { showStairs = false }
                        else {
                            stairValidation = store.errorMessage ?? String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
                            store.errorMessage = nil
                        }
                    }
                }
                .disabled(store.isSaving)
                .accessibilityIdentifier("mission.saveStairs")
                .listRowBackground(Color.repickActionFill)
            }
            .scrollContentBackground(.hidden)
            .background(Color.repickCream)
            .navigationTitle("계단 수 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { showStairs = false } }
            }
        }
        .font(AppFont.font(.body))
        .presentationDetents([.medium, .large])
    }

    private func save(_ change: (inout UsagiState) throws -> Void) async {
        if !(await store.update(change)) {
            errorMessage = store.errorMessage ?? String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
            store.errorMessage = nil
        }
    }
}

private extension DailyMissionKind {
    var shortTitle: String {
        switch self {
        case .calorieRange: String(localized: "칼로리 범위")
        case .stairs: String(localized: "계단 5칸")
        case .threeMeals: String(localized: "세 끼 기록")
        }
    }
    var title: String {
        switch self {
        case .calorieRange: String(localized: "나의 범위로 하루 마무리")
        case .stairs: String(localized: "계단 5칸 오르기")
        case .threeMeals: String(localized: "아침·점심·저녁 기록하기")
        }
    }
    var icon: String {
        switch self {
        case .calorieRange: "sparkles"
        case .stairs: "shoeprints.fill"
        case .threeMeals: "fork.knife"
        }
    }
}
