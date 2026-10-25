import Foundation
import WatchConnectivity

extension WatchCompanion {
    func receiveBackgroundUpdates() async {
        activate()
        guard let session else { return }
        // shortcut: bound context-only draining to 10 seconds; revisit for queued file transfers.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !Task.isCancelled, ContinuousClock.now < deadline {
            if session.activationState == .activated, !session.hasContentPending {
                refreshConnection()
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
    }
}
