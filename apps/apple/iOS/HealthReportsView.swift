import Observation
import REPickShared
import SwiftUI

struct HealthReportsView: View {
    @Environment(UsagiStore.self) private var store
    @AppStorage("apiBaseURL") private var configuredURL = ""
    @State private var model = HealthReportsModel()
    @State private var period: HealthReportPeriod = .week
    @State private var anchorDate = Date()
    @State private var request: HealthReportRequest?
    @State private var window: HealthReportWindow?
    @State private var inputError: String?
    @State private var showsWellness = false
    @State private var showsHistory = false
    @State private var generation: Task<Void, Never>?

    private var baseURL: String {
        configuredURL.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "REPickAPIBaseURL") as? String ?? "" : configuredURL
    }

    private var reportCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private var selectedReport: HealthReportResource? {
        model.report(period: period, window: window)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                periodSelection
                Button { showsWellness = true } label: {
                    Label("수면·컨디션 기록", systemImage: "bed.double")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isGenerating)
                .accessibilityIdentifier("reports.wellness")
                if let request {
                    localRecords(request)
                }
                if let message = inputError ?? model.errorMessage {
                    Text(message).font(AppFont.font(.subheadline)).foregroundStyle(Color.repickDanger)
                        .accessibilityIdentifier("reports.status")
                }
                if model.isGenerating {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("리포트 만드는 중")
                        Spacer(minLength: 8)
                        Button("취소") { generation?.cancel() }
                    }
                    .font(AppFont.font(.subheadline))
                    .accessibilityIdentifier("reports.loading")
                } else {
                    Button(selectedReport == nil ? "AI 리포트 만들기" : "기록 다시 분석") {
                        guard let request else { return }
                        generation?.cancel()
                        generation = Task { await model.generate(request) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.isConfigured || request?.hasRecords != true)
                    .accessibilityIdentifier("reports.generate")
                    Text("선택한 기간의 식사·운동·수면·컨디션 기록만 분석 서버로 전송합니다.")
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                }
                if let report = selectedReport {
                    ReportContent(report: report, cached: !model.freshIDs.contains(report.id))
                } else if !model.isGenerating && request?.hasRecords != true && inputError == nil {
                    ContentUnavailableView("아직 분석할 기록이 없어요", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("음식, 완료한 운동, 수면·컨디션을 기록한 뒤 리포트를 만들 수 있어요."))
                }
            }
            .padding(Design.pagePadding)
            .frame(maxWidth: Design.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color.repickCream)
        .foregroundStyle(Color.repickInk)
        .navigationTitle("건강 리포트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("지난 리포트")
                    .accessibilityIdentifier("reports.history")
            }
        }
        .task(id: baseURL) {
            generation?.cancel()
            await model.configure(baseURL)
        }
        .onAppear(perform: prepareRequest)
        .onChange(of: period) { _, _ in prepareRequest() }
        .onChange(of: anchorDate) { _, _ in prepareRequest() }
        .onChange(of: store.state) { _, _ in prepareRequest() }
        .onDisappear { generation?.cancel() }
        .sheet(isPresented: $showsWellness) { WellnessEntryView() }
        .sheet(isPresented: $showsHistory) { ReportHistoryView(model: model) }
    }

    private var periodSelection: some View {
        VStack(spacing: 12) {
            Picker("리포트 기간", selection: $period) {
                ForEach(HealthReportPeriod.allCases) { period in Text(period.name).tag(period) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isGenerating)
            .accessibilityIdentifier("reports.period")
            HStack(spacing: 12) {
                Button { movePeriod(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("이전 기간")
                    .disabled(model.isGenerating || previousDate == nil)
                VStack(spacing: 4) {
                    Text(window.map { ReportText.range($0) } ?? "기간 확인 중")
                        .font(AppFont.font(.headline)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("reports.range")
                    if let window, window.elapsedDays < window.dayCount {
                        Text("\(window.elapsedDays)일째 · 진행 중인 기간")
                            .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                Button { movePeriod(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("다음 기간")
                    .disabled(model.isGenerating || window.map { $0.endDate >= UsagiState.dayKey(for: Date(), calendar: reportCalendar) } != false)
            }
        }
    }

    private var previousDate: Date? {
        let component: Calendar.Component = period == .week ? .day : .month
        let offset = period == .week ? -7 : -1
        guard let date = reportCalendar.date(byAdding: component, value: offset, to: anchorDate),
              (try? period.window(containing: UsagiState.dayKey(for: date, calendar: reportCalendar))) != nil else { return nil }
        return date
    }

    private func movePeriod(_ direction: Int) {
        if direction < 0, let date = previousDate { anchorDate = date }
        else if direction > 0 {
            let component: Calendar.Component = period == .week ? .day : .month
            let offset = period == .week ? 7 : 1
            if let date = reportCalendar.date(byAdding: component, value: offset, to: anchorDate) {
                anchorDate = min(date, Date())
            }
        }
    }

    private func prepareRequest() {
        do {
            let day = UsagiState.dayKey(for: anchorDate, calendar: reportCalendar)
            window = try period.window(containing: day)
            request = try HealthReportRequest.make(state: store.state, period: period, anchorDate: day)
            inputError = nil
        } catch {
            request = nil
            window = nil
            inputError = error.localizedDescription
        }
    }

    private func localRecords(_ request: HealthReportRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보관된 기록 기준").font(AppFont.font(.headline))
            Text("음식 \(request.data.meals.count)건 · 운동 \(request.data.workouts.count)회 · 수면·컨디션 \(request.data.wellness.count)일")
                .font(AppFont.font(.subheadline))
            Text("보관 기간을 지난 기록과 삭제된 기록은 포함되지 않아요. 기록이 없는 날의 실제 식사·운동량은 알 수 없습니다.")
                .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
        }
    }
}

@Observable @MainActor
private final class HealthReportsModel {
    private(set) var reports: [HealthReportResource] = []
    private(set) var freshIDs: Set<UUID> = []
    private(set) var isConfigured = false
    private(set) var isGenerating = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var nextCursor: String?
    private var client: HealthReportClient?
    private let cache = HealthReportCache()
    private var configurationID = UUID()
    private var lastRequest: Data?
    private var idempotencyKey = UUID()
    private var preferredReports: [String: UUID] = [:]

    func report(period: HealthReportPeriod, window: HealthReportWindow?) -> HealthReportResource? {
        guard let window else { return nil }
        let candidates = reports.filter {
            $0.status == .completed && $0.period == period && $0.timeZone == window.timeZone
                && $0.metrics.window.startDate == window.startDate
        }
        let preferred = preferredReports[selectionKey(period, window)]
        return candidates.first(where: { $0.id == preferred }) ?? candidates.first
    }

    private func selectionKey(_ period: HealthReportPeriod, _ window: HealthReportWindow) -> String {
        "\(period.rawValue)|\(window.timeZone)|\(window.startDate)"
    }

    func configure(_ baseURL: String) async {
        let id = UUID()
        configurationID = id
        reports = []; freshIDs = []; nextCursor = nil; preferredReports = [:]
        client = nil; isConfigured = false; errorMessage = nil
        isGenerating = false; isRefreshing = false; lastRequest = nil; idempotencyKey = UUID()
        do {
            let client = try HealthReportClient(baseURL: baseURL)
            self.client = client
            isConfigured = true
            if let credential = try await client.existingCredential() {
                let saved = try await cache.load(origin: client.endpoint.identity, installationID: credential.id)
                guard configurationID == id, !Task.isCancelled else { return }
                reports = saved
            }
        } catch { if configurationID == id { errorMessage = error.localizedDescription } }
    }

    func generate(_ request: HealthReportRequest) async {
        guard let client, !isGenerating else { return }
        let id = configurationID
        isGenerating = true; errorMessage = nil; freshIDs = []
        defer { if configurationID == id { isGenerating = false } }
        do {
            let encoded = try HealthReportCoding.encoder().encode(request)
            if encoded != lastRequest { lastRequest = encoded; idempotencyKey = UUID() }
            var report = try await client.create(request, idempotencyKey: idempotencyKey)
            for _ in 0..<15 where report.status == .processing {
                try await Task.sleep(for: .seconds(2))
                report = try await client.fetch(id: report.id)
            }
            try Task.checkCancellation()
            guard configurationID == id else { return }
            merge([report])
            guard report.status == .completed else {
                throw report.status == .processing ? ReportClientError.processing : ReportClientError.failed
            }
            preferredReports[selectionKey(report.period, report.metrics.window)] = report.id
            freshIDs.insert(report.id)
            await saveCache(client: client, configuration: id)
        } catch is CancellationError {
            if configurationID == id { errorMessage = String(localized: "요청을 취소했습니다. 작성된 리포트는 지난 리포트에서 확인할 수 있어요.") }
        } catch {
            if configurationID == id { errorMessage = error.localizedDescription }
        }
    }

    func refreshHistory(loadMore: Bool = false) async {
        guard let client, !isRefreshing, !isGenerating else { return }
        let id = configurationID
        isRefreshing = true; errorMessage = nil
        defer { if configurationID == id { isRefreshing = false } }
        do {
            let result = try await client.list(cursor: loadMore ? nextCursor : nil)
            try Task.checkCancellation()
            guard configurationID == id else { return }
            merge(result.data)
            freshIDs.formUnion(result.data.map(\.id))
            nextCursor = result.meta.nextCursor
            await saveCache(client: client, configuration: id)
        } catch is CancellationError {
        } catch { if configurationID == id { errorMessage = error.localizedDescription } }
    }

    private func merge(_ incoming: [HealthReportResource]) {
        var merged = Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) })
        for report in incoming { merged[report.id] = report }
        reports = merged.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveCache(client: HealthReportClient, configuration: UUID) async {
        do {
            guard let credential = try await client.existingCredential(), configurationID == configuration else { return }
            try await cache.save(reports.filter { $0.status == .completed }, origin: client.endpoint.identity, installationID: credential.id)
        } catch {
            if configurationID == configuration {
                errorMessage = String(localized: "리포트는 불러왔지만 이 iPhone에 보관하지 못했어요.")
            }
        }
    }
}

private struct ReportHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: HealthReportsModel
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Text(error).font(AppFont.font(.footnote)).foregroundStyle(Color.repickDanger)
                }
                if model.reports.isEmpty {
                    ContentUnavailableView("아직 보관된 리포트가 없어요", systemImage: "doc.text")
                }
                ForEach(model.reports) { report in
                    NavigationLink {
                        ScrollView { ReportContent(report: report, cached: !model.freshIDs.contains(report.id)).padding(Design.pagePadding) }
                            .background(Color.repickCream)
                            .navigationTitle("\(report.period.name) 리포트")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(report.period.name) · \(ReportText.range(report.metrics.window))").font(AppFont.font(.headline))
                            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                            if report.status != .completed {
                                Text(report.status == .processing ? "작성 중" : "작성하지 못한 리포트")
                                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                            }
                        }
                    }
                    .listRowBackground(Color.repickSurface)
                }
                if model.nextCursor != nil {
                    Button("더 보기") { refresh(loadMore: true) }
                        .disabled(model.isRefreshing)
                }
            }
            .scrollContentBackground(.hidden).background(Color.repickCream)
            .navigationTitle("지난 리포트").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { refresh() } label: {
                        if model.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(!model.isConfigured || model.isRefreshing || model.isGenerating)
                    .accessibilityLabel("리포트 새로고침")
                }
            }
            .refreshable { await model.refreshHistory() }
            .onDisappear { refreshTask?.cancel() }
        }
    }

    private func refresh(loadMore: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { await model.refreshHistory(loadMore: loadMore) }
    }
}

private struct ReportContent: View {
    let report: HealthReportResource
    let cached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cached ? "보관된 리포트" : "분석 결과").font(AppFont.font(.headline))
                Text(ReportText.range(report.metrics.window)).font(AppFont.font(.subheadline))
                Text("작성 \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
            }
            metrics
            if report.status == .completed, let evaluation = report.evaluation {
                PaperCard {
                    VStack(alignment: .leading, spacing: 16) {
                        highlightedTitle(Text("우사기의 \(report.period.name) 평가"))
                        ReportUsagiView(reaction: report.reaction)
                        Text(evaluation)
                            .font(AppFont.font(.body)).lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reports.evaluation")
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.cardRadius)
                        .strokeBorder(Color.repickGreen.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 16) {
                    highlightedTitle(Text("바꿔볼 세 가지"))
                    ForEach(Array(report.recommendations.enumerated()), id: \.element.id) { index, item in
                        PaperCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(AppFont.font(.subheadline, weight: .bold)).monospacedDigit()
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .foregroundStyle(Color.repickInk)
                                        .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: 10))
                                    Text(item.title)
                                        .font(AppFont.font(.headline)).foregroundStyle(Color.repickGreen)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 4)
                                }
                                Text(item.detail)
                                    .font(AppFont.font(.body)).lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reports.recommendation.\(index)")
                    }
                }
            } else {
                Text(report.status == .processing ? "리포트를 작성 중이에요. 잠시 후 목록을 새로고침해 주세요." : "평가를 완성하지 못했어요. 기간을 선택해 다시 시도해 주세요.")
                    .foregroundStyle(Color.repickSecondaryText)
            }
            Text("보관된 기록을 참고한 AI 생활 제안입니다. 기록하지 않은 날과 보관 기간이 지난 기록은 평가할 수 없어요.")
                .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
        }
        .foregroundStyle(Color.repickInk)
        .frame(maxWidth: Design.contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("음식 기록", icon: "fork.knife") {
                Text("\(report.metrics.food.loggedDays)일 기록 · \(report.metrics.food.mealCount)건")
                detail("기간 중 \(report.metrics.window.elapsedDays)일 기준")
            }
            section("운동 기록", icon: "figure.walk") {
                Text("\(report.metrics.exercise.sessionCount)회 · \(report.metrics.exercise.totalMinutes)분")
                ForEach(report.metrics.exercise.byActivity) { item in
                    detail("\(item.activity?.name ?? String(localized: "종류 미기록")) · \(item.sessions)회 · \(item.totalMinutes)분")
                }
                if let repetitions = report.metrics.exercise.totalRepetitions {
                    detail("기록된 반복 횟수 \(repetitions)회 · 미입력 항목 제외")
                }
            }
            section("영양소 비율", icon: "chart.bar.fill") {
                if let carbs = report.metrics.nutrition.carbohydratePercent,
                   let protein = report.metrics.nutrition.proteinPercent,
                   let fat = report.metrics.nutrition.fatPercent {
                    nutrient("탄수화물", percent: carbs, grams: report.metrics.nutrition.carbohydratesG)
                    nutrient("단백질", percent: protein, grams: report.metrics.nutrition.proteinG)
                    nutrient("지방", percent: fat, grams: report.metrics.nutrition.fatG)
                } else {
                    Text(report.metrics.nutrition.trackedMeals == 0 ? "영양소 기록 없음" : "영양소 열량이 0이라 비율을 계산할 수 없어요.")
                }
                detail("음식 \(report.metrics.nutrition.totalMeals)건 중 영양소를 입력한 \(report.metrics.nutrition.trackedMeals)건의 열량 비중")
            }
            section("섭취 열량", icon: "flame") {
                Text("기록된 합계 \(report.metrics.calories.totalKcal.formatted()) kcal")
                if let average = report.metrics.calories.averagePerLoggedDay {
                    detail("기록한 \(report.metrics.calories.loggedDays)일 평균 \(average.formatted(.number.precision(.fractionLength(0)))) kcal")
                } else { detail("음식 기록 없음") }
            }
            section("수면·컨디션", icon: "moon.zzz") {
                Text(report.metrics.wellness.averageSleepMinutes.map { String(localized: "평균 수면 \(ReportText.sleep($0))") } ?? String(localized: "수면 기록 없음"))
                detail("수면 \(report.metrics.wellness.sleepLoggedDays)일 기록")
                if let condition = report.metrics.wellness.averageCondition {
                    Text("평균 컨디션 \(condition.formatted(.number.precision(.fractionLength(1)))) / 5")
                } else { Text("컨디션 기록 없음") }
                detail("컨디션 \(report.metrics.wellness.conditionLoggedDays)일 자가 기록")
            }
        }
        .accessibilityIdentifier("reports.metrics")
    }

    private func section<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon).foregroundStyle(Color.repickGreen)
                    highlightedTitle(Text(title))
                }
                content().font(AppFont.font(.body))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func highlightedTitle(_ title: Text) -> some View {
        title.font(AppFont.font(.headline)).foregroundStyle(Color.repickGreen)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.repickGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
    }

    private func nutrient(_ name: LocalizedStringKey, percent: Double, grams: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name) + Text(" \(percent.formatted(.number.precision(.fractionLength(1))))%")
            ProgressView(value: percent, total: 100).tint(.repickGreen)
            if let grams { detail("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g") }
        }
    }
}

private enum ReportText {
    static func range(_ window: HealthReportWindow) -> String {
        "\(window.startDate.replacingOccurrences(of: "-", with: ".")) – \(window.endDate.replacingOccurrences(of: "-", with: "."))"
    }

    static func sleep(_ minutes: Double) -> String {
        let value = Int(minutes.rounded())
        return String(localized: "\(value / 60)시간 \(value % 60)분")
    }
}
