import SwiftUI
import REPickShared

struct HomeView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var steps = StepTracker()
    @State private var selection = 1

    var body: some View {
        @Bindable var store = store
        Group {
            if store.isLoaded && store.state.profile == nil {
                OnboardingView()
            } else if store.isLoaded {
                TabView(selection: $selection) {
                    CareView(steps: steps).tabItem { Label("홈", systemImage: "house") }.tag(1)
                    ExerciseView(steps: steps).tabItem { Label("운동", systemImage: "figure.run") }.tag(0)
                    WardrobeView().tabItem { Label("꾸미기", systemImage: "tshirt") }.tag(2)
                    ProfileView().tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
                    FoodCaloriesView(isSelected: selection == 4)
                        .tabItem { Label("음식 칼로리", systemImage: "camera") }.tag(4)
                }
            } else if store.loadFailed {
                ContentUnavailableView {
                    Label("기록을 불러오지 못했어요", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("저장 공간을 확인하고 다시 시도해 주세요. 기존 기록은 유지됩니다.")
                } actions: {
                    Button("다시 불러오기") { Task { await store.load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("불러오는 중")
            }
        }
        .foregroundStyle(Color.repickInk)
        .onOpenURL { url in
            guard url.scheme == "repick" else { return }
            switch url.host {
            case "care": selection = 1
            case "walk", "exercise": selection = 0
            default: break
            }
        }
        .task {
            await store.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await store.refreshDay()
                if let trackingDate = steps.trackingDate, !Calendar.current.isDateInToday(trackingDate) {
                    steps.stop(); steps.start()
                }
            }
        }
        .onChange(of: steps.steps) { _, count in
            guard let date = steps.trackingDate else { return }
            let day = UsagiState.dayKey(for: date)
            Task { await store.recordSteps(count, day: day) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.refreshDay()
                    if steps.trackingDate != nil { steps.stop(); steps.start() }
                }
            }
        }
        .alert("안내", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("뽑기 결과", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("확인") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }
}
