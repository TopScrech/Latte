import SwiftUI
import AutoUpdate
import LaunchAtLogin
import OSLog

@Observable
final class LatteModel {
    enum ManualUpdateCheckResult: Equatable {
        case upToDate, updateAvailable, failed
    }
    
    private enum DefaultsKey {
        static let disablesAfterWake = "disablesAfterWake"
        static let allowsPrereleaseUpdates = "allowsPrereleaseUpdates"
        static let usesGitHubProxy = "usesGitHubProxy"
        static let gitHubProxyURL = "gitHubProxyURL"
        static let menuBarIcon = "menuBarIcon"
        static let hasConfiguredLaunchAtLogin = "hasConfiguredLaunchAtLogin"
    }
    
    nonisolated private static let logger = Logger(subsystem: "dev.topscrech.Latte", category: "LatteModel")
    nonisolated private static let updateRepositoryOwner = "TopScrech"
    nonisolated private static let updateRepositoryName = "Latte"
    nonisolated private static let automaticUpdateCheckInterval: Duration = .seconds(24 * 60 * 60)
    nonisolated static let defaultGitHubProxyURLString = "https://gh-proxy.com"
    
    var isActive = false
    var activeDuration: AwakeDuration?
    var deactivationDate: Date?
    
    var disablesAfterWake = UserDefaults.standard.bool(forKey: DefaultsKey.disablesAfterWake) {
        didSet {
            UserDefaults.standard.set(disablesAfterWake, forKey: DefaultsKey.disablesAfterWake)
        }
    }
    
    var launchesAtLogin = LaunchAtLogin.isEnabled {
        didSet {
            guard launchesAtLogin != oldValue else { return }
            
            let requestedValue = launchesAtLogin
            LaunchAtLogin.isEnabled = requestedValue
            let resolvedValue = LaunchAtLogin.isEnabled
            
            guard resolvedValue != launchesAtLogin else { return }
            launchesAtLogin = resolvedValue
        }
    }
    
    var allowsPrereleaseUpdates = UserDefaults.standard.bool(forKey: DefaultsKey.allowsPrereleaseUpdates) {
        didSet {
            UserDefaults.standard.set(allowsPrereleaseUpdates, forKey: DefaultsKey.allowsPrereleaseUpdates)
            let allowsPrereleases = allowsPrereleaseUpdates
            
            Task {
                await appUpdater.setAllowPrereleases(allowsPrereleases)
            }
        }
    }
    
    var usesGitHubProxy = UserDefaults.standard.bool(forKey: DefaultsKey.usesGitHubProxy) {
        didSet {
            UserDefaults.standard.set(usesGitHubProxy, forKey: DefaultsKey.usesGitHubProxy)
            let resolvedGitHubProxyURL = gitHubProxyURL
            
            Task {
                await appUpdater.setGitHubProxyURL(resolvedGitHubProxyURL)
            }
        }
    }
    var gitHubProxyURLString = UserDefaults.standard.string(forKey: DefaultsKey.gitHubProxyURL) ?? LatteModel.defaultGitHubProxyURLString {
        didSet {
            UserDefaults.standard.set(gitHubProxyURLString, forKey: DefaultsKey.gitHubProxyURL)
            let resolvedGitHubProxyURL = gitHubProxyURL
            
            Task {
                await appUpdater.setGitHubProxyURL(resolvedGitHubProxyURL)
            }
        }
    }
    var isCheckingForUpdates = false
    var isInstallingPreparedUpdate = false
    var updateStatusText = "Not checked yet"
    var menuBarIcon = MenuBarIcon(
        rawValue: UserDefaults.standard.string(forKey: DefaultsKey.menuBarIcon) ?? ""
    ) ?? .cupAndSaucer {
        didSet {
            UserDefaults.standard.set(menuBarIcon.rawValue, forKey: DefaultsKey.menuBarIcon)
        }
    }
    var preparedUpdateTag: String?
    var preparedUpdateReleaseURL: URL?
    var preparedUpdateReleaseNotes = ""
    
    var menuBarSymbolName: String {
        menuBarIcon.symbolName(isActive: isActive)
    }
    
    var statusTitle: String {
        isActive ? "Keeping your Mac awake" : "Latte is idle"
    }
    
    var statusSubtitle: String? {
        if let formattedDeactivationDate = deactivationDate?.formatted(date: .omitted, time: .shortened) {
            "The display will stay awake until \(formattedDeactivationDate)"
        } else {
            nil
        }
    }
    
    var appVersionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return version.hasPrefix("v") ? version : "v\(version)"
    }
    
    var showsResetGitHubProxyURLButton: Bool {
        gitHubProxyURLString != Self.defaultGitHubProxyURLString
    }
    
    private var gitHubProxyURL: URL? {
        Self.resolvedGitHubProxyURL(isEnabled: usesGitHubProxy, rawValue: gitHubProxyURLString)
    }
    
    private let appUpdater = AppUpdater(
        owner: LatteModel.updateRepositoryOwner,
        repository: LatteModel.updateRepositoryName,
        gitHubProxyURL: LatteModel.storedGitHubProxyURL()
    )
    
    private let preparedUpdateInstaller = PreparedUpdateInstaller()
    private var preparedUpdate: PreparedUpdate?
    private var powerAssertion: PowerAssertionController?
    private var deactivationTask: Task<Void, Never>?
    private var wakeObservationTask: Task<Void, Never>?
    private var automaticUpdateTask: Task<Void, Never>?
    
    init() {
        configureLaunchAtLoginOnFirstLaunch()
        startWakeObservation()
        
        Task {
            await configureAppUpdater()
            checkForUpdatesOnLaunch()
            startAutomaticUpdateChecks()
        }
    }
    
    func toggleAwake(for duration: AwakeDuration) {
        if isActive, activeDuration == duration {
            deactivate()
            return
        }
        
        activate(for: duration)
    }
    
    func isDurationActive(_ duration: AwakeDuration) -> Bool {
        isActive && activeDuration == duration
    }
    
    func deactivate() {
        powerAssertion = nil
        deactivationTask?.cancel()
        deactivationTask = nil
        isActive = false
        activeDuration = nil
        deactivationDate = nil
    }
    
    @discardableResult
    func checkForUpdatesNow() async -> ManualUpdateCheckResult {
        guard !isCheckingForUpdates else { return .failed }
        
        isCheckingForUpdates = true
        updateStatusText = "Checking for updates"
        defer { isCheckingForUpdates = false }
        
        do {
            switch try await appUpdater.prepareUpdateIfAvailable() {
            case .upToDate:
                clearPreparedUpdate()
                updateStatusText = "The latest version is already installed"
                return .upToDate
                
            case .prepared(let preparedUpdate):
                await setPreparedUpdate(preparedUpdate)
                updateStatusText = "Update available: \(preparedUpdate.release.tagName)"
                return .updateAvailable
            }
        } catch {
            clearPreparedUpdate()
            updateStatusText = "Update failed"
            Self.logger.error("Manual update check failed: \(error.localizedDescription)")
            return .failed
        }
    }
    
    func installPreparedUpdate() async {
        guard !isCheckingForUpdates else { return }
        guard let preparedUpdate else { return }
        
        isCheckingForUpdates = true
        isInstallingPreparedUpdate = true
        updateStatusText = "Installing \(preparedUpdate.release.tagName)"
        defer { isCheckingForUpdates = false }
        
        do {
            let installedAppURL = try preparedUpdateInstaller.install(preparedUpdate)
            clearPreparedUpdate()
            
            try relaunchInstalledApp(at: installedAppURL)
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            isInstallingPreparedUpdate = false
            await appUpdater.discardPreparedUpdate(preparedUpdate)
            
            clearPreparedUpdate()
            updateStatusText = "Update failed"
            
            Self.logger.error("Prepared update install failed: \(error.localizedDescription)")
        }
    }
    
    func dismissPreparedUpdate() async {
        guard let preparedUpdate else { return }
        
        await appUpdater.discardPreparedUpdate(preparedUpdate)
        clearPreparedUpdate()
        updateStatusText = "Update postponed"
    }
    
    func resetGitHubProxyURL() {
        gitHubProxyURLString = Self.defaultGitHubProxyURLString
    }
    
    func quit() {
        NSApp.terminate(nil)
    }
    
    private func activate(for duration: AwakeDuration) {
        deactivate()
        
        powerAssertion = PowerAssertionController(name: "Keeping this Mac awake")
        isActive = true
        activeDuration = duration
        
        guard let timeInterval = duration.timeInterval else {
            deactivationDate = nil
            return
        }
        
        deactivationDate = .now.addingTimeInterval(timeInterval)
        
        deactivationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeInterval))
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            self?.deactivate()
        }
    }
    
    private func startWakeObservation() {
        wakeObservationTask?.cancel()
        
        wakeObservationTask = Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification)
            
            for await _ in notifications {
                guard let self else { return }
                guard self.disablesAfterWake else { continue }
                self.deactivate()
            }
        }
    }
    
    private func startAutomaticUpdateChecks() {
        automaticUpdateTask?.cancel()
        
        automaticUpdateTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.automaticUpdateCheckInterval)
                } catch {
                    return
                }
                
                await self.checkForUpdatesAutomatically()
            }
        }
    }
    
    private func configureAppUpdater() async {
        await appUpdater.setAllowPrereleases(allowsPrereleaseUpdates)
        await appUpdater.setGitHubProxyURL(gitHubProxyURL)
        await appUpdater.setCodeSigningValidation(Self.updateCodeSigningValidation())
    }
    
    private func checkForUpdatesOnLaunch() {
        Task {
            await checkForUpdatesAutomatically()
        }
    }
    
    private func checkForUpdatesAutomatically() async {
        guard !isCheckingForUpdates else { return }
        
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        
        do {
            switch try await appUpdater.prepareUpdateIfAvailable() {
            case .upToDate:
                if preparedUpdate == nil {
                    updateStatusText = "You’re on the latest version"
                }
                
            case .prepared(let preparedUpdate):
                await setPreparedUpdate(preparedUpdate)
                updateStatusText = "Update available: \(preparedUpdate.release.tagName)"
            }
        } catch {
            Self.logger.error("Automatic update check failed: \(error.localizedDescription)")
        }
    }
    
    private func configureLaunchAtLoginOnFirstLaunch() {
        let defaults = UserDefaults.standard
        
        guard !defaults.bool(forKey: DefaultsKey.hasConfiguredLaunchAtLogin) else { return }
        
        defaults.set(true, forKey: DefaultsKey.hasConfiguredLaunchAtLogin)
        launchesAtLogin = true
    }
    
    private func setPreparedUpdate(_ preparedUpdate: PreparedUpdate) async {
        if let existingPreparedUpdate = self.preparedUpdate {
            await appUpdater.discardPreparedUpdate(existingPreparedUpdate)
        }
        
        self.preparedUpdate = preparedUpdate
        preparedUpdateTag = preparedUpdate.release.tagName
        preparedUpdateReleaseURL = preparedUpdate.release.htmlURL
        preparedUpdateReleaseNotes = preparedUpdate.release.body
    }
    
    private func clearPreparedUpdate() {
        preparedUpdate = nil
        preparedUpdateTag = nil
        preparedUpdateReleaseURL = nil
        preparedUpdateReleaseNotes = ""
        isInstallingPreparedUpdate = false
    }
    
    private func relaunchInstalledApp(at installedAppURL: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [installedAppURL.path(percentEncoded: false)]
        try process.run()
    }
    
    nonisolated private static func updateCodeSigningValidation() -> AppUpdater.CodeSigningValidation {
        guard let authority = currentCodeSigningAuthority() else {
            return .required
        }
        
        guard authority.hasPrefix("Developer ID Application:") else {
            let logger = Logger(subsystem: "dev.topscrech.Latte", category: "LatteModel")
            logger.info("Skipping strict update identity match for local authority \(authority, privacy: .public)")
            return .skipped
        }
        
        return .required
    }
    
    nonisolated private static func currentCodeSigningAuthority() -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/codesign")
        process.arguments = ["-dvvv", Bundle.main.bundleURL.path(percentEncoded: false)]
        
        let standardError = Pipe()
        process.standardOutput = Pipe()
        process.standardError = standardError
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        let description = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        
        guard let authorityLine = description
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("Authority=") })
        else {
            return nil
        }
        
        return String(authorityLine.dropFirst("Authority=".count))
    }
    
    nonisolated private static func storedGitHubProxyURL() -> URL? {
        let defaults = UserDefaults.standard
        let usesGitHubProxy = defaults.bool(forKey: "usesGitHubProxy")
        let rawValue = defaults.string(forKey: "gitHubProxyURL") ?? "https://gh-proxy.com"
        return resolvedGitHubProxyURL(isEnabled: usesGitHubProxy, rawValue: rawValue)
    }
    
    nonisolated private static func resolvedGitHubProxyURL(isEnabled: Bool, rawValue: String) -> URL? {
        guard isEnabled else { return nil }
        
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        
        return URL(string: trimmedValue)
    }
}
