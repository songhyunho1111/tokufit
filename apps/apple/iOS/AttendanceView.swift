import REPickShared
import SwiftUI
import UIKit

struct AttendanceView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var calendarBadgeSize = 40.0
    @ScaledMetric(relativeTo: .subheadline) private var weekdayHeight = 22.0
    @State private var showProfile = false
    @State private var showHelp = false
    @State private var errorMessage: String?
    @State private var isCheckingIn = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    private var today: Date {
        let components = store.state.daily.day.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return Date() }
        return calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2], hour: 12)) ?? Date()
    }

    private var week: [Date] {
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - daysSinceMonday, to: today) }
    }

    private var weekCount: Int {
        week.filter { store.state.attendance.days.contains(UsagiState.dayKey(for: $0, calendar: calendar)) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    checkInCard
                        .padding(.bottom, 16)
                    weeklyCard
                        .padding(.bottom, 11)
                    goalCard
                        .padding(.bottom, 10)
                    recordsCard
                }
                .frame(maxWidth: Design.contentWidth)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.repickInk)
        .background(AttendancePalette.page.ignoresSafeArea())
        .statusBarHidden(false)
        .sheet(isPresented: $showProfile) { ProfileEditor() }
        .alert("출석 안내", isPresented: $showHelp) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("출석 버튼을 누르면 하루 한 번 기록돼요. 연속 10·20·30일과 이후 매 10일째, 그날의 걸음 목표까지 달성하면 무료 뽑기 1회를 받아요. 출석과 걸음 목표는 어느 쪽을 먼저 완료해도 괜찮아요. 무료 기회는 사용하기 전까지 보관돼요.\n\n하루를 빠뜨리면 연속 출석이 새로 시작돼요. 불꽃 눈은 다시 출석하면 사라져요.")
        }
        .alert("출석을 저장하지 못했어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .interactiveDismissDisabled(isCheckingIn)
        .task { await store.refreshDay() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(isCheckingIn)
            .accessibilityLabel("홈으로 돌아가기")
            .accessibilityIdentifier("attendance.back")
            Spacer(minLength: 0)
            Text("출석체크")
                .font(AppFont.font(.title2, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("출석 도움말")
            .accessibilityIdentifier("attendance.help")
        }
        .font(AppFont.font(.title3, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: Design.contentWidth + 24)
    }

    private var checkInCard: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    checkInDate
                    checkInIllustration
                        .containerRelativeFrame(.horizontal) { width, _ in min(max(0, width - 64), 240) }
                        .frame(height: 220)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                // shortcut: the source art's shallow mat limits overlap; revisit if the space below its feet grows.
                Color.clear
                    .aspectRatio(720.0 / 390, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geometry in
                            checkInIllustration
                                .frame(width: geometry.size.width * 0.575, height: geometry.size.width * 0.575)
                                .offset(x: geometry.size.width * 0.31, y: -3)
                            checkInDate
                                .frame(width: geometry.size.width * 0.5, alignment: .leading)
                        }
                    }
                    .padding(.bottom, -10)
            }

            Button {
                Task { await checkIn() }
            } label: {
                Text(isCheckingIn ? "저장 중…" : store.state.hasCheckedInToday ? "오늘 출석 완료" : "오늘도 출석하기")
                    .font(AppFont.font(.title3, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .foregroundStyle(AttendancePalette.actionInk)
                    .background(AttendancePalette.action, in: Capsule())
                    .overlay { Capsule().strokeBorder(AttendancePalette.actionBorder, lineWidth: 1.5) }
                    .shadow(color: .black.opacity(0.25), radius: 2.5, x: 0, y: 2.5)
            }
            .buttonStyle(.plain)
            .disabled(isCheckingIn || store.isSaving || store.state.hasCheckedInToday)
            .accessibilityIdentifier("attendance.checkIn")
            Text("출석은 하루 한 번 기록돼요")
                .font(AppFont.font(.caption, weight: .medium))
                .foregroundStyle(Color.repickSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(AttendancePalette.checkInGradient, in: RoundedRectangle(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(AttendancePalette.checkInBorder, lineWidth: 1) }
    }

    private var checkInDate: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(today.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                .font(AppFont.font(.body, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("attendance.date")
            Text(store.state.hasCheckedInToday ? "출석 완료" : "출석 전")
                .font(AppFont.font(.caption, weight: .medium))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(AttendancePalette.status, in: Capsule())
                .overlay { Capsule().strokeBorder(AttendancePalette.actionBorder, lineWidth: 0.5) }
                .accessibilityIdentifier("attendance.status")
        }
        .padding(.top, 4)
    }

    private var checkInIllustration: some View {
        Image(store.state.attendanceNeedsAttention ? "AttendanceUsagiFiery" : "AttendanceUsagi")
            .resizable()
            .scaledToFit()
            .accessibilityLabel(store.state.attendanceNeedsAttention ? "다시 출석을 기다리는 불꽃 눈 우사기" : "당근을 안고 있는 우사기")
            .accessibilityIdentifier("attendance.illustration")
    }

    private var weeklyCard: some View {
        attendanceCard(background: AttendancePalette.weeklyGradient) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        weeklyTitle
                        Spacer()
                        weekRange
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        weeklyTitle
                        weekRange
                    }
                }
                GeometryReader { geometry in
                    let badgeSize = dynamicTypeSize.isAccessibilitySize
                        ? calendarBadgeSize : min(calendarBadgeSize, (geometry.size.width - 9) / 7)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                                if index > 0 {
                                    Rectangle().fill(AttendancePalette.divider)
                                        .frame(width: 0.5)
                                }
                                calendarDay(date, badgeSize: badgeSize)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(width: max(geometry.size.width, badgeSize * 7 + 9))
                    }
                }
                .frame(height: calendarBadgeSize + weekdayHeight + 10)
                (Text("이번 주 ") + Text("\(weekCount)일").foregroundColor(AttendancePalette.accent) + Text(" 출석"))
                    .font(AppFont.font(.subheadline, weight: .medium))
                    .accessibilityIdentifier("attendance.weekSummary")
            }
        }
    }

    private var weeklyTitle: some View {
        Text("이번 주 출석").font(AppFont.font(.body, weight: .medium))
    }

    private var weekRange: some View {
        let range = week.first.map { shortDate($0) } ?? ""
        let end = week.last.map { shortDate($0) } ?? ""
        return Text("\(range) ~ \(end)")
            .font(AppFont.font(.caption, weight: .medium))
            .foregroundStyle(Color.repickSecondaryText)
    }

    private func calendarDay(_ date: Date, badgeSize: CGFloat) -> some View {
        let key = UsagiState.dayKey(for: date, calendar: calendar)
        let isToday = key == store.state.daily.day
        let isCheckedIn = store.state.attendance.days.contains(key)
        let weekday = date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR")))
        return VStack(spacing: 10) {
            Text(weekday)
                .font(AppFont.font(.subheadline, weight: .medium))
                .frame(height: weekdayHeight)
            ZStack {
                if isToday {
                    AttendanceDateBadge()
                        .fill(AttendancePalette.badge)
                        .overlay { AttendanceDateBadge().strokeBorder(AttendancePalette.badgeBorder, lineWidth: 1.5) }
                } else {
                    Circle().fill(AttendancePalette.badge)
                        .overlay { Circle().strokeBorder(AttendancePalette.checkInBorder, lineWidth: 1) }
                }
                if isCheckedIn {
                    AttendanceCarrot().padding(9)
                } else if isToday {
                    Text("\(calendar.component(.day, from: date))")
                        .font(AppFont.font(.body, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))), \(isCheckedIn ? String(localized: "출석 완료") : key > store.state.daily.day ? String(localized: "예정") : String(localized: "출석 기록 없음"))"))
        .accessibilityIdentifier("attendance.day.\(key)")
    }

    private var goalCard: some View {
        Button { showProfile = true } label: {
            attendanceCard(background: AttendancePalette.goalGradient) {
                HStack(spacing: 16) {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(AttendancePalette.checkIn, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("나의 습관 목표")
                            .font(AppFont.font(.caption, weight: .medium))
                            .foregroundStyle(Color.repickSecondaryText)
                        Text(store.state.preferences.goalTitle.isEmpty
                             ? String(localized: "하루 \(store.state.daily.goalSteps.formatted())보 걷기")
                             : store.state.preferences.goalTitle)
                            .font(AppFont.font(.body, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if let profile = store.state.profile {
                            Text("목표 몸무게 \(profile.targetWeightKG.formatted()) kg")
                                .font(AppFont.font(.caption, weight: .medium))
                                .foregroundStyle(Color.repickSecondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.repickSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("목표와 프로필을 수정합니다.")
        .accessibilityIdentifier("attendance.goal")
    }

    private var recordsCard: some View {
        attendanceCard(background: AttendancePalette.recordsGradient) {
            VStack(alignment: .leading, spacing: 14) {
                Text("오늘의 기록")
                    .font(AppFont.font(.body, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    recordTile("섭취 열량", value: String(localized: "\(store.state.daily.meals.reduce(0) { $0 + $1.calories }.formatted()) kcal"), icon: "fork.knife", color: AttendancePalette.food, ink: AttendancePalette.foodInk, id: "food")
                    recordTile("운동", value: String(localized: "\(store.state.workoutMinutesToday)분"), icon: "dumbbell", color: AttendancePalette.exercise, ink: AttendancePalette.exerciseInk, id: "exercise")
                    recordTile("수면", value: sleepValue, icon: "moon", color: AttendancePalette.sleep, ink: AttendancePalette.sleepInk, id: "sleep")
                    recordTile("컨디션", value: conditionValue, icon: "face.smiling", color: AttendancePalette.condition, ink: AttendancePalette.conditionInk, id: "condition")
                }
            }
        }
    }

    private func recordTile(_ label: LocalizedStringKey, value: String, icon: String, color: Color, ink: Color, id: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(ink)
                .frame(width: 32, height: 32)
                .background(color, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(AppFont.font(.caption2, weight: .medium))
                    .foregroundStyle(Color.repickSecondaryText)
                Text(value).font(AppFont.font(.caption, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("attendance.metric.\(id)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AttendancePalette.tile, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }

    private var sleepValue: String {
        guard let minutes = store.state.wellnessHistory.first(where: { $0.day == store.state.daily.day })?.sleepMinutes else {
            return String(localized: "기록 없음")
        }
        return String(localized: "\(minutes / 60)시간 \(minutes % 60)분")
    }

    private var conditionValue: String {
        switch store.state.wellnessHistory.first(where: { $0.day == store.state.daily.day })?.condition {
        case 1: String(localized: "매우 나쁨")
        case 2: String(localized: "나쁨")
        case 3: String(localized: "보통")
        case 4: String(localized: "좋음")
        case 5: String(localized: "매우 좋음")
        default: String(localized: "기록 없음")
        }
    }

    private func attendanceCard<Content: View>(background: LinearGradient, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 30))
            .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(AttendancePalette.border, lineWidth: 1) }
    }

    private func shortDate(_ date: Date) -> String {
        "\(calendar.component(.month, from: date)).\(String(format: "%02d", calendar.component(.day, from: date)))"
    }

    private func checkIn() async {
        guard !isCheckingIn, !store.isSaving, !store.state.hasCheckedInToday else { return }
        isCheckingIn = true
        defer { isCheckingIn = false }
        if !(await store.update { try $0.checkIn() }) {
            errorMessage = store.errorMessage ?? String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
            store.errorMessage = nil
        }
    }
}

private struct AttendanceDateBadge: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        return Path { path in
            for index in 0...144 {
                let angle = Double(index) / 144 * .pi * 2
                let scallop = radius * (0.94 + 0.06 * cos(angle * 12))
                let point = CGPoint(x: rect.midX + cos(angle) * scallop, y: rect.midY + sin(angle) * scallop)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

private struct AttendanceCarrot: View {
    var body: some View {
        Canvas { context, size in
            let scale = CGAffineTransform(scaleX: size.width / 24, y: size.height / 24)
            let carrot = Path { path in
                path.move(to: CGPoint(x: 4, y: 22))
                path.addQuadCurve(to: CGPoint(x: 10, y: 7), control: CGPoint(x: 4, y: 11))
                path.addQuadCurve(to: CGPoint(x: 18, y: 14), control: CGPoint(x: 20, y: 4))
                path.addQuadCurve(to: CGPoint(x: 4, y: 22), control: CGPoint(x: 14, y: 20))
            }.applying(scale)
            context.fill(carrot, with: .color(Color(red: 0.94, green: 0.64, blue: 0.33)))
            context.stroke(carrot, with: .color(Color(red: 0.68, green: 0.39, blue: 0.17)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            let leaves = Path { path in
                path.move(to: CGPoint(x: 14, y: 8)); path.addLine(to: CGPoint(x: 14, y: 2))
                path.move(to: CGPoint(x: 16, y: 8)); path.addLine(to: CGPoint(x: 20, y: 2))
                path.move(to: CGPoint(x: 17, y: 10)); path.addLine(to: CGPoint(x: 23, y: 6))
            }.applying(scale)
            context.stroke(leaves, with: .color(Color(red: 0.40, green: 0.59, blue: 0.22)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private enum AttendancePalette {
    static let page = Color.repickCream
    static let checkIn = Color.repickSurface
    static let checkInBorder = color(0xE5E5E7, 0x48484A)
    static let checkInGradient = EllipticalGradient(
        gradient: Gradient(stops: [
            .init(color: color(0xFFFFFF, 0x343436), location: 0),
            .init(color: color(0xFCFCFD, 0x303032), location: 0.58),
            .init(color: color(0xF7F7F8, 0x2C2C2E), location: 1)
        ]),
        center: UnitPoint(x: 0.18, y: 0.3),
        startRadiusFraction: 0,
        endRadiusFraction: 1
    )
    static let weeklyGradient = LinearGradient(
        colors: [color(0xFFFFFF, 0x303032), color(0xF9F9FA, 0x2C2C2E)],
        startPoint: .top, endPoint: .bottom
    )
    static let goalGradient = LinearGradient(
        colors: [color(0xFFFFFF, 0x303032), color(0xFAFAFB, 0x2C2C2E)],
        startPoint: .top, endPoint: .bottom
    )
    static let recordsGradient = LinearGradient(
        colors: [color(0xFAFAFB, 0x303032), color(0xFFFFFF, 0x2C2C2E)],
        startPoint: .top, endPoint: .bottom
    )
    static let border = color(0xEAEAEC, 0x48484A)
    static let action = color(0xF9E194, 0xF9E194)
    static let actionBorder = color(0xB6A776, 0xB6A776)
    static let actionInk = color(0x0F0A04, 0x0F0A04)
    static let status = color(0xFAE9AE, 0x50452C)
    static let accent = color(0x877022, 0xE4C76C)
    static let divider = color(0xD8D8DC, 0x505054)
    static let badge = color(0xFCFCFD, 0x343436)
    static let badgeBorder = color(0xECD7A5, 0x887544)
    static let tile = color(0xF6F6F7, 0x343436)
    static let food = color(0xFBF1D5, 0x4A3D25)
    static let foodInk = color(0xA6612F, 0xF5C18C)
    static let exercise = color(0xDBF3E5, 0x284237)
    static let exerciseInk = color(0x438265, 0xA4DDC0)
    static let sleep = color(0xEBE7FB, 0x3E3655)
    static let sleepInk = color(0x77649E, 0xCDBEF0)
    static let condition = color(0xDDEEFC, 0x2B4052)
    static let conditionInk = color(0x5D87AC, 0xB2D5F2)

    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}
