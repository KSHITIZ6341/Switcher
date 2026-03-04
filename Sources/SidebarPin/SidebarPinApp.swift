import SwiftUI

@main
struct SidebarPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Sidebar Pin") {
            MainMenuView(model: model, isCompact: false)
                .frame(minWidth: 500, minHeight: 620)
        }

        MenuBarExtra("Sidebar Pin", systemImage: "sidebar.right") {
            MainMenuView(model: model, isCompact: true)
        }
        .menuBarExtraStyle(.window)
    }
}
