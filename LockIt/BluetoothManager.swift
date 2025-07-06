import CoreBluetooth
import Combine
import AppKit // Import AppKit to manage the application's activation policy

import Foundation // Explicitly import Foundation
import CoreBluetooth
import Combine
import AppKit // Import AppKit to manage the application's activation policy


class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    private var centralManager: CBCentralManager!
    @Published var discoveredPeripherals = [DiscoveredDevice]() // Publish the array directly
    @Published var selectedPeripheral: CBPeripheral? {
        didSet {
            if let uuid = selectedPeripheral?.identifier {
                settings?.selectedPeripheralUUID = uuid.uuidString
            } else {
                settings?.selectedPeripheralUUID = nil
            }
        }
    }
    @Published var rssi: NSNumber = 0
    @Published var isScanning = false // This will now reflect if *any* scan is active

    private var activeScanReasons: Set<ScanReason> = [] // Track active scan reasons

    // Add a temporary dictionary to buffer scan results and a timer for batch updates.
    private var scanBuffer = [UUID: DiscoveredDevice]()
    private var updateTimer: Timer?
    private var masterDeviceList = [UUID: DiscoveredDevice]()

    @Published var isConnected: Bool = false // Connection status (still useful for lock logic)

    var settings: AppSettings? // Reference to AppSettings, now optional

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func setup(settings: AppSettings) {
        self.settings = settings
        // Attempt to restore selected peripheral after settings are available
        if let uuidString = settings.selectedPeripheralUUID, let uuid = UUID(uuidString: uuidString) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                self.selectedPeripheral = peripheral
                self.selectedPeripheral?.delegate = self
                print("BluetoothManager: Restored selected peripheral: \(peripheral.name ?? "Unknown") (ID: \(peripheral.identifier.uuidString))")
                // Automatically connect to the restored peripheral
                centralManager.connect(peripheral, options: nil)
                print("BluetoothManager: Attempting to reconnect to restored peripheral.")
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("CBCentralManager State: Powered On - Bluetooth is available and ready.")
        case .poweredOff:
            print("CBCentralManager State: Powered Off - Bluetooth is currently off.")
        case .resetting:
            print("CBCentralManager State: Resetting - Bluetooth is temporarily unavailable.")
        case .unauthorized:
            print("CBCentralManager State: Unauthorized - App is not authorized to use Bluetooth. Check Privacy & Security settings.")
        case .unsupported:
            print("CBCentralManager State: Unsupported - This device does not support Bluetooth Low Energy.")
        case .unknown:
            print("CBCentralManager State: Unknown - Bluetooth state is unknown. Waiting for update.")
        @unknown default:
            print("CBCentralManager State: An unknown state occurred.")
        }
    }

    func startScan(reason: ScanReason) {
        print("BluetoothManager: startScan called for reason: \(reason)")
        if activeScanReasons.contains(reason) { 
            print("BluetoothManager: Scan for reason \(reason) already active.")
            return 
        } // Already scanning for this reason

        activeScanReasons.insert(reason)

        // Only start actual CBCentralManager scan if this is the first reason
        if activeScanReasons.count == 1 {
            // For MenuBarExtra apps, we need to temporarily become a regular app
            // to be able to show the permission dialog.
            if centralManager.authorization == .notDetermined {
                // Bring app to front to show permission dialog
                NSApp.setActivationPolicy(.regular)
                // Revert back to accessory mode shortly after
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }

            guard centralManager.state == .poweredOn else {
                print("Cannot scan, Bluetooth is not powered on or authorized.")
                // Optionally, you could inform the user here.
                activeScanReasons.remove(reason) // Remove reason if scan can't start
                return
            }

            isScanning = true
            // Clear discovered peripherals only if scanning for list population
            if reason == .listPopulation {
                discoveredPeripherals.removeAll() // Clear the array
                masterDeviceList.removeAll() // Also clear the master list
                print("BluetoothManager: Cleared discoveredPeripherals and masterDeviceList for listPopulation.")
            }
            
            // Scan with CBCentralManagerScanOptionAllowDuplicatesKey to get frequent RSSI updates
            let scanOptions: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
            centralManager.scanForPeripherals(withServices: nil, options: scanOptions) // Scan continuously
            print("BluetoothManager: Started actual CBCentralManager scan.")

            // Start the timer to process buffered updates.
            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.processBufferedUpdates()
            }
        }
    }

    func stopScan(reason: ScanReason) {
        print("BluetoothManager: stopScan called for reason: \(reason)")
        if !activeScanReasons.contains(reason) { 
            print("BluetoothManager: Scan for reason \(reason) not active.")
            return 
        } // Not scanning for this reason

        activeScanReasons.remove(reason)

        // Only stop actual CBCentralManager scan if no other reasons remain
        if activeScanReasons.isEmpty {
            centralManager.stopScan()
            isScanning = false
            print("BluetoothManager: Stopped actual CBCentralManager scan. No active reasons remaining.")

            // Stop the timer and process any remaining buffered updates.
            updateTimer?.invalidate()
            updateTimer = nil
            processBufferedUpdates() // Process any remaining devices in the buffer
        } else {
            print("BluetoothManager: Scan reason \(reason) removed, but other reasons remain. Scan continues.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }

        // Update RSSI for the selected peripheral if it matches
        if peripheral.identifier == selectedPeripheral?.identifier {
            DispatchQueue.main.async {
                self.rssi = RSSI
                print("BluetoothManager: Updated selected peripheral RSSI via discovery: \(RSSI) dBm for \(peripheral.name ?? "Unknown") (ID: \(peripheral.identifier.uuidString))")
            }
        }

        // Buffer the discovered device instead of updating the published property directly.
        scanBuffer[peripheral.identifier] = DiscoveredDevice(peripheral: peripheral, rssi: RSSI)
    }

    func connect(to peripheral: CBPeripheral) {
        // stopScan() // No longer call stopScan here, let the onChange observers manage it
        selectedPeripheral = peripheral
        print("BluetoothManager: Selected peripheral set to: \(peripheral.name ?? "Unknown") (ID: \(peripheral.identifier.uuidString))")
        selectedPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = selectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BluetoothManager: Peripheral connected: \(peripheral.name ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnected = true // Update connection status
        }
        // No need to discover services or read RSSI here if we only care about discovery RSSI
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print("BluetoothManager: Peripheral disconnected with error: \(error.localizedDescription)")
        } else {
            print("BluetoothManager: Peripheral disconnected: \(peripheral.name ?? "Unknown")")
        }
        DispatchQueue.main.async {
            self.isConnected = false // Update connection status
        }
    }

    // This function is no longer used for real-time RSSI updates for selectedPeripheral
    func readRSSI() {
        print("BluetoothManager: readRSSI() called (no longer actively used for selected peripheral RSSI updates via polling).")
        // selectedPeripheral?.readRSSI() // Removed active polling
    }
    
    // This delegate method is still called if readRSSI() was used, but we're not using it for selectedPeripheral anymore
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            print("BluetoothManager: Error reading RSSI for \(peripheral.name ?? "Unknown"): \(error.localizedDescription)")
            return
        }
        print("BluetoothManager: Received RSSI update via readRSSI() (not used for selected peripheral display): \(RSSI) dBm")
        // self.rssi = RSSI // Do not update self.rssi here for selected peripheral
    }

    // Process the buffered scan results to update the UI in batches.
    private func processBufferedUpdates() {
        guard !scanBuffer.isEmpty else { return }

        DispatchQueue.main.async {
            // Merge the buffer into the master list.
            self.scanBuffer.forEach { self.masterDeviceList[$0.key] = $0.value }
            self.scanBuffer.removeAll()

            let updatedPeripherals = Array(self.masterDeviceList.values).sorted { $0.peripheral.name ?? "" < $1.peripheral.name ?? "" }

            // Only update the published property if the content has actually changed.
            if self.discoveredPeripherals != updatedPeripherals {
                self.discoveredPeripherals = updatedPeripherals
                print("BluetoothManager: Updated discoveredPeripherals with \(updatedPeripherals.count) devices from master list.")
            }
        }
    }
}
