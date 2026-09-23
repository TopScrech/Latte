import ScrechKit

struct UpdateSection: View {
    @Bindable var model: LatteModel
    @State private var isShowingUpToDateAlert = false
    
    var body: some View {
        Group {
            AsyncButton("Check for updates", action: checkForUpdates)
                .alert("Latte is up to date", isPresented: $isShowingUpToDateAlert) {
                    
                } message: {
                    Text("You already have the latest version installed.")
                }
                .keyboardShortcut("r")
                .disabled(model.isCheckingForUpdates || model.isInstallingPreparedUpdate)
            
            if let preparedUpdateTag = model.preparedUpdateTag {
                AsyncButton("Install \(preparedUpdateTag)", systemImage: "square.and.arrow.down", action: model.installPreparedUpdate)
                    .disabled(model.isCheckingForUpdates)
                
                AsyncButton("Later", systemImage: "clock.arrow.circlepath", action: model.dismissPreparedUpdate)
                    .disabled(model.isInstallingPreparedUpdate)
                
                if let preparedUpdateReleaseURL = model.preparedUpdateReleaseURL {
                    Link("Open release page", destination: preparedUpdateReleaseURL)
                }
            }
        }
    }
    
    private func checkForUpdates() async {
        let result = await model.checkForUpdatesNow()
        guard result == .upToDate else { return }
        
        await MainActor.run {
            isShowingUpToDateAlert = true
        }
    }
}
