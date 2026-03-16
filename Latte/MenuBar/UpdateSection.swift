import SwiftUI

struct UpdateSection: View {
    @Bindable var model: LatteModel
    @State private var isShowingUpToDateAlert = false
    
    var body: some View {
        Group {
            Button("Check for updates", action: checkForUpdates)
                .alert("Latte is up to date", isPresented: $isShowingUpToDateAlert) {
                } message: {
                    Text("You already have the latest version installed.")
                }
                .keyboardShortcut("r")
                .disabled(model.isCheckingForUpdates || model.isInstallingPreparedUpdate)
            
            if let preparedUpdateTag = model.preparedUpdateTag {
                Button("Install \(preparedUpdateTag)", systemImage: "square.and.arrow.down", action: installPreparedUpdate)
                    .disabled(model.isCheckingForUpdates)
                
                Button("Later", systemImage: "clock.arrow.circlepath", action: dismissPreparedUpdate)
                    .disabled(model.isInstallingPreparedUpdate)
                
                if let preparedUpdateReleaseURL = model.preparedUpdateReleaseURL {
                    Link("Open release page", destination: preparedUpdateReleaseURL)
                }
            }
        }
    }
    
    private func checkForUpdates() {
        Task {
            let result = await model.checkForUpdatesNow()
            guard result == .upToDate else { return }
            await MainActor.run {
                isShowingUpToDateAlert = true
            }
        }
    }
    
    private func installPreparedUpdate() {
        Task {
            await model.installPreparedUpdate()
        }
    }
    
    private func dismissPreparedUpdate() {
        Task {
            await model.dismissPreparedUpdate()
        }
    }
}
