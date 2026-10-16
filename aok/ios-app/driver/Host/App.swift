// AOKDriver's host: the UI tests drive other apps (AOK VM, Settings) by bundle identifier; this only hosts them.
// In front, it keeps the screen on, as the bench app's hold does.
import SwiftUI

@main
struct AOKDriverHost: App {
    var body: some Scene {
        WindowGroup {
            Text("AOK Driver").onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
