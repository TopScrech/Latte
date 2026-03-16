import SwiftUI

struct MenuBarView: View {
    @Bindable var model: LatteModel
    
    var body: some View {
        Group {
            Section("Keep awake for...") {
                if let subtitle = model.statusSubtitle {
                    Text(subtitle)
                }
                
                DurationSection(model: model)
            }
            
            Toggle("Disable after sleep", isOn: $model.disablesAfterWake)
            Toggle("Launch at login", isOn: $model.launchesAtLogin)
            
            Picker("Icon", selection: $model.menuBarIcon) {
                ForEach(MenuBarIcon.allCases) {
                    Label($0.title, systemImage: $0.inactiveSymbolName)
                        .tag($0)
                }
            }
            
            Divider()

            UpdateSection(model: model)
            
            Button("Quit Latte", action: model.quit)
                .keyboardShortcut("q")
        }
    }
}
