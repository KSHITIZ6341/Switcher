import SwiftUI

@main
struct SwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Switcher") {
            MainMenuView(model: model, isCompact: false)
                .frame(minWidth: 500, minHeight: 620)
        }

        MenuBarExtra("Switcher", systemImage: "sidebar.right") {
            MainMenuView(model: model, isCompact: true)
        }
        .menuBarExtraStyle(.window)
    }
}
