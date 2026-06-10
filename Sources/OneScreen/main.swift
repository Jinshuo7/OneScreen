import AppKit
import Carbon
import CoreGraphics
import ServiceManagement

private enum PreferenceKey {
    static let blackoutShortcutKeyCode = "blackoutShortcutKeyCode"
    static let blackoutShortcutModifiers = "blackoutShortcutModifiers"
    static let clearShortcutKeyCode = "clearShortcutKeyCode"
    static let clearShortcutModifiers = "clearShortcutModifiers"
    static let preferredDisplayID = "preferredDisplayID"
    static let lastKeptDisplayID = "lastKeptDisplayID"
    static let overlayMode = "overlayMode"
    static let dimmingOpacity = "dimmingOpacity"
    static let hardwareBlackoutEnabled = "hardwareBlackoutEnabled"
    static let hasSeenOnboarding = "hasSeenOnboarding"
}

enum OverlayMode: String {
    case blackout
    case dim
}

private struct HardwareDisplayTarget {
    let displayID: CGDirectDisplayID
    let name: String
}

private final class BetterDisplayHardwareController {
    static let shared = BetterDisplayHardwareController()

    private let executablePath = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
    private let queue = DispatchQueue(label: "local.onescreen.blackout.betterdisplay")
    private var savedBrightness: [CGDirectDisplayID: Double] = [:]

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    func blackOut(_ targets: [HardwareDisplayTarget]) {
        guard isAvailable, !targets.isEmpty else { return }

        queue.async { [executablePath] in
            for target in targets {
                if self.savedBrightness[target.displayID] == nil,
                   let currentBrightness = self.readHardwareBrightness(displayID: target.displayID, executablePath: executablePath) {
                    self.savedBrightness[target.displayID] = currentBrightness
                }

                _ = self.runBetterDisplay(
                    arguments: ["set", "-displayID=\(target.displayID)", "-hardwareBrightness=0"],
                    executablePath: executablePath
                )
            }
        }
    }

    func restore(wait: Bool = false) {
        guard isAvailable else { return }

        let work = { [executablePath] in
            let valuesToRestore = self.savedBrightness
            self.savedBrightness.removeAll()

            for (displayID, brightness) in valuesToRestore {
                _ = self.runBetterDisplay(
                    arguments: ["set", "-displayID=\(displayID)", "-hardwareBrightness=\(brightness)"],
                    executablePath: executablePath
                )
            }
        }

        if wait {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    private func readHardwareBrightness(displayID: CGDirectDisplayID, executablePath: String) -> Double? {
        let output = runBetterDisplay(
            arguments: ["get", "-displayID=\(displayID)", "-hardwareBrightness"],
            executablePath: executablePath
        )
        guard let firstLine = output?.split(whereSeparator: \.isNewline).first else { return nil }
        return Double(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func runBetterDisplay(arguments: [String], executablePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

enum HotKeyID: UInt32 {
    case blackout = 1
    case clear = 2
}

struct HotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        "\(modifierString)\(keyString(for: keyCode))"
    }

    private var modifierString: String {
        var parts: [String] = []
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { parts.append("Control") }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { parts.append("Option") }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { parts.append("Shift") }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { parts.append("Command") }
        return parts.isEmpty ? "" : parts.joined(separator: "-") + "-"
    }
}

private func keyString(for keyCode: UInt32) -> String {
    let names: [UInt32: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
    if let name = names[keyCode] {
        return name
    }
    return String(keyCode)
}

private func carbonModifiers(from cocoaModifiers: UInt32) -> UInt32 {
    var result: UInt32 = 0
    if cocoaModifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { result |= UInt32(cmdKey) }
    if cocoaModifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { result |= UInt32(optionKey) }
    if cocoaModifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { result |= UInt32(controlKey) }
    if cocoaModifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { result |= UInt32(shiftKey) }
    return result
}

private func normalizedModifiers(from event: NSEvent) -> UInt32 {
    let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    return UInt32(event.modifierFlags.intersection(relevant).rawValue)
}

@MainActor
final class DisplayOption {
    let id: CGDirectDisplayID
    let screen: NSScreen
    let name: String
    let frame: NSRect

    init(screen: NSScreen, index: Int) {
        self.screen = screen
        self.id = screen.displayID
        self.name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
        self.frame = screen.frame
    }

    var menuTitle: String {
        "\(name) (\(Int(frame.width)) x \(Int(frame.height)))"
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

@MainActor
final class BlackoutWindow: NSWindow {
    private var blackoutView: BlackoutView?

    init(screen: NSScreen, opacity: Double) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: true)
        isReleasedWhenClosed = false
        backgroundColor = NSColor.black.withAlphaComponent(opacity)
        isOpaque = opacity >= 0.995
        hasShadow = false
        animationBehavior = .none
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = BlackoutView(frame: NSRect(origin: .zero, size: screen.frame.size), opacity: opacity)
        blackoutView = view
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateOpacity(_ opacity: Double) {
        backgroundColor = NSColor.black.withAlphaComponent(opacity)
        isOpaque = opacity >= 0.995
        blackoutView?.opacity = opacity
    }
}

@MainActor
final class BlackoutView: NSView {
    var opacity: Double {
        didSet {
            needsDisplay = true
        }
    }

    init(frame frameRect: NSRect, opacity: Double) {
        self.opacity = opacity
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(opacity).setFill()
        dirtyRect.fill()
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let blackoutShortcutButton = NSButton()
    private let clearShortcutButton = NSButton()
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let preferredDisplayPopup = NSPopUpButton()
    private let overlayModeControl = NSSegmentedControl(labels: ["Black out", "Dim"], trackingMode: .selectOne, target: nil, action: nil)
    private let dimmingSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 1, target: nil, action: nil)
    private let dimmingValueLabel = NSTextField(labelWithString: "100%")
    private let hardwareBlackoutButton = NSButton(checkboxWithTitle: "Use BetterDisplay hardware blackout", target: nil, action: nil)
    private let hardwareStatusLabel = NSTextField(labelWithString: "")
    private var recordingTarget: HotKeyID?
    private var keyMonitor: Any?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OneScreen Preferences"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        reload()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(row(label: "Blackout shortcut", control: blackoutShortcutButton))
        root.addArrangedSubview(row(label: "Clear shortcut", control: clearShortcutButton))
        root.addArrangedSubview(row(label: "Blackout keeps", control: preferredDisplayPopup))
        root.addArrangedSubview(row(label: "Mode", control: overlayModeControl))
        root.addArrangedSubview(row(label: "Dim amount", control: dimmingControl()))
        root.addArrangedSubview(row(label: "External displays", control: hardwareBlackoutControl()))
        root.addArrangedSubview(launchAtLoginButton)

        blackoutShortcutButton.target = self
        blackoutShortcutButton.action = #selector(recordBlackoutShortcut)
        blackoutShortcutButton.bezelStyle = .rounded

        clearShortcutButton.target = self
        clearShortcutButton.action = #selector(recordClearShortcut)
        clearShortcutButton.bezelStyle = .rounded

        preferredDisplayPopup.target = self
        preferredDisplayPopup.action = #selector(preferredDisplayChanged)

        overlayModeControl.target = self
        overlayModeControl.action = #selector(overlayModeChanged)

        dimmingSlider.target = self
        dimmingSlider.action = #selector(dimmingChanged)
        dimmingSlider.isContinuous = false
        dimmingSlider.numberOfTickMarks = 4
        dimmingSlider.allowsTickMarkValuesOnly = false

        hardwareBlackoutButton.target = self
        hardwareBlackoutButton.action = #selector(hardwareBlackoutChanged)

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let text = NSTextField(labelWithString: label)
        text.alignment = .right
        text.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let stack = NSStackView(views: [text, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        return stack
    }

    private func hardwareBlackoutControl() -> NSStackView {
        hardwareStatusLabel.font = .systemFont(ofSize: 11)
        hardwareStatusLabel.textColor = .secondaryLabelColor
        hardwareStatusLabel.lineBreakMode = .byWordWrapping
        hardwareStatusLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [hardwareBlackoutButton, hardwareStatusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        hardwareBlackoutButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        hardwareStatusLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return stack
    }

    private func dimmingControl() -> NSStackView {
        dimmingValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = NSStackView(views: [dimmingSlider, dimmingValueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        dimmingSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        return stack
    }

    func reload() {
        blackoutShortcutButton.title = AppDelegate.shared?.blackoutHotKey.displayString ?? "Not set"
        clearShortcutButton.title = AppDelegate.shared?.clearHotKey.displayString ?? "Not set"
        let opacity = AppDelegate.shared?.dimmingOpacity ?? 1
        dimmingSlider.doubleValue = opacity
        dimmingValueLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
        let mode = AppDelegate.shared?.overlayMode ?? .blackout
        overlayModeControl.selectedSegment = mode == .blackout ? 0 : 1
        dimmingSlider.isEnabled = mode == .dim
        dimmingValueLabel.textColor = mode == .dim ? .labelColor : .secondaryLabelColor
        hardwareBlackoutButton.state = (AppDelegate.shared?.hardwareBlackoutEnabled ?? true) ? .on : .off
        hardwareBlackoutButton.isEnabled = BetterDisplayHardwareController.shared.isAvailable
        hardwareStatusLabel.stringValue = BetterDisplayHardwareController.shared.isAvailable
            ? "Black out mode also lowers external display hardware brightness to zero."
            : "BetterDisplay is not installed in /Applications, so OneScreen will use the black overlay only."
        reloadDisplayPopup()

        if #available(macOS 13.0, *) {
            launchAtLoginButton.isEnabled = true
            launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginButton.isEnabled = false
            launchAtLoginButton.title = "Launch at login requires macOS 13+"
        }
    }

    private func reloadDisplayPopup() {
        preferredDisplayPopup.removeAllItems()
        preferredDisplayPopup.addItem(withTitle: "Last selected display")
        preferredDisplayPopup.lastItem?.representedObject = NSNumber(value: UInt32.max)

        for display in AppDelegate.shared?.currentDisplays ?? [] {
            preferredDisplayPopup.addItem(withTitle: display.menuTitle)
            preferredDisplayPopup.lastItem?.representedObject = NSNumber(value: display.id)
        }

        let preferredID = UserDefaults.standard.object(forKey: PreferenceKey.preferredDisplayID) as? UInt32
        let selectedIndex = preferredDisplayPopup.itemArray.firstIndex { item in
            guard let number = item.representedObject as? NSNumber else { return false }
            if preferredID == nil {
                return number.uint32Value == UInt32.max
            }
            return number.uint32Value == preferredID
        } ?? 0
        preferredDisplayPopup.selectItem(at: selectedIndex)
    }

    @objc private func recordBlackoutShortcut() {
        beginRecording(.blackout)
    }

    @objc private func recordClearShortcut() {
        beginRecording(.clear)
    }

    private func beginRecording(_ target: HotKeyID) {
        recordingTarget = target
        if target == .blackout {
            blackoutShortcutButton.title = "Press shortcut..."
        } else {
            clearShortcutButton.title = "Press shortcut..."
        }

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        guard let recordingTarget else { return }
        let hotKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: normalizedModifiers(from: event))
        AppDelegate.shared?.setHotKey(hotKey, for: recordingTarget)
        stopRecording()
        reload()
    }

    private func stopRecording() {
        recordingTarget = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    @objc private func preferredDisplayChanged() {
        guard let number = preferredDisplayPopup.selectedItem?.representedObject as? NSNumber else { return }
        if number.uint32Value == UInt32.max {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.preferredDisplayID)
        } else {
            UserDefaults.standard.set(number.uint32Value, forKey: PreferenceKey.preferredDisplayID)
        }
    }

    @objc private func dimmingChanged() {
        let opacity = dimmingSlider.doubleValue
        dimmingValueLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
        AppDelegate.shared?.setDimmingOpacity(opacity)
    }

    @objc private func overlayModeChanged() {
        let mode: OverlayMode = overlayModeControl.selectedSegment == 0 ? .blackout : .dim
        AppDelegate.shared?.setOverlayMode(mode)
        reload()
    }

    @objc private func hardwareBlackoutChanged() {
        AppDelegate.shared?.setHardwareBlackoutEnabled(hardwareBlackoutButton.state == .on)
        reload()
    }

    @objc private func launchAtLoginChanged() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLoginButton.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
            NSSound.beep()
        }
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OneScreen"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Keep one display. Dim the rest.")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
        OneScreen lives in the menu bar. Choose the display you want to keep active; every other display gets a black or dim overlay.

        To restore, press Esc, use your Clear shortcut, or choose Clear Blackout from the menu.

        A black overlay does not turn off a monitor backlight. Some external LCD displays may still glow at black; lower the dim amount if you want to keep them usable.
        """)
        body.textColor = .secondaryLabelColor

        let openPreferencesButton = NSButton(title: "Open Preferences", target: self, action: #selector(openPreferences))
        openPreferencesButton.bezelStyle = .rounded

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [openPreferencesButton, doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        root.addArrangedSubview(title)
        root.addArrangedSubview(body)
        root.addArrangedSubview(buttons)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func openPreferences() {
        AppDelegate.shared?.showPreferences()
        close()
    }

    @objc private func done() {
        close()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static weak var shared: AppDelegate?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var displays: [DisplayOption] = []
    private var blackoutWindows: [CGDirectDisplayID: BlackoutWindow] = [:]
    private var retiredBlackoutWindows: [BlackoutWindow] = []
    private var activeKeptDisplayID: CGDirectDisplayID?
    private var escapeMonitor: Any?
    private var blackoutHotKeyRef: EventHotKeyRef?
    private var clearHotKeyRef: EventHotKeyRef?
    private var preferencesWindowController: PreferencesWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var hotKeyHandlerInstalled = false

    var currentDisplays: [DisplayOption] { displays }

    var overlayMode: OverlayMode {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKey.overlayMode) ?? OverlayMode.blackout.rawValue
        return OverlayMode(rawValue: rawValue) ?? .blackout
    }

    var dimmingOpacity: Double {
        let value = UserDefaults.standard.double(forKey: PreferenceKey.dimmingOpacity)
        return min(1, max(0.25, value))
    }

    var hardwareBlackoutEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.hardwareBlackoutEnabled)
    }

    private var overlayOpacity: Double {
        overlayMode == .blackout ? 1.0 : dimmingOpacity
    }

    var blackoutHotKey: HotKey {
        HotKey(
            keyCode: UInt32(UserDefaults.standard.integer(forKey: PreferenceKey.blackoutShortcutKeyCode)),
            modifiers: UInt32(UserDefaults.standard.integer(forKey: PreferenceKey.blackoutShortcutModifiers))
        )
    }

    var clearHotKey: HotKey {
        HotKey(
            keyCode: UInt32(UserDefaults.standard.integer(forKey: PreferenceKey.clearShortcutKeyCode)),
            modifiers: UInt32(UserDefaults.standard.integer(forKey: PreferenceKey.clearShortcutModifiers))
        )
    }

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerDefaultPreferences()
        configureStatusItem()
        refreshDisplays()
        installHotKeyHandler()
        registerHotKeys()
        showOnboardingIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKeys()
        clearBlackoutForTermination()
    }

    private func registerDefaultPreferences() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.blackoutShortcutKeyCode: 11,
            PreferenceKey.blackoutShortcutModifiers: UInt32(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue),
            PreferenceKey.clearShortcutKeyCode: 8,
            PreferenceKey.clearShortcutModifiers: UInt32(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue),
            PreferenceKey.overlayMode: OverlayMode.blackout.rawValue,
            PreferenceKey.dimmingOpacity: 1.0,
            PreferenceKey.hardwareBlackoutEnabled: true
        ])
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "OneScreen") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
            } else {
                button.title = "■"
            }
            button.toolTip = "OneScreen: choose the display to keep active"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if displays.isEmpty {
            let emptyItem = NSMenuItem(title: "No displays found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for display in displays {
                let item = NSMenuItem(title: display.menuTitle, action: #selector(keepDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: display.id)
                item.state = activeKeptDisplayID == display.id ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Blackout", action: #selector(clearBlackoutAction), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !blackoutWindows.isEmpty
        menu.addItem(clearItem)

        let refreshItem = NSMenuItem(title: "Refresh Displays", action: #selector(refreshDisplaysAction), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let onboardingItem = NSMenuItem(title: "Getting Started", action: #selector(showOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit OneScreen", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusTitle()
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            DisplayOption(screen: screen, index: index)
        }

        if let activeKeptDisplayID, !displays.contains(where: { $0.id == activeKeptDisplayID }) {
            clearBlackout()
        }

        preferencesWindowController?.reload()
        rebuildMenu()
    }

    @objc private func screenParametersDidChange() {
        clearBlackout()
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplays()
        }
    }

    @objc private func keepDisplay(_ sender: NSMenuItem) {
        guard
            let number = sender.representedObject as? NSNumber,
            let keptDisplay = displays.first(where: { $0.id == number.uint32Value })
        else {
            refreshDisplays()
            return
        }

        keepOnly(display: keptDisplay)
    }

    @objc private func clearBlackoutAction() {
        clearBlackout()
    }

    @objc private func refreshDisplaysAction() {
        clearBlackout()
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplays()
        }
    }

    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: PreferenceKey.hasSeenOnboarding) else { return }
        UserDefaults.standard.set(true, forKey: PreferenceKey.hasSeenOnboarding)
        DispatchQueue.main.async { [weak self] in
            self?.showOnboarding()
        }
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController()
        }
        onboardingWindowController?.showWindow(nil)
    }

    @objc private func quitAction() {
        clearBlackoutForTermination()
        NSApp.terminate(nil)
    }

    private func keepOnly(display keptDisplay: DisplayOption) {
        if activeKeptDisplayID == keptDisplay.id, !blackoutWindows.isEmpty {
            return
        }

        clearBlackout(rebuildMenuAfterClear: false)
        activeKeptDisplayID = keptDisplay.id
        UserDefaults.standard.set(keptDisplay.id, forKey: PreferenceKey.lastKeptDisplayID)

        DispatchQueue.main.async { [weak self] in
            self?.blackOutOtherDisplays(keeping: keptDisplay.id)
        }
    }

    private func blackOutOtherDisplays(keeping keptDisplayID: CGDirectDisplayID) {
        guard activeKeptDisplayID == keptDisplayID else { return }

        var hardwareTargets: [HardwareDisplayTarget] = []
        for display in displays where display.id != keptDisplayID {
            hardwareTargets.append(HardwareDisplayTarget(displayID: display.id, name: display.name))
            let blackoutWindow = BlackoutWindow(screen: display.screen, opacity: overlayOpacity)
            blackoutWindows[display.id] = blackoutWindow
            blackoutWindow.orderFrontRegardless()
        }

        if overlayMode == .blackout, hardwareBlackoutEnabled {
            BetterDisplayHardwareController.shared.blackOut(hardwareTargets)
        }

        installEscapeMonitor()
        rebuildMenu()
    }

    private func keepDisplayForBlackoutShortcut() {
        if displays.isEmpty {
            refreshDisplays()
        }

        let preferredID = UserDefaults.standard.object(forKey: PreferenceKey.preferredDisplayID) as? UInt32
        let lastID = UserDefaults.standard.object(forKey: PreferenceKey.lastKeptDisplayID) as? UInt32
        let targetID = preferredID ?? lastID ?? NSScreen.main?.displayID

        if let targetID, let display = displays.first(where: { $0.id == targetID }) {
            keepOnly(display: display)
        } else if let mainDisplay = displays.first(where: { $0.screen == NSScreen.main }) ?? displays.first {
            keepOnly(display: mainDisplay)
        }
    }

    func clearBlackout(rebuildMenuAfterClear: Bool = true) {
        activeKeptDisplayID = nil
        BetterDisplayHardwareController.shared.restore()
        let windowsToRetire = Array(blackoutWindows.values)
        windowsToRetire.forEach { $0.orderOut(nil) }
        retiredBlackoutWindows.append(contentsOf: windowsToRetire)
        blackoutWindows.removeAll()
        removeEscapeMonitor()

        if rebuildMenuAfterClear {
            rebuildMenu()
        }

        DispatchQueue.main.async { [weak self] in
            self?.retiredBlackoutWindows.removeAll()
        }
    }

    private func clearBlackoutForTermination() {
        activeKeptDisplayID = nil
        removeEscapeMonitor()
        BetterDisplayHardwareController.shared.restore(wait: true)

        blackoutWindows.values.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        blackoutWindows.removeAll()

        retiredBlackoutWindows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        retiredBlackoutWindows.removeAll()
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.clearBlackout()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    func setHotKey(_ hotKey: HotKey, for id: HotKeyID) {
        switch id {
        case .blackout:
            UserDefaults.standard.set(hotKey.keyCode, forKey: PreferenceKey.blackoutShortcutKeyCode)
            UserDefaults.standard.set(hotKey.modifiers, forKey: PreferenceKey.blackoutShortcutModifiers)
        case .clear:
            UserDefaults.standard.set(hotKey.keyCode, forKey: PreferenceKey.clearShortcutKeyCode)
            UserDefaults.standard.set(hotKey.modifiers, forKey: PreferenceKey.clearShortcutModifiers)
        }
        registerHotKeys()
    }

    func setDimmingOpacity(_ opacity: Double) {
        UserDefaults.standard.set(min(1, max(0.25, opacity)), forKey: PreferenceKey.dimmingOpacity)
        applyCurrentOverlayOpacity()
    }

    func setOverlayMode(_ mode: OverlayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: PreferenceKey.overlayMode)
        applyCurrentOverlayOpacity()
        updateHardwareBlackoutForCurrentMode()
    }

    func setHardwareBlackoutEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.hardwareBlackoutEnabled)
        updateHardwareBlackoutForCurrentMode()
    }

    private func applyCurrentOverlayOpacity() {
        let opacity = overlayOpacity
        for window in blackoutWindows.values {
            window.updateOpacity(opacity)
        }
    }

    private func updateHardwareBlackoutForCurrentMode() {
        guard let activeKeptDisplayID, !blackoutWindows.isEmpty else {
            BetterDisplayHardwareController.shared.restore()
            return
        }

        if overlayMode == .blackout, hardwareBlackoutEnabled {
            let targets = displays
                .filter { $0.id != activeKeptDisplayID }
                .map { HardwareDisplayTarget(displayID: $0.id, name: $0.name) }
            BetterDisplayHardwareController.shared.blackOut(targets)
        } else {
            BetterDisplayHardwareController.shared.restore()
        }
    }

    private func installHotKeyHandler() {
        guard !hotKeyHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            Task { @MainActor in
                AppDelegate.shared?.handleHotKey(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
        hotKeyHandlerInstalled = true
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        blackoutHotKeyRef = registerHotKey(blackoutHotKey, id: .blackout)
        clearHotKeyRef = registerHotKey(clearHotKey, id: .clear)
    }

    private func registerHotKey(_ hotKey: HotKey, id: HotKeyID) -> EventHotKeyRef? {
        guard hotKey.keyCode > 0, hotKey.modifiers > 0 else { return nil }
        var ref: EventHotKeyRef?
        let signature = OSType(UInt32(UInt8(ascii: "O")) << 24 | UInt32(UInt8(ascii: "S")) << 16 | UInt32(UInt8(ascii: "C")) << 8 | UInt32(UInt8(ascii: "R")))
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            carbonModifiers(from: hotKey.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }

    private func unregisterHotKeys() {
        if let blackoutHotKeyRef {
            UnregisterEventHotKey(blackoutHotKeyRef)
            self.blackoutHotKeyRef = nil
        }
        if let clearHotKeyRef {
            UnregisterEventHotKey(clearHotKeyRef)
            self.clearHotKeyRef = nil
        }
    }

    func handleHotKey(id: UInt32) {
        guard let hotKeyID = HotKeyID(rawValue: id) else { return }
        switch hotKeyID {
        case .blackout:
            keepDisplayForBlackoutShortcut()
        case .clear:
            clearBlackout()
        }
    }

    private func updateStatusTitle() {
        if let button = statusItem.button, let activeKeptDisplayID, let keptDisplay = displays.first(where: { $0.id == activeKeptDisplayID }) {
            button.toolTip = "OneScreen: keeping \(keptDisplay.menuTitle)"
        } else {
            statusItem.button?.toolTip = "OneScreen: choose the display to keep active"
        }
    }
}

@MainActor
private var retainedAppDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedAppDelegate = delegate
    app.delegate = delegate
    app.run()
}
