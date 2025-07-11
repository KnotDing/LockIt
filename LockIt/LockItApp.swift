import Foundation // Explicitly import Foundation
import SwiftUI
import CoreBluetooth
import Combine
import ServiceManagement // Import ServiceManagement for launch at login
import CoreGraphics // Import CoreGraphics for screen lock status


// MARK: - App Configuration
class AppSettings: ObservableObject {
    @AppStorage("weakSignalThreshold") var weakSignalThreshold: Int = -75
    @AppStorage("screenOnSignalThreshold") var screenOnSignalThreshold: Int = -70 // New property
    @AppStorage("weakSignalTimeout") var weakSignalTimeout: TimeInterval = 10.0
    @AppStorage("disconnectTimeout") var disconnectTimeout: TimeInterval = 5.0
    @AppStorage("lockMode") var lockMode: LockMode = .lockScreen
    @AppStorage("selectedPeripheralUUID") var selectedPeripheralUUID: String? // New property
    @AppStorage("selectedPeripheralName") var selectedPeripheralName: String? // New property
    @AppStorage("selectedLanguageCode") var selectedLanguageCode: String? // New property for language
    @AppStorage("pauseMediaOnLock") var pauseMediaOnLock: Bool = false // New property
    @AppStorage("wakeOnAutoLockOnly") var wakeOnAutoLockOnly: Bool = false // New property
    @AppStorage("skippedVersion") var skippedVersion: String = "" // For update skipping
    @Published var isPaused: Bool = UserDefaults.standard.bool(forKey: "isPaused") { // New property for pause state
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "isPaused")
        }
    }
    
    @Published var launchAtLoginEnabled: Bool = false

    init() {
        // Initialize launchAtLoginEnabled based on current SMAppService status
        updateLaunchAtLoginStatus()
        
        // Apply selected language on app launch
        if let languageCode = selectedLanguageCode {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    func updateLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        if launchAtLoginEnabled {
            enableLaunchAtLogin()
        } else {
            disableLaunchAtLogin()
        }
    }

    private func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            #if DEBUG
            print("Successfully enabled launch at login.")
            #endif
        } catch {
            #if DEBUG
            print("Failed to enable launch at login: \(error.localizedDescription)")
            #endif
        }
    }

    private func disableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.unregister()
            #if DEBUG
            print("Successfully disabled launch at login.")
            #endif
        } catch {
            #if DEBUG
            print("Failed to disable launch at login: \(error.localizedDescription)")
            #endif
        }
    }
    
    func lockScreen() {
        guard !isPaused else { return }

        let command: String
        switch lockMode {
        case .lockScreen:
            command = "pmset displaysleepnow"
            #if DEBUG
            print("LockScreen: Executing command: \(command)")
            print("LockItApp: Screen locked.")
            #endif
        case .screenSaver:
            command = "open -a ScreenSaverEngine"
            #if DEBUG
            print("LockScreen: Executing command: \(command)")
            print("LockItApp: Screen saver activated.")
            #endif
        }

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()

        // Pause media if setting is enabled
        if pauseMediaOnLock {
            let pauseMediaScript = "tell application \"System Events\" to key code 49"
            let osascriptTask = Process()
            osascriptTask.launchPath = "/usr/bin/osascript"
            osascriptTask.arguments = ["-e", pauseMediaScript]
            osascriptTask.launch()
        }
    }
}

enum LockMode: String, CaseIterable {
    case lockScreen = "lockScreen"
    case screenSaver = "screenSaver"

    var localizedString: String {
        switch self {
        case .lockScreen:
            return NSLocalizedString("LOCK_MODE_LOCK_SCREEN", comment: "Lock screen mode")
        case .screenSaver:
            return NSLocalizedString("LOCK_MODE_SCREEN_SAVER", comment: "Screen saver mode")
        }
    }
}

// MARK: - Helper Views
struct LockNowButton: View {
    let action: () -> Void
    var body: some View {
        Button(NSLocalizedString("LOCK_NOW_BUTTON_TITLE", comment: "Title for the Lock Now button"), action: action)
    }
}

//struct ConnectedDeviceStatusView: View {
//    @ObservedObject var settings: AppSettings
//    @ObservedObject var bluetoothManager: BluetoothManager
//
//    var body: some View {
//        let _ = print("✅ The ConnectedDeviceStatusView containing this print statement is re-rendering.")
//        if bluetoothManager.selectedPeripheral == nil {
//            Text(NSLocalizedString("NO_DEVICE_CONNECTED", comment: "Text displayed when no device is connected")).disabled(true)
//        } else {
//            //Text(String(format: NSLocalizedString("CONNECTED_DEVICE_STATUS", comment: "Text showing connected device status"), bluetoothManager.selectedPeripheral?.name ?? NSLocalizedString("UNKNOWN_DEVICE", comment: "Unknown device name"), bluetoothManager.rssi.intValue))
////                .onChange(of: bluetoothManager.rssi) {
////                self.handleRssiChange(bluetoothManager.rssi)
////            }
//            Text(String(format: NSLocalizedString("CONNECTED_DEVICE_STATUS", comment: "Text showing connected device status"), settings.selectedPeripheralName ?? NSLocalizedString("UNKNOWN_DEVICE", comment: "Unknown device name"), 0))
//        }
//    }
//}

struct DiscoveredDeviceRow: View {
    let discoveredDevice: DiscoveredDevice
    let connectAction: (CBPeripheral) -> Void

    var body: some View {
        Button(String(format: NSLocalizedString("DISCOVERED_DEVICE_FORMAT", comment: "Format string for discovered device row"),
            discoveredDevice.peripheral.name ?? NSLocalizedString("UNKNOWN_DEVICE", comment: "Unknown device name"),
            discoveredDevice.peripheral.identifier.uuidString.prefix(8).description,
            discoveredDevice.rssi.stringValue)) { // Fixed: Use peripheral.name
            connectAction(discoveredDevice.peripheral)
        }
    }
}

struct SelectBluetoothDeviceMenu: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var bluetoothManager = BluetoothManager.shared

    @State private var weakSignalTimer: Timer?
    @State private var disconnectTimer: Timer?
    @State private var isLockedByApp = false
    var body: some View {
        let _ = print("✅ The SelectBluetoothDeviceMenu containing this print statement is re-rendering.")

        if bluetoothManager.discoveredPeripherals.isEmpty {
            Text(NSLocalizedString("SCANNING_STATUS", comment: "Text indicating scanning in progress")).disabled(true)
        }
        ForEach(bluetoothManager.discoveredPeripherals) { discoveredDevice in
            DiscoveredDeviceRow(discoveredDevice: discoveredDevice, connectAction: { peripheral in
                bluetoothManager.connect(to: peripheral)
                settings.selectedPeripheralName = peripheral.name
            }).onChange(of: bluetoothManager.rssi) {
                self.handleRssiChange(bluetoothManager.rssi)
            }
        }

    }

    private func handleRssiChange(_ newRssi: NSNumber) {
        guard !settings.isPaused else { return }

        // If screen on is disabled, don't check for strong signals
        if settings.screenOnSignalThreshold == 0 {
            if newRssi.intValue < settings.weakSignalThreshold {
                if weakSignalTimer == nil {
                    weakSignalTimer = Timer.scheduledTimer(withTimeInterval: settings.weakSignalTimeout, repeats: false) { _ in
                        settings.lockScreen()
                    }
                }
            } else {
                weakSignalTimer?.invalidate()
                weakSignalTimer = nil
            }
            return
        }

        if newRssi.intValue < settings.weakSignalThreshold {
            if weakSignalTimer == nil {
                weakSignalTimer = Timer.scheduledTimer(withTimeInterval: settings.weakSignalTimeout, repeats: false) { _ in
                    settings.lockScreen()
                }
            }
        } else if newRssi.intValue > settings.screenOnSignalThreshold { // New condition
            // If signal is strong enough, invalidate weak signal timer and turn on screen
            weakSignalTimer?.invalidate()
            weakSignalTimer = nil

            // Turn on screen only if the screen is currently locked
            if isScreenLocked() {
                if settings.wakeOnAutoLockOnly && !isLockedByApp {
                    #if DEBUG
                    print("LockItApp: Screen not woken because wakeOnAutoLockOnly is enabled and screen was not locked by app.")
                    #endif
                    return
                }
                #if DEBUG
                print("LockItApp: Screen turned on.")
                #endif
                let task = Process()
                task.launchPath = "/usr/bin/caffeinate"
                task.arguments = ["-u", "-t", "1"]
                task.launch()
                isLockedByApp = false // Reset after waking
            } else {
                #if DEBUG
                print("LockItApp: Screen is already unlocked, not turning on.")
                #endif
            }
        }
        else {
            weakSignalTimer?.invalidate()
            weakSignalTimer = nil
        }
    }
    
    // MARK: - Core Logic
    private func isScreenLocked() -> Bool {
        if let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any],
           let isLocked = sessionDict["CGSSessionScreenIsLocked"] as? Bool {
            return isLocked
        }
        return false
    }

}

struct SignalThresholdMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu(String(format: NSLocalizedString("WEAK_SIGNAL_THRESHOLD_MENU_TITLE", comment: "Menu title for weak signal threshold"), settings.weakSignalThreshold)) {
            ForEach(stride(from: -30, through: -90, by: -5).map { $0 }, id: \.self) { value in
                Button(String(format: NSLocalizedString("DBM_VALUE_FORMAT", comment: "Format for dBm value"), value)) { settings.weakSignalThreshold = value }
            }
        }
    }
}

struct ScreenOnSignalThresholdMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        let title: String
        if settings.screenOnSignalThreshold == 0 {
            title = NSLocalizedString("SCREEN_ON_SIGNAL_THRESHOLD_MENU_TITLE_DISABLED", comment: "Menu title for screen on signal threshold when disabled")
        } else {
            title = String(format: NSLocalizedString("SCREEN_ON_SIGNAL_THRESHOLD_MENU_TITLE", comment: "Menu title for screen on signal threshold"), settings.screenOnSignalThreshold)
        }

        return Menu(title) {
            Button(NSLocalizedString("DISABLED", comment: "Disabled option text")) {
                settings.screenOnSignalThreshold = 0
            }
            Divider()
            ForEach(stride(from: -30, through: -90, by: -5).map { $0 }, id: \.self) { value in
                // Ensure screenOnSignalThreshold is stronger (less negative) than weakSignalThreshold
                if value > settings.weakSignalThreshold {
                    Button(String(format: NSLocalizedString("DBM_VALUE_FORMAT", comment: "Format for dBm value"), value)) { settings.screenOnSignalThreshold = value }
                }
            }
        }
    }
}

struct WeakSignalTimeoutMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu(String(format: NSLocalizedString("WEAK_SIGNAL_TIMEOUT_MENU_TITLE", comment: "Menu title for weak signal timeout"), Int(settings.weakSignalTimeout))) {
            ForEach([5, 10, 20, 30, 60], id: \.self) { value in
                Button(String(format: NSLocalizedString("SECONDS_VALUE_FORMAT", comment: "Format for seconds value"), value)) { settings.weakSignalTimeout = TimeInterval(value) }
            }
        }
    }
}

struct DisconnectTimeoutMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu(String(format: NSLocalizedString("DISCONNECT_TIMEOUT_MENU_TITLE", comment: "Menu title for disconnect timeout"), Int(settings.disconnectTimeout))) {
            ForEach([5, 10, 20, 30], id: \.self) { value in
                Button(String(format: NSLocalizedString("SECONDS_VALUE_FORMAT", comment: "Format for seconds value"), value)) { settings.disconnectTimeout = TimeInterval(value) }
            }
        }
    }
}

struct LockModeMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu(String(format: NSLocalizedString("LOCK_MODE_MENU_TITLE", comment: "Menu title for lock mode selection"), settings.lockMode.localizedString)) {
            ForEach(LockMode.allCases, id: \.self) { mode in
                Button(mode.localizedString) { settings.lockMode = mode }
            }
        }
    }
}

struct LaunchAtLoginToggle: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Toggle(NSLocalizedString("LAUNCH_AT_LOGIN_TOGGLE_TITLE", comment: "Toggle title for launch at login"), isOn: $settings.launchAtLoginEnabled)
            .onChange(of: settings.launchAtLoginEnabled) {
                settings.toggleLaunchAtLogin()
            }
    }
}

// ADDED: A new dedicated view for the Pause/Resume button
struct PauseButton: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button(action: {
            settings.isPaused.toggle()
        }) {
            Text(settings.isPaused ? NSLocalizedString("PAUSE_BUTTON_CONTINUE", comment: "Text for continue button when paused") : NSLocalizedString("PAUSE_BUTTON_PAUSE", comment: "Text for pause button"))
        }
                .help(settings.isPaused ? NSLocalizedString("TOOLTIP_RESUME_ACTIVITY", comment: "Tooltip for resuming activity") : NSLocalizedString("TOOLTIP_PAUSE_ACTIVITY", comment: "Tooltip for pausing activity"))
    }
}

struct QuitButton: View {
    let action: () -> Void
    var body: some View {
        Button(NSLocalizedString("QUIT_BUTTON_TITLE", comment: "Title for the Quit button"), action: action)
    }
}

struct LanguageSelectionMenu: View {
    @ObservedObject var settings: AppSettings

    // Get available localizations from the app bundle
    private var availableLanguages: [String] {
        Bundle.main.localizations.filter { lang in
            // Filter out Base and ensure it's a valid language code
            lang != "Base" && Locale.current.localizedString(forLanguageCode: lang) != nil
        }.sorted { lang1, lang2 in
            // Sort by localized language name
            Locale.current.localizedString(forLanguageCode: lang1) ?? lang1 < Locale.current.localizedString(forLanguageCode: lang2) ?? lang2
        }
    }

    // New helper function to get specific localized names for Chinese variants
    private func getLocalizedLanguageName(for langCode: String) -> String {
        switch langCode {
        case "zh-Hans":
            return "简体中文"
        case "zh-Hant":
            return "繁體中文"
        default:
            return Locale(identifier: langCode).localizedString(forLanguageCode: langCode) ?? langCode
        }
    }

    var body: some View {
        Menu(NSLocalizedString("LANGUAGE_MENU_TITLE", comment: "Menu title for language selection")) {
            ForEach(availableLanguages, id: \.self) { langCode in
                Button(getLocalizedLanguageName(for: langCode)) {
                    settings.selectedLanguageCode = langCode
                    // Show alert to restart app
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("RESTART_APP_ALERT_TITLE", comment: "Alert title for app restart");
                    alert.informativeText = NSLocalizedString("RESTART_APP_ALERT_MESSAGE", comment: "Alert message for app restart");
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("RESTART_APP_ALERT_OK", comment: "OK button for app restart alert"))
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Helper for window access
struct HostingWindowFinder: NSViewRepresentable {
    var callback: (NSWindow?) -> ()

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            self.callback(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 5)

            VStack(spacing: 5) {
                Text(Bundle.main.appName)
                    .font(.title2.bold())
                Text(String(format: NSLocalizedString("ABOUT_VERSION_FORMAT", comment: "Version format string in About window"), Bundle.main.appVersion, Bundle.main.appBuild))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Text(NSLocalizedString("ABOUT_REPOSITORY_LABEL", comment: "Label for the repository link in About window"))
                Link("KnotDing/LockIt", destination: URL(string: "https://github.com/KnotDing/LockIt")!)
            }
            .font(.callout)
        }
        .padding(20)
        .frame(minWidth: 300)
        .background(.regularMaterial)
        .background(HostingWindowFinder { window in
            window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window?.standardWindowButton(.zoomButton)?.isHidden = true
            window?.titlebarAppearsTransparent = true
            window?.isMovableByWindowBackground = true
        })
    }
}

// MARK: - MenuBarContentView
struct MenuBarContentView: View {
    @ObservedObject var settings: AppSettings
    
    let quitAction: () -> Void
    let checkForUpdatesAction: () -> Void
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        let _ = print("✅ The MenuBarContentView containing this print statement is re-rendering.")
        let _ = Self._printChanges()
        Group {
            LockNowButton(action: { settings.lockScreen() })
            Divider()
            Menu {
                SelectBluetoothDeviceMenu(settings: settings)
            } label: {
                Text(String(format:NSLocalizedString("SELECT_BLUETOOTH_DEVICE_MENU_TITLE", comment: "Menu title for selecting Bluetooth device"), settings.selectedPeripheralName ?? NSLocalizedString("UNKNOWN_DEVICE", comment: "Unknown device name")))
            }
            Divider()
            SignalThresholdMenu(settings: settings)
            ScreenOnSignalThresholdMenu(settings: settings)
            WeakSignalTimeoutMenu(settings: settings)
            DisconnectTimeoutMenu(settings: settings)
            LockModeMenu(settings: settings)
            Divider()
            LaunchAtLoginToggle(settings: settings)
            Toggle(NSLocalizedString("WAKE_ON_AUTO_LOCK_ONLY_TOGGLE_TITLE", comment: "Toggle title for wake on auto lock only"), isOn: $settings.wakeOnAutoLockOnly)
            Toggle(NSLocalizedString("PAUSE_MEDIA_ON_LOCK_TOGGLE_TITLE", comment: "Toggle title for pause media on lock"), isOn: $settings.pauseMediaOnLock)
            Divider()
            LanguageSelectionMenu(settings: settings)
            Button(NSLocalizedString("CHECK_FOR_UPDATES_BUTTON_TITLE", comment: "Title for the Check for Updates button")) {
                checkForUpdatesAction()
            }
            Button(NSLocalizedString("ABOUT_BUTTON_TITLE", comment: "Title for the About button")) {
                openWindow(id: "about")
            }
            PauseButton(settings: settings)
            QuitButton(action: quitAction)
        }
    }
}

// MARK: - Main Application
@main
struct LockItApp: App {
    @StateObject private var settings = AppSettings()
    init() {
        let initialSettings = AppSettings()
        _settings = StateObject(wrappedValue: AppSettings())
        BluetoothManager.shared.setup(settings: settings)
        BluetoothManager.shared.lockScreenAction = {  initialSettings.lockScreen() }
    }
    var body: some Scene {
        MenuBarExtra(content: {
            MenuBarContentView(
                settings: settings,
                quitAction: { NSApplication.shared.terminate(nil) },
                checkForUpdatesAction: { self.checkForUpdates() }
            )
        }, label: {
            Image(systemName: imageName)
        })
    
        Window(NSLocalizedString("ABOUT_WINDOW_TITLE", comment: "Title for the About window"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }

    // MARK: - Computed Properties
    private var imageName: String {
        if settings.isPaused {
            return "lock.slash.fill"
        }
        return settings.selectedPeripheralUUID != nil ? "lock.fill" : "lock.open.fill"
    }
    
    // MARK: - Update Checking
    private func checkForUpdates() {
        #if DEBUG
        print("Checking for updates...")
        #endif
        guard let url = URL(string: "https://api.github.com/repos/KnotDing/LockIt/releases/latest") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                #if DEBUG
                print("Update check failed with error: \(error.localizedDescription)")
                #endif
                return
            }

            guard let data = data else {
                #if DEBUG
                print("Update check failed: No data received.")
                #endif
                return
            }
            
            #if DEBUG
            if let dataString = String(data: data, encoding: .utf8) {
                print("Received data from GitHub API: \(dataString)")
            }
            #endif

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                #if DEBUG
                print("Successfully decoded release: \(release)")
                #endif
                
                let latestVersion = release.tagName
                let currentVersion = "v" + Bundle.main.appVersion
                
                #if DEBUG
                print("Comparing versions: Latest='\(latestVersion)', Current='\(currentVersion)', Skipped='\(self.settings.skippedVersion)'")
                #endif
                
                DispatchQueue.main.async {
                    if latestVersion != currentVersion && latestVersion != self.settings.skippedVersion {
                        #if DEBUG
                        print("New version found. Showing update alert.")
                        #endif
                        self.showUpdateAlert(latestVersion: latestVersion, downloadURL: release.htmlURL)
                    } else {
                        #if DEBUG
                        print("Version is up-to-date or skipped. Showing 'up to date' alert.")
                        #endif
                        self.showUpToDateAlert()
                    }
                }
            } catch {
                #if DEBUG
                print("Failed to decode GitHub release JSON: \(error)")
                #endif
            }
        }.resume()
    }

    private func showUpdateAlert(latestVersion: String, downloadURL: String) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("UPDATE_AVAILABLE_ALERT_TITLE", comment: "Title for update available alert"), latestVersion)
        alert.informativeText = NSLocalizedString("UPDATE_AVAILABLE_ALERT_MESSAGE", comment: "Message for update available alert")
        alert.addButton(withTitle: NSLocalizedString("UPDATE_AVAILABLE_ALERT_UPDATE_NOW", comment: "Update Now button for update alert"))
        alert.addButton(withTitle: NSLocalizedString("UPDATE_AVAILABLE_ALERT_SKIP_VERSION", comment: "Skip This Version button for update alert"))
        alert.addButton(withTitle: NSLocalizedString("UPDATE_AVAILABLE_ALERT_CANCEL", comment: "Cancel button for update alert"))

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Update Now
            if let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn: // Skip This Version
            self.settings.skippedVersion = latestVersion
        default:
            break
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("UP_TO_DATE_ALERT_TITLE", comment: "Title for up to date alert")
        alert.informativeText = String(format: NSLocalizedString("UP_TO_DATE_ALERT_MESSAGE", comment: "Message for up to date alert"), Bundle.main.appVersion)
        alert.addButton(withTitle: NSLocalizedString("UP_TO_DATE_ALERT_OK", comment: "OK button for up to date alert"))
        alert.runModal()
    }
}

// MARK: - GitHub Release Model
struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}


// MARK: - Bundle Extension
extension Bundle {
    var appName: String {
        infoDictionary?["CFBundleName"] as? String ?? "LockIt"
    }
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
