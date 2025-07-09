import CoreBluetooth

// Using a struct for discovered devices simplifies state management and improves performance with SwiftUI.
// Structs are value types, which means SwiftUI can easily track changes and update the view.
// Add Equatable conformance to allow for comparing lists and avoiding unnecessary UI updates.
struct DiscoveredDevice: Equatable, Identifiable {
    
    // MARK: - Properties
    
    // Use the peripheral's identifier for the `Identifiable` protocol.
    let id: UUID
    
    // The underlying CBPeripheral object from CoreBluetooth.
    let peripheral: CBPeripheral
    
    // The last known signal strength (RSSI) of the device.
    var rssi: NSNumber
    
    // The timestamp of when the device was last seen during a scan.
    // This is crucial for the timeout mechanism.
    var lastSeen: Date
    
    // MARK: - Initializer
    
    // A custom initializer to create a DiscoveredDevice instance.
    // It automatically sets the `id` from the peripheral and allows setting `lastSeen`.
    init(peripheral: CBPeripheral, rssi: NSNumber, lastSeen: Date = Date()) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.rssi = rssi
        self.lastSeen = lastSeen // <-- 这个初始化器现在认识 'lastSeen' 了
    }
    
    // MARK: - Equatable Conformance
    
    // Define how to check if two DiscoveredDevice instances are equal.
    // We check if the ID and RSSI are the same. This helps SwiftUI
    // to avoid unnecessary UI redraws if the data hasn't changed.
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.id == rhs.id && lhs.rssi == rhs.rssi
    }
}

enum ScanReason {
    case listPopulation
    case appLaunch
}
