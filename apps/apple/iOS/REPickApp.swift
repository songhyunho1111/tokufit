import REPickShared
import SwiftUI

@main
struct REPickApp: App {
    @State private var store = UsagiStore()
    init() { AppTypographyAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .font(AppFont.font(.body))
                .environment(store)
                .tint(.repickGreen)
        }
    }
}
