import Foundation // Explicitly import Foundation
import SwiftUI
import CoreBluetooth
import Combine
import ServiceManagement // Import ServiceManagement for launch at login


// MARK: - App Configuration
class AppSettings: ObservableObject {
    @AppStorage("weakSignalThreshold") var weakSignalThreshold: Int = -75
    @AppStorage("screenOnSignalThreshold") var screenOnSignalThreshold: Int = -70 // New property
    @AppStorage("weakSignalTimeout") var weakSignalTimeout: TimeInterval = 10.0
    @AppStorage("disconnectTimeout") var disconnectTimeout: TimeInterval = 5.0
    @AppStorage("lockMode") var lockMode: LockMode = .lockScreen
    @AppStorage("selectedPeripheralUUID") var selectedPeripheralUUID: String? // New property
    @AppStorage("selectedLanguageCode") var selectedLanguageCode: String? // New property for language
    
    @Published var launchAtLoginEnabled: Bool = false

    init() {
        // Initialize launchAtLoginEnabled based on current SMAppService status
        updateLaunchAtLoginStatus()
    }

    func updateLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        if launchAtLoginEnabled {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
    }

    private func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            launchAtLoginEnabled = true
            print("Successfully enabled launch at login.")
        } catch {
            print("Failed to enable launch at login: \(error.localizedDescription)")
            launchAtLoginEnabled = false
        }
    }

    private func disableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.unregister()
            launchAtLoginEnabled = false
            print("Successfully disabled launch at login.")
        } catch {
            print("Failed to disable launch at login: \(error.localizedDescription)")
            launchAtLoginEnabled = true
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

struct ConnectedDeviceStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    var body: some View {
        if bluetoothManager.selectedPeripheral == nil {
            Text(NSLocalizedString("NO_DEVICE_CONNECTED", comment: "Text displayed when no device is connected")).disabled(true)
        } else {
            Text(String(format: NSLocalizedString("CONNECTED_DEVICE_NAME", comment: "Text showing connected device name"), bluetoothManager.selectedPeripheral?.name ?? NSLocalizedString("UNKNOWN_DEVICE", comment: "Unknown device name")))
            Text(String(format: NSLocalizedString("SIGNAL_STRENGTH", comment: "Text showing signal strength"), bluetoothManager.rssi.stringValue))
        }
    }
}

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
    @ObservedObject var bluetoothManager: BluetoothManager
    let connectAction: (CBPeripheral) -> Void

    var body: some View {
        print("SelectBluetoothDeviceMenu: body re-evaluated. Discovered count: \(bluetoothManager.discoveredPeripherals.count)")
        for device in bluetoothManager.discoveredPeripherals {
            print("  Device in list: \(device.peripheral.name ?? "Unknown") (ID: \(device.id.uuidString)) RSSI: \(device.rssi) dBm")
        }

        return Menu(NSLocalizedString("SELECT_BLUETOOTH_DEVICE_MENU_TITLE", comment: "Menu title for selecting Bluetooth device")) {
            if bluetoothManager.discoveredPeripherals.isEmpty {
                Text(NSLocalizedString("SCANNING_STATUS", comment: "Text indicating scanning in progress")).disabled(true)
            }
            // Use the struct's 'id' property, which conforms to Identifiable.
            ForEach(bluetoothManager.discoveredPeripherals) { discoveredDevice in
                DiscoveredDeviceRow(discoveredDevice: discoveredDevice, connectAction: connectAction)
            }
        }
        .onAppear {
            print("SelectBluetoothDeviceMenu: onAppear called. Starting listPopulation scan.")
            bluetoothManager.startScan(reason: .listPopulation)
        }
        .onDisappear {
            print("SelectBluetoothDeviceMenu: onDisappear called. Stopping listPopulation scan.")
            bluetoothManager.stopScan(reason: .listPopulation)
        }
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
        Menu(String(format: NSLocalizedString("SCREEN_ON_SIGNAL_THRESHOLD_MENU_TITLE", comment: "Menu title for screen on signal threshold"), settings.screenOnSignalThreshold)) {
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
            ForEach([0, 5, 10, 20, 30], id: \.self) { value in
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
            .onChange(of: settings.launchAtLoginEnabled) { _ in
                settings.toggleLaunchAtLogin()
            }
    }
}

struct PauseButton: View {
    @Binding var isPaused: Bool
    let action: () -> Void
    var body: some View {
        Button(isPaused ? NSLocalizedString("PAUSE_BUTTON_CONTINUE", comment: "Text for continue button when paused") : NSLocalizedString("PAUSE_BUTTON_PAUSE", comment: "Text for pause button"), action: action)
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

    var body: some View {
        Menu(NSLocalizedString("LANGUAGE_MENU_TITLE", comment: "Menu title for language selection")) {
            ForEach(availableLanguages, id: \.self) { langCode in
                Button(Locale(identifier: langCode).localizedString(forLanguageCode: langCode) ?? langCode) {
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

// MARK: - Main Application
@main
struct LockItApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var settings = AppSettings()

    init() {
        _bluetoothManager = StateObject(wrappedValue: BluetoothManager())
        _settings = StateObject(wrappedValue: AppSettings())

        // Apply selected language on app launch
        if let languageCode = settings.selectedLanguageCode {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    @State private var weakSignalTimer: Timer?
    @State private var disconnectTimer: Timer?
    @State private var isPaused = false
    var body: some Scene {
        MenuBarExtra(content: {
            Group {
                LockNowButton { lockScreen() }
                Divider()
                ConnectedDeviceStatusView(bluetoothManager: bluetoothManager)
                SelectBluetoothDeviceMenu(bluetoothManager: bluetoothManager) { peripheral in
                    bluetoothManager.connect(to: peripheral)
                }
                Divider()
                SignalThresholdMenu(settings: settings)
                ScreenOnSignalThresholdMenu(settings: settings) // New menu item
                WeakSignalTimeoutMenu(settings: settings)
                DisconnectTimeoutMenu(settings: settings)
                LockModeMenu(settings: settings)
                Divider()
                LaunchAtLoginToggle(settings: settings)
                LanguageSelectionMenu(settings: settings)
                PauseButton(isPaused: $isPaused) {
                    isPaused.toggle()
                }
                QuitButton { NSApplication.shared.terminate(nil) }
            }
            .onAppear {
                bluetoothManager.setup(settings: settings)
            }
        }, label: {
            Image(systemName: imageName)
        })
        .onChange(of: bluetoothManager.rssi) { newRssi in
            handleRssiChange(newRssi)
        }
        .onChange(of: bluetoothManager.selectedPeripheral) { peripheral in
            if peripheral != nil && !isPaused {
                bluetoothManager.startScan(reason: .selectedPeripheralMonitoring)
            } else {
                bluetoothManager.stopScan(reason: .selectedPeripheralMonitoring)
            }
        }
        .onChange(of: isPaused) { paused in
            if paused {
                bluetoothManager.stopScan(reason: .selectedPeripheralMonitoring)
            } else if bluetoothManager.selectedPeripheral != nil {
                bluetoothManager.startScan(reason: .selectedPeripheralMonitoring)
            }
        }
    }

    // MARK: - Computed Properties
    private var imageName: String {
        if isPaused {
            return "lock.slash.fill"
        }
        return bluetoothManager.selectedPeripheral != nil ? "lock.fill" : "lock.open.fill"
    }

    // MARK: - Core Logic
    private func handleRssiChange(_ newRssi: NSNumber) {
        guard !isPaused else { return }
        
        if newRssi.intValue < settings.weakSignalThreshold {
            if weakSignalTimer == nil {
                weakSignalTimer = Timer.scheduledTimer(withTimeInterval: settings.weakSignalTimeout, repeats: false) { _ in
                    lockScreen()
                }
            }
        } else if newRssi.intValue > settings.screenOnSignalThreshold { // New condition
            // If signal is strong enough, invalidate weak signal timer and turn on screen
            weakSignalTimer?.invalidate()
            weakSignalTimer = nil
            
            // Turn on screen
            let task = Process()
            task.launchPath = "/usr/bin/caffeinate"
            task.arguments = ["-u", "-t", "1"]
            task.launch()
        }
        else {
            weakSignalTimer?.invalidate()
            weakSignalTimer = nil
        }
    }

    private func lockScreen() {
        guard !isPaused else { return }

        let command: String
        switch settings.lockMode {
        case .lockScreen:
            command = "pmset displaysleepnow"
            print("LockScreen: Executing command: \(command)")
        case .screenSaver:
            command = "open -a ScreenSaverEngine"
            print("LockScreen: Executing command: \(command)")
        }

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()
    }
}
