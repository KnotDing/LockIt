## 🔒 LockIt - Your Smart Security Sidekick!

LockIt is a super cool macOS menu bar application designed to boost your device security by keeping an eye on your Bluetooth devices. 🕵️‍♂️ When you step away from your computer with your paired Bluetooth device (like your phone or smartwatch), LockIt can automatically lock your screen or kick off the screen saver. And guess what? It'll even magically turn your screen back on when you return! ✨ How awesome is that?!

**Pro Tip:** Guess what? This app was crafted by AI itself! 🤖

### 🌟 Key Features That'll Make You Smile

*   **Bluetooth Device Monitoring**: Constantly monitors the signal strength (RSSI) of your chosen Bluetooth device. Super precise, super reliable! 📡
*   **Automatic Lock/Screen Saver**: When your Bluetooth signal gets weak (you've wandered off!), LockIt will, after a short delay, automatically lock your macOS screen or start that snazzy screen saver. Your privacy is safe with us! 🛡️
*   **Smart Screen On**: Back at your desk? As soon as your device's signal is strong again, your screen will light up automatically, seamlessly picking up where you left off! 💡
*   **Configurable Thresholds**: You're in control! Customize the weak signal strength and screen-on signal strength thresholds to perfectly match your habits. 📏
*   **Flexible Timeouts**: Set those weak signal and disconnection timeouts just right to avoid any accidental triggers. Smooth sailing all the way! ⏳
*   **Launch at Login**: Set it and forget it! Opt to automatically launch LockIt when macOS starts, so it's always ready to protect your digital space. 💻
*   **Remembers Last Selected Device**: LockIt has a good memory! It'll recall your last connected Bluetooth device and try to hook up with it on the next launch. Easy peasy! 🧠
*   **Sleek Menu Bar Integration**: A tiny, elegant icon in your menu bar that's always there, showing you the status at a glance. Simple and effective! 🖥️
*   **Pause Media on Lock**: When you step away, LockIt doesn't just lock your screen; it can also pause your music or videos! Keep your privacy intact and avoid disturbing others. 🔇

### 🚀 How to Get Started (It's a Breeze!)

1.  **Build and Run**:
    *   Clone this treasure trove of a repository. ⬇️
    *   Open `LockIt.xcodeproj` in Xcode.
    *   Select the `LockIt` target and hit `Product > Build` (or `⌘B`) to compile.
    *   Once built, run the application (`Product > Run` or `⌘R`). Voila! The LockIt icon will pop up in your menu bar. 🎉

2.  **Configuration Fun**:
    *   Click that shiny LockIt icon in your menu bar. ✨
    *   From the dropdown, pick "Select Bluetooth Device" to find and connect your favorite gadget. 🔗
    *   Tweak the "Weak Signal Threshold", "Screen On Signal Threshold", "Weak Signal Timeout", and "Disconnect Timeout" settings to fit your unique needs. Make it yours! 💖
    *   Choose your preferred "Lock Mode": "Lock Screen" or "Start Screen Saver".
    *   Check "Launch at Login" to make LockIt your loyal macOS companion! ✅
    *   Check "Pause Media on Lock" to automatically pause your media when you lock your screen. 🎶

### 🛠️ Under the Hood (Tech Goodies!)

*   **Swift**: The primary language, making everything fast and secure! ⚡
*   **SwiftUI**: For that smooth, beautiful user interface. It's magic! 🎨
*   **CoreBluetooth**: The unsung hero behind all the Bluetooth wizardry. 🔗
*   **ServiceManagement**: The secret sauce for launching at login. ⚙️

### 🏗️ Build Instructions (For the Brave & Curious!)

Want to build it yourself? Awesome! Just make sure Xcode is installed on your machine.

```bash
# Clone the repo and embark on your coding adventure!
git clone https://github.com/your-username/LockIt.git
cd LockIt

# Build the project and witness the magic unfold!
xcodebuild build -configuration Release
```

After a successful build, you'll find `LockIt.app` chilling in the `build/Release/` directory. Go on, give it a whirl! 🥳

---

**Crafted by AI, just for you!** ✨

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.