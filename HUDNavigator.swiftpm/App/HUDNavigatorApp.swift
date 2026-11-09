import SwiftUI

@main
struct HUDNavigatorApp: App {
    var body: some Scene {
        WindowGroup {
            Text("HUD Navigator")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}
