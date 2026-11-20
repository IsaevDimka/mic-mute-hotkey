import Cocoa
import CoreAudio
import Carbon
import ApplicationServices
import ServiceManagement

// MARK: - Глобальное состояние

var debugKeyLogging = UserDefaults.standard.bool(forKey: "DebugKeys")
var captureInProgress = false

let secondaryFnMask: UInt32 = 1 << 23  // физическая клавиша fn; не считаем модификатором

func logKeyLine(_ s: String) {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/micmute-keys.log")
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    let line = "\(fmt.string(from: Date())) \(s)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(data)
        try? h.close()
    } else {
        try? data.write(to: url)
    }
}

// MARK: - CoreAudio

enum Mic {
    static func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        guard err == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func muteAddr() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volumeAddr() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func hasMuteProperty(_ device: AudioDeviceID) -> Bool {
        var addr = muteAddr()
        return AudioObjectHasProperty(device, &addr)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddr()
        let err = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return err == noErr && value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        var addr = muteAddr()
        let err = AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return err == noErr
    }

    static func inputVolume(_ device: AudioDeviceID) -> Float {
        var value: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = volumeAddr()
        let err = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return err == noErr ? value : 1.0
    }

    static func setInputVolume(_ volume: Float, device: AudioDeviceID) {
        var value = volume
        var addr = volumeAddr()
        AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
    }

    static func deviceUID(_ device: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return err == noErr ? (value as String? ?? "unknown") : "unknown"
    }
}

// MARK: - Слушатель изменений (нативный мьют, смена устройства)

final class MicMonitor {
    static let shared = MicMonitor()
    var onChange: (() -> Void)?

    private var device: AudioDeviceID?
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private lazy var listener: AudioObjectPropertyListenerProc = { _, _, _, _ in
        DispatchQueue.main.async {
            MicMonitor.shared.restart()
            MicMonitor.shared.onChange?()
        }
        return noErr
    }

    func start() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListener(systemObject, &addr, listener, nil)
        restart()
    }

    func restart() {
        if let old = device, Mic.hasMuteProperty(old) {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(old, &addr, listener, nil)
        }
        device = Mic.defaultInputDevice()
        if let new = device, Mic.hasMuteProperty(new) {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListener(new, &addr, listener, nil)
        }
    }
}

// MARK: - Toggle logic

func toggleMuteState() -> Bool? {
    guard let device = Mic.defaultInputDevice() else { return nil }

    if Mic.hasMuteProperty(device) {
        let newState = !Mic.isMuted(device)
        return Mic.setMuted(newState, device: device) ? newState : nil
    }

    let defaults = UserDefaults.standard
    let key = "SavedVolume_\(Mic.deviceUID(device))"
    let current = Mic.inputVolume(device)
    if current == 0, let saved = defaults.object(forKey: key) as? Float {
        Mic.setInputVolume(saved, device: device)
        defaults.removeObject(forKey: key)
        return false
    } else if current > 0 {
        defaults.set(current, forKey: key)
        Mic.setInputVolume(0, device: device)
        return true
    }
    return nil
}

func readMuteState() -> Bool? {
    guard let device = Mic.defaultInputDevice() else { return nil }
    if Mic.hasMuteProperty(device) {
        return Mic.isMuted(device)
    }
    return Mic.inputVolume(device) == 0
}

// MARK: - CLI

let args = Set(CommandLine.arguments.dropFirst())
if args.contains("--status") {
    if let muted = readMuteState() {
        print(muted ? "muted" : "unmuted")
        exit(muted ? 0 : 1)
    }
    print("unknown")
    exit(2)
}
if args.contains("--toggle") {
    if let muted = toggleMuteState() {
        print(muted ? "muted" : "unmuted")
        exit(0)
    }
    print("error")
    exit(2)
}

// MARK: - Клавиша: хранение, имена, конвертация модификаторов

let defaultsHotKeyKeyCode = "HotKeyKeyCode"
let defaultsHotKeyModifiers = "HotKeyModifiers"

func currentKeyCombo() -> (code: UInt32, mods: UInt32) {
    let defaults = UserDefaults.standard
    let code = UInt32((defaults.object(forKey: defaultsHotKeyKeyCode) as? Int) ?? 96)   // 96 = F5
    let mods = UInt32((defaults.object(forKey: defaultsHotKeyModifiers) as? Int) ?? 0)
    return (code, mods)
}

func toCarbonMask(_ cg: UInt32) -> UInt32 {
    var r: UInt32 = 0
    if cg & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { r |= UInt32(cmdKey) }
    if cg & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { r |= UInt32(optionKey) }
    if cg & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { r |= UInt32(shiftKey) }
    if cg & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { r |= UInt32(controlKey) }
    return r
}

func toCGMask(_ carbon: UInt32) -> UInt32 {
    var r: UInt32 = 0
    if carbon & UInt32(cmdKey) != 0 { r |= UInt32(NSEvent.ModifierFlags.command.rawValue) }
    if carbon & UInt32(optionKey) != 0 { r |= UInt32(NSEvent.ModifierFlags.option.rawValue) }
    if carbon & UInt32(shiftKey) != 0 { r |= UInt32(NSEvent.ModifierFlags.shift.rawValue) }
    if carbon & UInt32(controlKey) != 0 { r |= UInt32(NSEvent.ModifierFlags.control.rawValue) }
    return r
}

func modifierName(_ mods: UInt32) -> String {
    var s = ""
    if mods & UInt32(controlKey) != 0 { s += "⌃" }
    if mods & UInt32(optionKey) != 0 { s += "⌥" }
    if mods & UInt32(shiftKey) != 0 { s += "⇧" }
    if mods & UInt32(cmdKey) != 0 { s += "⌘" }
    return s
}

func keyName(forKeyCode keyCode: UInt16) -> String {
    let special: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        36: "Return", 48: "Tab", 49: "Пробел", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        116: "Page Up", 121: "Page Down", 115: "Home", 119: "End",
    ]
    if let name = special[keyCode] { return name }

    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "Key\(keyCode)"
    }
    let data = unsafeBitCast(layoutData, to: CFData.self)
    let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
    var deadKeyState = UInt32(0)
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0
    UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                   0, &deadKeyState, 4, &length, &chars)
    if length > 0 {
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
    return "Key\(keyCode)"
}

func currentKeyName() -> String {
    let combo = currentKeyCombo()
    return modifierName(combo.mods) + keyName(forKeyCode: UInt16(combo.code))
}

func isDangerousCombo(code: UInt32, mods: UInt32) -> Bool {
    guard mods == 0 else { return false }
    let name = keyName(forKeyCode: UInt16(code))
    return name.count == 1 || name == "Пробел"
}

// MARK: - Горячая клавиша: CGEventTap (основной) + Carbon (fallback)

private var carbonHotKey: EventHotKeyRef?
var carbonHotKeyActive = false
let hotKeySignature: OSType = 0x6D6D7574  // 'mmut'

final class HotkeyTap {
    static let shared = HotkeyTap()
    var onTrustChanged: ((Bool) -> Void)?

    private(set) var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var levelIdx = 0
    private var lastEventAt = Date()
    private var lastFlipAt = Date()
    private var pinned = false  // уровень, который точно доставляет события
    private var createFailures = 0  // после двух неудач — отключаемся, живём на Carbon
    private var tapAbandoned = false  // tap жив, но события не доставляет — навсегда на Carbon
    private var flipCount = 0

    /// Уровни tap: 0=HID, 1=session, 2=annotated session
    private let levels: [(UInt32, String)] = [(0, "hid"), (1, "session"), (2, "annotated")]

    var isActive: Bool { tap != nil }
    var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    func start() {
        checkTrust()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkTrust()
            self?.checkSilence()
        }
    }

    /// Показать системный диалог запроса доступа
    func promptForTrust() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private func checkTrust() {
        let wasActive = isActive
        if isTrusted && tap == nil && createFailures < 2 && !tapAbandoned {
            createTap()
        }
        if isActive != wasActive {
            DispatchQueue.main.async { [weak self] in
                if let self = self { self.onTrustChanged?(self.isActive) }
            }
        }
    }

    /// Если tap молчит или выключен — лечим: пересоздаём на другом уровне;
    /// если ни один уровень не доставляет события — навсегда уходим на Carbon
    private func checkSilence() {
        guard let tap = tap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            logKeyLine("--- tap disabled externally, re-enabling ---")
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        guard !pinned, !tapAbandoned, Date().timeIntervalSince(lastFlipAt) > 8 else { return }
        guard Date().timeIntervalSince(lastEventAt) > 6 else { return }
        flipCount += 1
        if flipCount >= levels.count * 2 {
            logKeyLine("--- tap never delivered events, abandoning -> Carbon ---")
            lastFlipAt = Date()
            invalidateTap()
            tapAbandoned = true
            DispatchQueue.main.async {
                AppDelegate.shared?.refreshKeyLabels()
                applyHotKey()
            }
            return
        }
        logKeyLine("--- tap silent >6s on level=\(levels[levelIdx].1), switching ---")
        lastFlipAt = Date()
        invalidateTap()
        levelIdx = (levelIdx + 1) % levels.count
        createTap()
    }

    private func invalidateTap() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func createTap() {
        let kEventOther: UInt32 = 14  // kCGEventOtherEvent
        let mask: CGEventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1) << kEventOther
            | CGEventMask(1) << 62   // tapDisabledByTimeout
            | CGEventMask(1) << 63   // tapDisabledByUserInput
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        let (levelRaw, levelName) = levels[levelIdx]
        guard let tapRef = CGEvent.tapCreate(
            tap: CGEventTapLocation(rawValue: levelRaw)!,
            place: CGEventTapPlacement(rawValue: 0)!,     // headInsert
            options: CGEventTapOptions(rawValue: 0)!,     // default
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            createFailures += 1
            NSLog("MicMute: не удалось создать event tap (level=\(levelName))")
            logKeyLine("--- tap create FAILED (level=\(levelName)) ---")
            return
        }
        tap = tapRef
        let source = CFMachPortCreateRunLoopSource(nil, tapRef, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tapRef, enable: true)
        lastEventAt = Date()
        NSLog("MicMute: event tap создан (уровень \(levelName))")
        logKeyLine("--- tap created (level=\(levelName)) enabled=\(CGEvent.tapIsEnabled(tap: tapRef)) ---")
        // Tap жив — Carbon-дубль не нужен
        unregisterCarbonHotKey()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lastEventAt = Date()
        if !pinned {
            pinned = true
            logKeyLine("--- level \(levels[levelIdx].1) delivers events, pinned ---")
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logKeyLine("--- tap DISABLED (type=\(type.rawValue)), re-enabling ---")
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if debugKeyLogging {
            logKeyLine("event type=\(type.rawValue)")
        }
        if type.rawValue == 14 { // kCGEventOtherEvent (NX_SYSDEFINED и прочие)
            if debugKeyLogging {
                // Дамп всех потенциально значимых полей — ищем, где лежит код клавиши
                func f(_ field: Int) -> String {
                    String(event.getIntegerValueField(CGEventField(rawValue: UInt32(field))!), radix: 16)
                }
                logKeyLine("otherEvent keycode=\(f(9)) srcData=\(f(42)) srcID=\(f(43)) srcGroup=\(f(44)) srcState=\(f(45)) f87=\(f(87)) f101=\(f(101)) subtype=\(f(108)) flags=0x\(String(event.flags.rawValue, radix: 16))")
            }
            return Unmanaged.passUnretained(event)
        }
        // keyDown
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let rawMods = UInt32(event.flags.rawValue)
            & UInt32(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        let cgMods = rawMods & ~secondaryFnMask  // fn не считаем модификатором
        if debugKeyLogging {
            logKeyLine("keyDown code=\(keyCode) mods=0x\(String(cgMods, radix: 16)) raw=0x\(String(rawMods, radix: 16)) repeat=\(event.getIntegerValueField(.keyboardEventAutorepeat))")
        }
        if !captureInProgress {
            let combo = currentKeyCombo()
            if keyCode == combo.code && toCGMask(combo.mods) == cgMods {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { AppDelegate.shared?.toggleMute() }
                }
                return nil // проглатываем событие, как настоящий хоткей
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

func applyHotKey() -> Bool {
    if HotkeyTap.shared.isActive {
        unregisterCarbonHotKey()
        return true
    }
    if let old = carbonHotKey {
        UnregisterEventHotKey(old)
        carbonHotKey = nil
    }
    let combo = currentKeyCombo()
    var ref: EventHotKeyRef?
    let err = RegisterEventHotKey(
        combo.code, combo.mods, EventHotKeyID(signature: hotKeySignature, id: 1),
        GetEventDispatcherTarget(), 0, &ref)
    if err == noErr {
        carbonHotKey = ref
        carbonHotKeyActive = true
        return true
    }
    carbonHotKeyActive = false
    NSLog("MicMute: не удалось зарегистрировать клавишу \(combo.code)+\(combo.mods), err=\(err)")
    return false
}

func unregisterCarbonHotKey() {
    if let old = carbonHotKey {
        UnregisterEventHotKey(old)
        carbonHotKey = nil
    }
    carbonHotKeyActive = false
}

func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let size = MemoryLayout<EventHotKeyID>.size
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil, size, nil, &hotKeyID)
    if hotKeyID.signature == hotKeySignature {
        DispatchQueue.main.async {
            AppDelegate.shared?.toggleMute()
        }
    }
    return noErr
}

// MARK: - Захват новой клавиши

final class KeyCaptureController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    var onComplete: ((UInt32?, UInt32) -> Void)?

    func start() {
        end()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.title = "Смена клавиши"
        panel.level = .floating
        panel.delegate = self
        panel.center()

        let label = NSTextField(labelWithString: "Нажмите новую клавишу или комбинацию…")
        label.frame = NSRect(x: 0, y: 78, width: 400, height: 24)
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .medium)
        panel.contentView?.addSubview(label)

        let hint = NSTextField(labelWithString: "Esc — отмена")
        hint.frame = NSRect(x: 0, y: 44, width: 400, height: 18)
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        panel.contentView?.addSubview(hint)

        self.panel = panel
        captureInProgress = true

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == 53 {
            finish(code: nil, mods: 0)
            return
        }
        let cgMask = UInt32(event.modifierFlags.rawValue)
            & UInt32(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        finish(code: UInt32(event.keyCode), mods: toCarbonMask(cgMask))
    }

    private func finish(code: UInt32?, mods: UInt32) {
        captureInProgress = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        NSApp.setActivationPolicy(.accessory)
        onComplete?(code, mods)
    }

    func windowWillClose(_ notification: Notification) {
        monitor = nil
        captureInProgress = false
        panel?.delegate = nil
        panel = nil
        NSApp.setActivationPolicy(.accessory)
        onComplete?(nil, 0)
    }

    func end() {
        monitor = nil
        captureInProgress = false
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Один экземпляр приложения

private var singletonFD: Int32 = -1

func acquireSingleInstance() -> Bool {
    let dir = NSHomeDirectory() + "/Library/Application Support/MicMute"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let fd = open(dir + "/singleton.lock", O_RDWR | O_CREAT, 0o644)
    guard fd >= 0 else { return true }
    singletonFD = fd
    return flock(fd, LOCK_EX | LOCK_NB) == 0
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var keyStatusItem: NSMenuItem!
    private var keyItem: NSMenuItem!
    private var debugItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var timer: Timer?
    private let capture = KeyCaptureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Микрофон: …", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        toggleItem = NSMenuItem(title: "Переключить", action: #selector(toggleMute), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        keyStatusItem = NSMenuItem(title: "⌨️ …", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        keyStatusItem.target = self
        menu.addItem(keyStatusItem)

        keyItem = NSMenuItem(title: "Сменить клавишу…", action: #selector(changeKey), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        loginItem = NSMenuItem(title: "Запускаться при входе", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        debugItem = NSMenuItem(title: "Отладка: лог клавиш", action: #selector(toggleDebug), keyEquivalent: "")
        debugItem.target = self
        debugItem.state = debugKeyLogging ? .on : .off
        menu.addItem(debugItem)

        let logItem = NSMenuItem(title: "Показать лог отладки", action: #selector(showLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "MicMute v\(version), сборка \(build)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(
            title: "Завершить MicMute",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusItem.menu = menu

        MicMonitor.shared.onChange = { [weak self] in
            self?.refreshUI()
        }
        MicMonitor.shared.start()

        HotkeyTap.shared.onTrustChanged = { [weak self] _ in
            self?.refreshKeyLabels()
        }
        // В MAS-сборке (песочница) tap недоступен — работаем через Carbon
        let forceCarbon = UserDefaults.standard.bool(forKey: "ForceCarbon")
            || (Bundle.main.infoDictionary?["MicMuteForceCarbon"] as? Bool ?? false)
        if forceCarbon {
            applyHotKey()
        } else {
            HotkeyTap.shared.start()
            if !HotkeyTap.shared.isTrusted {
                HotkeyTap.shared.promptForTrust()
            }
        }

        // Carbon-обработчик (fallback, если tap недоступен)
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyHandler(nextHandler:event:userData:),
            1, &spec, nil, nil)
        applyHotKey()

        capture.onComplete = { [weak self] code, mods in
            guard let self = self, let code = code else { return }
            self.setHotKey(code: code, mods: mods)
        }

        refreshKeyLabels()
        refreshLoginItem()
        refreshUI()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
    }

    @objc func toggleMute() {
        if let muted = toggleMuteState() {
            refreshUI(mutedOverride: muted)
        }
    }

    @objc func changeKey() {
        capture.start()
    }

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleLoginItem() {
        if #available(macOS 13, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Не удалось изменить автозапуск"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            refreshLoginItem()
        }
    }

    private func refreshLoginItem() {
        guard let item = loginItem else { return }
        if #available(macOS 13, *) {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            item.isEnabled = false
        }
    }

    @objc func toggleDebug() {
        debugKeyLogging = !debugKeyLogging
        UserDefaults.standard.set(debugKeyLogging, forKey: "DebugKeys")
        debugItem.state = debugKeyLogging ? .on : .off
        if debugKeyLogging {
            logKeyLine("--- debug on ---")
        }
    }

    @objc func showLog() {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/micmute-keys.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "--- лог пуст ---\n".data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func setHotKey(code: UInt32, mods: UInt32) {
        let name = modifierName(mods) + keyName(forKeyCode: UInt16(code))

        if isDangerousCombo(code: code, mods: mods) {
            let alert = NSAlert()
            alert.messageText = "Клавиша «\(name)» без модификаторов"
            alert.informativeText = "Она будет перехватываться во всех приложениях — вводить этот символ станет невозможно. Продолжить?"
            alert.addButton(withTitle: "Продолжить")
            alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let defaults = UserDefaults.standard
        defaults.set(Int(code), forKey: defaultsHotKeyKeyCode)
        defaults.set(Int(mods), forKey: defaultsHotKeyModifiers)
        if !applyHotKey() {
            let alert = NSAlert()
            alert.messageText = "Не удалось назначить «\(name)»"
            alert.informativeText = "Возможно, клавиша занята системой или другим приложением."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        refreshKeyLabels()
    }

    func refreshKeyLabels() {
        let name = currentKeyName()
        toggleItem.title = "Переключить (\(name))"
        keyItem.title = "Сменить клавишу…  (\(name))"
        if HotkeyTap.shared.isActive {
            keyStatusItem.title = "⌨️ \(name) — активна"
        } else if carbonHotKeyActive {
            keyStatusItem.title = "⌨️ \(name) — активна (Carbon)"
        } else if HotkeyTap.shared.isTrusted {
            keyStatusItem.title = "⚠️ Клавиша не перехватывается (tap недоступен)"
        } else {
            keyStatusItem.title = "⚠️ Нужен доступ «Универсальный доступ» — нажмите сюда"
        }
    }

    private func refreshUI(mutedOverride: Bool? = nil) {
        let muted = mutedOverride ?? readMuteState() ?? false
        let button = statusItem.button
        if muted {
            button?.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Микрофон выключен")
            button?.image?.isTemplate = false
            button?.contentTintColor = .systemRed
            button?.title = ""
            stateItem.title = "Микрофон: выключен"
        } else {
            button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Микрофон включён")
            button?.image?.isTemplate = false
            button?.contentTintColor = .labelColor
            button?.title = ""
            stateItem.title = "Микрофон: включён"
        }
        if button?.image == nil {
            button?.title = muted ? "🔇" : "🎤"
        }
    }
}

// MARK: - Запуск

if !acquireSingleInstance() {
    // Уже запущен другой экземпляр — молча выходим
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
