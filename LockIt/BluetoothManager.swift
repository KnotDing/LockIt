import CoreBluetooth
import Combine
import AppKit
import Foundation

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    // MARK: - Published Properties
    @Published var discoveredPeripherals = [DiscoveredDevice]()
    @Published var selectedPeripheral: CBPeripheral? {
        didSet {
            settings?.selectedPeripheralUUID = selectedPeripheral?.identifier.uuidString
        }
    }
    @Published var rssi: NSNumber = 0
    @Published var isScanning = false
    @Published var isPaused: Bool = false // ADDED: The master pause state for the entire manager

    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var activeScanReasons: Set<ScanReason> = []
    private var scanBuffer = [UUID: DiscoveredDevice]()
    private var updateTimer: Timer?
    private var masterDeviceList = [UUID: DiscoveredDevice]()
    private var cleanupTimer: Timer?
    private let deviceTimeoutInterval: TimeInterval = 5.0
    private var lockScreenTimer: Timer?
    var isMenuActive: Bool = false
    // Dependencies
    var settings: AppSettings?
    var lockScreenAction: (() -> Void)?

    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func setup(settings: AppSettings) {
        self.settings = settings
        if let uuidString = settings.selectedPeripheralUUID, let uuid = UUID(uuidString: uuidString) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                self.selectedPeripheral = peripheral
                self.selectedPeripheral?.delegate = self
                #if DEBUG
                print("BluetoothManager: Restored selected peripheral: \(peripheral.name ?? "Unknown")")
                #endif
            }
        }
    }
    
    // ADDED: The main function to pause and resume all activities
    func togglePause() {
        isPaused.toggle()
        #if DEBUG
        print("BluetoothManager: Pause state toggled to \(isPaused)")
        #endif

        if isPaused {
            // --- PAUSING ---
            // Stop the main scan immediately
            centralManager.stopScan()
            isScanning = false // Update UI state

            // Invalidate all timers to halt all background activity
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
            // Restart the scanning process. This will re-initialize the necessary timers.
            // We ensure a clean start by clearing reasons first.
            activeScanReasons.removeAll()
            startScan(reason: .appLaunch)
        }
    }


    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            #if DEBUG
            print("CBCentralManager State: Powered On")
            #endif
            startScan(reason: .appLaunch)
        default:
            #if DEBUG
            print("CBCentralManager State: Not Powered On (\(central.state.rawValue))")
            #endif
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // MODIFIED: We still discover devices in the background, but timers won't process them if paused.
        guard !isPaused, let name = peripheral.name, !name.isEmpty else { return }

        if peripheral.identifier == selectedPeripheral?.identifier {
            DispatchQueue.main.async {
                self.rssi = RSSI
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
    func startScan(reason: ScanReason) {
        // MODIFIED: Added guard to prevent scanning if paused
        guard !isPaused else {
            #if DEBUG
            print("BluetoothManager: startScan ignored because manager is paused.")
            #endif
            return
        }
        
        if activeScanReasons.contains(reason) { return }
        activeScanReasons.insert(reason)

        if activeScanReasons.count == 1 && centralManager.state == .poweredOn {
            isScanning = true
            let scanOptions: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
            centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
            #if DEBUG
            print("BluetoothManager: Started central scan with duplicates allowed.")
            #endif

            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.processBufferedUpdates() }
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.removeStalePeripherals() }
        }
    }

    func stopScan(reason: ScanReason) {
        activeScanReasons.remove(reason)
        if activeScanReasons.isEmpty {
            centralManager.stopScan()
            isScanning = false
            updateTimer?.invalidate()
            updateTimer = nil
            cleanupTimer?.invalidate()
            cleanupTimer = nil
            processBufferedUpdates()
            #if DEBUG
            print("BluetoothManager: Stopped central scan. All reasons removed.")
            #endif
        }
    }

    // MARK: - Device and Lock Management
    func connect(to peripheral: CBPeripheral) {
        selectedPeripheral = peripheral
        selectedPeripheral?.delegate = self
    }

    func disconnect() {
        if let peripheral = selectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        selectedPeripheral = nil
        rssi = 0
    }
    
    private func triggerLockScreen() {
        #if DEBUG
        print("BluetoothManager: LOCK SCREEN ACTION TRIGGERED.")
        #endif
        lockScreenAction?()
    }

    private func handleLockScreenLogic(for peripheral: CBPeripheral, reason: String) {
        // MODIFIED: Added guard to prevent lock logic if paused
        guard !isPaused else {
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
        guard !isMenuActive else { return }
        guard !scanBuffer.isEmpty else { return }
        DispatchQueue.main.async {
            self.scanBuffer.forEach { self.masterDeviceList[$0.key] = $0.value }
            self.scanBuffer.removeAll()
            let updatedPeripherals = Array(self.masterDeviceList.values).sorted { $0.peripheral.name ?? "" < $1.peripheral.name ?? "" }
            if self.discoveredPeripherals != updatedPeripherals {
                self.discoveredPeripherals = updatedPeripherals
            }
        }
    }

    private func removeStalePeripherals() {
        let now = Date()
        var hasChangesForUI = false
        for (identifier, device) in masterDeviceList {
            if now.timeIntervalSince(device.lastSeen) > deviceTimeoutInterval {
                if identifier == selectedPeripheral?.identifier {
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
}
