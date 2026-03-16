import SwiftUI

struct DurationSection: View {
    let model: LatteModel
    
    var body: some View {
        Group {
            ForEach(AwakeDuration.allCases) { duration in
                Button(duration.title) {
                    model.toggleAwake(for: duration)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(duration.shortcut)")), modifiers: [])
            }
            
            Button("Stop", action: model.deactivate)
                .disabled(!model.isActive)
                .keyboardShortcut("0", modifiers: [])
        }
    }
}
