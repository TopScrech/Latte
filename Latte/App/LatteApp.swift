import SwiftUI

@main
struct LatteApp: App {
    @State private var model = LatteModel()
    
    var body: some Scene {
        MenuBarExtra("Latte", systemImage: model.menuBarSymbolName) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
