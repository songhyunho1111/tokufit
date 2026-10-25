import SwiftUI

@main
struct REPickApp: App {
    @State private var store = UsagiStore()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .tint(.repickGreen)
        }
    }
}
