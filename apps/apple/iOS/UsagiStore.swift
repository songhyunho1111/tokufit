import Foundation
import Observation
import REPickShared

@Observable @MainActor
final class UsagiStore {
    private(set) var state = UsagiState()
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    private(set) var isSaving = false
    var errorMessage: String?
    var notice: String?
    var motion: UsagiMotion = .idle
    let sync = PhoneSync()
    let widget = WidgetStatePublisher()
    private let disk: LocalSaveStore
    private var pendingSteps: (count: Int, day: String)?

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "REPick", directoryHint: .isDirectory)
        var file = directory.appending(path: "usagi-v1.json")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") || ProcessInfo.processInfo.arguments.contains("--ui-testing-use-store") {
            file = URL.temporaryDirectory.appending(path: "repick-ui-test.json")
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") { try? FileManager.default.removeItem(at: file) }
        }
        #endif
        disk = LocalSaveStore(fileURL: file)
    }

    func load() async {
        guard !isSaving else { return }
        isSaving = true
        loadFailed = false
        defer { isSaving = false }
        do {
            let loaded = try await disk.load()
            try await disk.save(loaded)
            state = loaded
            isLoaded = true
            errorMessage = nil
            sync.publish(loaded)
            widget.publish(loaded)
        } catch {
            loadFailed = true
            errorMessage = String(localized: "저장된 우사기를 열지 못했어요. 원본 데이터는 유지됩니다.") + "\n" + error.localizedDescription
        }
    }

    @discardableResult
    func update(_ change: (inout UsagiState) throws -> Void) async -> Bool {
        guard isLoaded, !isSaving else { return false }
        isSaving = true
        defer {
            isSaving = false
            if let pendingSteps {
                self.pendingSteps = nil
                Task { await recordSteps(pendingSteps.count, day: pendingSteps.day) }
            }
        }
        do {
            var candidate = state
            candidate.rollover()
            try change(&candidate)
            try await disk.save(candidate)
            state = candidate
            sync.publish(candidate)
            widget.publish(candidate)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func recordSteps(_ steps: Int, day: String) async {
        guard isLoaded, day == UsagiState.dayKey(for: Date()) else { return }
        if isSaving {
            pendingSteps = (max(pendingSteps?.day == day ? pendingSteps?.count ?? 0 : 0, steps), day)
            return
        }
        guard state.daily.day <= day, state.daily.day < day || steps > state.daily.steps else { return }
        await update { try $0.recordSteps(steps) }
    }

    func refreshDay() async {
        guard isLoaded else { return }
        if state.daily.day < UsagiState.dayKey(for: Date()) {
            pendingSteps = nil
            await update { $0.rollover() }
        } else {
            sync.publish(state)
        }
    }
}
