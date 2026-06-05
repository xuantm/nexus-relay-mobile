import SwiftUI

@main
struct NexusRelayIPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("NexusRelay iPhone")
                .padding()
        }
    }
}
