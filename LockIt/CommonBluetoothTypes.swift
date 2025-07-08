import CoreBluetooth

// Using a struct for discovered devices simplifies state management and improves performance with SwiftUI.
// Structs are value types, which means SwiftUI can easily track changes and update the view.
// Add Equatable conformance to allow for comparing lists and avoiding unnecessary UI updates.
struct DiscoveredDevice: Identifiable, Hashable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    var rssi: NSNumber // No need for @Published, as the whole struct will be replaced on update.

    init(peripheral: CBPeripheral, rssi: NSNumber) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.rssi = rssi
    }

    // Conformance to Hashable for checking containment and for use in ForEach.
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ScanReason {
    case listPopulation
    case appLaunch
}