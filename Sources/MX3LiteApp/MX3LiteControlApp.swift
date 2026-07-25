import SwiftUI

@main
struct MX3LiteControlApp: App {
    @StateObject private var model = AppModel(helperURL: HelperLocator.locate())

    var body: some Scene {
        WindowGroup("mx3-lite") {
            ContentView(model: model)
                .frame(minWidth: 680, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh") { model.refresh(forceConfigReload: true) }
                    .keyboardShortcut("r")
            }
        }
    }
}
