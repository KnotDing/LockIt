import CoreBluetooth
import Combine
import AppKit
import Foundation

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    
    static let shared = BluetoothManager()
    // MARK: - Published Properties
    @Published var discoveredPeripherals = [DiscoveredDevice]()
    var selectedPeripheralUUID: String?
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var scanBuffer = [UUID: DiscoveredDevice]()
    private var updateTimer: Timer?
    private var masterDeviceList = [UUID: DiscoveredDevice]()
    private var cleanupTimer: Timer?
    private let deviceTimeoutInterval: TimeInterval = 5.0
    private var lockScreenTimer: Timer?
    var isPaused: Bool = false // Internal pause state
    // Dependencies
    var settings: AppSettings?
    var lockScreenAction: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    private var weakSignalTimer: Timer?
    private var disconnectTimer: Timer?
    private var isLockedByApp = false
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func setup(settings: AppSettings) {
        self.settings = settings
        if let uuidString = settings.selectedPeripheralUUID {
            self.selectedPeripheralUUID = uuidString
            #if DEBUG
            print("BluetoothManager: Restored selected peripheral: \(settings.selectedPeripheralUUID ?? "Unknown")")
            #endif
        }
        // Apply initial pause state
        self.isPaused = settings.isPaused
        self.lockScreenAction = settings.lockScreen
        applyPauseState(settings.isPaused)
    }

    private func applyPauseState(_ isPaused: Bool) {
        #if DEBUG
        print("BluetoothManager: Applying pause state: \(isPaused)")
        #endif
        if isPaused {
            // --- PAUSING ---
            centralManager.stopScan()
            updateTimer?.invalidate()
            updateTimer = nil
            cleanupTimer?.invalidate()
            cleanupTimer = nil
            lockScreenTimer?.invalidate()
            lockScreenTimer = nil
            #if DEBUG
            print("BluetoothManager: All activities and timers paused.")
            #endif
        } else {
            // --- RESUMING ---
            #if DEBUG
            print("BluetoothManager: Resuming all activities.")
            #endif
            self.startScan()
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            #if DEBUG
            print("CBCentralManager State: Powered On")
            #endif
            startScan()
        default:
            #if DEBUG
            print("CBCentralManager State: Not Powered On (\(central.state.rawValue))")
            #endif
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // MODIFIED: We still discover devices in the background, but timers won't process them if paused.
        guard !self.isPaused, let name = peripheral.name, !name.isEmpty else { return }

        if peripheral.identifier.uuidString == selectedPeripheralUUID {
            DispatchQueue.main.async {
                self.handleRssiChange(newRssi: RSSI)
            }
            if self.lockScreenTimer != nil {
                self.lockScreenTimer?.invalidate()
                self.lockScreenTimer = nil
                #if DEBUG
                print("BluetoothManager: Selected device [\(name)] came back into range. Lock screen timer cancelled.")
                #endif
            }
        }
        scanBuffer[peripheral.identifier] = DiscoveredDevice(peripheral: peripheral, rssi: RSSI, lastSeen: Date())
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        #if DEBUG
        print("BluetoothManager: Peripheral explicitly connected: \(peripheral.name ?? "Unknown")")
        #endif
        DispatchQueue.main.async {
            self.lockScreenTimer?.invalidate()
            self.lockScreenTimer = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        #if DEBUG
        if let error = error {
            print("BluetoothManager: Peripheral explicitly disconnected with error: \(error.localizedDescription)")
        } else {
            print("BluetoothManager: Peripheral explicitly disconnected: \(peripheral.name ?? "Unknown")")
        }
        #endif
        handleLockScreenLogic(for: peripheral, reason: "explicit disconnect")
    }

    // MARK: - Scanning Logic
    func startScan() {
        // MODIFIED: Added guard to prevent scanning if paused
        guard !self.isPaused else {
            #if DEBUG
            print("BluetoothManager: startScan ignored because manager is paused.")
            #endif
            return
        }
        
        if centralManager.state == .poweredOn {
            let scanOptions: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
            centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
            #if DEBUG
            print("BluetoothManager: Started central scan with duplicates allowed.")
            #endif

            updateTimer?.invalidate()
            cleanupTimer?.invalidate()

            let newUpdateTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.processBufferedUpdates()
            }

            RunLoop.current.add(newUpdateTimer, forMode: .common)
            self.updateTimer = newUpdateTimer

            let newCleanupTimer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.removeStalePeripherals()
            }
            RunLoop.current.add(newCleanupTimer, forMode: .common)
            self.cleanupTimer = newCleanupTimer
        }
    }


    // MARK: - Device and Lock Management
    func connect(to peripheral: CBPeripheral) {
        #if DEBUG
        print("BluetoothManager: Connect \(peripheral.name ?? "Unknown").")
        #endif
        selectedPeripheralUUID = peripheral.identifier.uuidString
    }

    func disconnect() {
        selectedPeripheralUUID = ""
    }
    
    private func triggerLockScreen() {
        #if DEBUG
        print("BluetoothManager: LOCK SCREEN ACTION TRIGGERED.")
        #endif
        lockScreenAction?()
    }

    private func handleLockScreenLogic(for peripheral: CBPeripheral, reason: String) {
        // MODIFIED: Added guard to prevent lock logic if paused
        guard !self.isPaused else {
            #if DEBUG
            print("BluetoothManager: handleLockScreenLogic ignored because manager is paused.")
            #endif
            return
        }
        
        DispatchQueue.main.async {
            guard let settings = self.settings, settings.disconnectTimeout > 0, self.lockScreenTimer == nil else {
                return
            }
            self.lockScreenTimer?.invalidate()
            self.lockScreenTimer = Timer.scheduledTimer(withTimeInterval: settings.disconnectTimeout, repeats: false) { [weak self] _ in
                self?.triggerLockScreen()
            }
            #if DEBUG
            print("BluetoothManager: Lock screen timer started for [\(peripheral.name ?? "Unknown")] (\(settings.disconnectTimeout)s). Reason: \(reason).")
            #endif
        }
    }
    
    // MARK: - Timed Helper Functions
    private func processBufferedUpdates() {
        guard !self.isPaused else {
            #if DEBUG
            print("BluetoothManager: processBufferedUpdates ignored because manager is paused.")
            #endif
            return
        }
        #if DEBUG
        print("BluetoothManager: Update devices from UI list")
        #endif
        guard !scanBuffer.isEmpty else { return }
        DispatchQueue.main.async {
            self.scanBuffer.forEach { self.masterDeviceList[$0.key] = $0.value }
            self.scanBuffer.removeAll()
            #if DEBUG
            print("BluetoothManager: Update stale device from UI list")
            #endif
            let updatedPeripherals = Array(self.masterDeviceList.values).sorted { $0.peripheral.name ?? "" < $1.peripheral.name ?? "" }
            if self.discoveredPeripherals != updatedPeripherals {
                self.discoveredPeripherals = updatedPeripherals
            }
        }
    }

    private func removeStalePeripherals() {
        guard !self.isPaused else {
            #if DEBUG
            print("BluetoothManager: removeStalePeripherals ignored because manager is paused.")
            #endif
            return
        }
        
        let now = Date()
        var hasChangesForUI = false
        for (identifier, device) in masterDeviceList {
            if now.timeIntervalSince(device.lastSeen) > deviceTimeoutInterval {
                if identifier.uuidString == selectedPeripheralUUID {
                    handleLockScreenLogic(for: device.peripheral, reason: "device disappeared (timeout)")
                    continue
                }
                masterDeviceList.removeValue(forKey: identifier)
                hasChangesForUI = true
                #if DEBUG
                print("BluetoothManager: Removed stale device from UI list: \(device.peripheral.name ?? "Unknown")")
                #endif
            }
        }
        if hasChangesForUI {
            processBufferedUpdates()
        }
    }
    
    private func handleRssiChange(newRssi: NSNumber) {
        #if DEBUG
        print("BluetoothManager: Handling Rssi Change.")
        #endif
        guard !self.isPaused else { return }
        guard let settings = self.settings else { return }
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
                    print("BluetoothManager: Screen not woken because wakeOnAutoLockOnly is enabled and screen was not locked by app.")
                    #endif
                    return
                }
                #if DEBUG
                print("BluetoothManager: Screen turned on.")
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
