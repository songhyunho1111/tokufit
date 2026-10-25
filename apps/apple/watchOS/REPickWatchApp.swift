import REPickShared
import SwiftUI

@main
struct REPickWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var companion = WatchCompanion()
    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(companion: companion)
                .font(AppFont.font(.body))
                .task { companion.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { companion.refreshConnection() }
                }
        }
        .backgroundTask(.watchConnectivity) {
            await companion.receiveBackgroundUpdates()
        }
    }
}
