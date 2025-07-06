# LockIt

LockIt is a macOS menu bar application designed to enhance your device security by monitoring the signal strength of your Bluetooth devices. When you move away from your computer with a paired Bluetooth device (like your phone or smartwatch), LockIt can automatically lock your screen or start the screen saver, and then automatically turn on the screen when you return.

**Note:** This application was written by AI.

## Key Features

*   **Bluetooth Device Monitoring**: Continuously monitors the signal strength (RSSI) of your selected Bluetooth device.
*   **Automatic Lock/Screen Saver**: Automatically locks your macOS screen or starts the screen saver when the Bluetooth signal strength drops below a preset threshold for a continuous period.
*   **Automatic Screen On**: Automatically turns on the screen when the Bluetooth signal strength returns above a preset threshold.
*   **Configurable Thresholds**: You can customize the weak signal strength threshold and the screen-on signal strength threshold.
*   **Configurable Timeouts**: Set timeouts for weak signal and disconnection to prevent false triggers.
*   **Launch at Login**: Option to automatically launch the application when macOS logs in.
*   **Remember Last Selected Device**: The application remembers your last selected Bluetooth device and attempts to reconnect on next launch.
*   **Menu Bar Integration**: Runs as a menu bar application, providing a clean user interface and status display.

## How to Use

1.  **Build and Run**:
    *   Clone this repository.
    *   Open `LockIt.xcodeproj` in Xcode.
    *   Select the `LockIt` target and build the project (`Product > Build` or `⌘B`).
    *   Run the application (`Product > Run` or `⌘R`). The application will appear in your menu bar.

2.  **Configuration**:
    *   Click the LockIt icon in the menu bar.
    *   From the dropdown menu, select "Select Bluetooth Device" to find and connect your Bluetooth device.
    *   Configure "Weak Signal Threshold", "Screen On Signal Threshold", "Weak Signal Timeout", and "Disconnect Timeout" to suit your needs.
    *   Choose "Lock Mode" as either "Lock Screen" or "Start Screen Saver".
    *   Check "Launch at Login" to automatically start LockIt when you log in.

## Technology Stack

*   **Swift**: The primary programming language.
*   **SwiftUI**: Used for building the user interface.
*   **CoreBluetooth**: For interacting with Bluetooth devices.
*   **ServiceManagement**: For managing the launch at login feature.

## Build Instructions

To build this project from source, ensure you have Xcode installed.

```bash
# Clone the repository
git clone https://github.com/your-username/LockIt.git
cd LockIt

# Build the project
xcodebuild build -configuration Release
```

After a successful build, you can find `LockIt.app` in the `build/Release/` directory.

---

**Written by AI**
