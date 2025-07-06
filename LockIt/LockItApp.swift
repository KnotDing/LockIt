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
    case lockScreen = "锁屏"
    case screenSaver = "启动屏幕保护"
}

// MARK: - Helper Views
struct LockNowButton: View {
    let action: () -> Void
    var body: some View {
        Button("立即锁定", action: action)
    }
}

struct ConnectedDeviceStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    var body: some View {
        if bluetoothManager.selectedPeripheral == nil {
            Text("未连接设备").disabled(true)
        } else {
            Text("已连接: \(bluetoothManager.selectedPeripheral?.name ?? "未知设备")")
            Text("信号强度: \(bluetoothManager.rssi) dBm")
        }
    }
}

struct DiscoveredDeviceRow: View {
    let discoveredDevice: DiscoveredDevice
    let connectAction: (CBPeripheral) -> Void

    var body: some View {
        Button("\(discoveredDevice.peripheral.name ?? "未知设备") (ID: \(discoveredDevice.peripheral.identifier.uuidString.prefix(8))... | RSSI: \(discoveredDevice.rssi) dBm)") { // Fixed: Use peripheral.name
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

        return Menu("选择蓝牙设备") {
            if bluetoothManager.discoveredPeripherals.isEmpty {
                Text("扫描中...").disabled(true)
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
        Menu("弱信号强度 (\(settings.weakSignalThreshold) dBm)") {
            ForEach(stride(from: -30, through: -90, by: -5).map { $0 }, id: \.self) { value in
                Button("\(value) dBm") { settings.weakSignalThreshold = value }
            }
        }
    }
}

struct ScreenOnSignalThresholdMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu("点亮屏幕信号强度 (\(settings.screenOnSignalThreshold) dBm)") {
            ForEach(stride(from: -30, through: -90, by: -5).map { $0 }, id: \.self) { value in
                // Ensure screenOnSignalThreshold is stronger (less negative) than weakSignalThreshold
                if value > settings.weakSignalThreshold {
                    Button("\(value) dBm") { settings.screenOnSignalThreshold = value }
                }
            }
        }
    }
}

struct WeakSignalTimeoutMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu("弱信号超时时间 (\(Int(settings.weakSignalTimeout)) 秒)") {
            ForEach([5, 10, 20, 30, 60], id: \.self) { value in
                Button("\(value) 秒") { settings.weakSignalTimeout = TimeInterval(value) }
            }
        }
    }
}

struct DisconnectTimeoutMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu("连接断开超时时间 (\(Int(settings.disconnectTimeout)) 秒)") {
            ForEach([0, 5, 10, 20, 30], id: \.self) { value in
                Button("\(value) 秒") { settings.disconnectTimeout = TimeInterval(value) }
            }
        }
    }
}

struct LockModeMenu: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Menu("锁定方式 (\(settings.lockMode.rawValue))") {
            ForEach(LockMode.allCases, id: \.self) { mode in
                Button(mode.rawValue) { settings.lockMode = mode }
            }
        }
    }
}

struct LaunchAtLoginToggle: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Toggle("开机启动", isOn: $settings.launchAtLoginEnabled)
            .onChange(of: settings.launchAtLoginEnabled) { _ in
                settings.toggleLaunchAtLogin()
            }
    }
}

struct PauseButton: View {
    @Binding var isPaused: Bool
    let action: () -> Void
    var body: some View {
        Button(isPaused ? "继续" : "暂停", action: action)
    }
}

struct QuitButton: View {
    let action: () -> Void
    var body: some View {
        Button("退出", action: action)
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
