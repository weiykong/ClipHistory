import AppKit
import Carbon.HIToolbox
import SwiftUI

private func clipHistoryHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }

    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.showPopupFromHotkey()
    return noErr
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Core objects

    private var settings:       AppSettings!
    private var store:          ClipboardStore!
    private var popup:          PopupWindowController!
    private var updateChecker:  UpdateChecker!

    // MARK: - UI

    private var statusItem:       NSStatusItem?
    private var hotkeyHintItem:   NSMenuItem?   // updated live when hotkey changes
    private var settingsWindow:   NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingDelegate = OnboardingWindowDelegate()

    // MARK: - Background work

    private var hotkeyRef:          EventHotKeyRef?
    private var eventHandlerRef:     EventHandlerRef?
    private var clipboardTimer:      Timer?
    private var lastFrontmostSource: SourceApp?   // updated on every app-switch

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings      = AppSettings()
        store         = ClipboardStore(maxCount: settings.maxItems)
        updateChecker = UpdateChecker()
        popup         = PopupWindowController(store: store, settings: settings, updateChecker: updateChecker)

        // Wire setting-change callbacks
        settings.onHotkeyChanged   = { [weak self] _ in self?.reRegisterHotkey() }
        settings.onMaxItemsChanged = { [weak self] n  in self?.store.updateMaxCount(n) }

        setupMenuBar()
        startFrontmostAppTracking()
        startClipboardMonitoring()
        requestAccessibilityAndRegisterHotkey()
        showOnboardingIfNeeded()

        // Check for updates on every launch
        updateChecker.checkForUpdate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        unregisterHotkey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = .clipHistoryMenuBar()

        let menu = NSMenu()
        menu.delegate = self

        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        hotkeyHintItem = hint

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(quit),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    /// Refresh the hint line right before the menu opens (hotkey might have changed)
    func menuWillOpen(_ menu: NSMenu) {
        hotkeyHintItem?.title = hintTitle
    }

    private var hintTitle: String { "ClipHistory  —  \(settings.hotkey.displayString) to open" }

    // MARK: - Settings window

    @objc private func openSettings() {
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate()
            return
        }

        let view       = SettingsView(settings: settings, store: store,
                                     onReopenOnboarding: { [weak self] in
                                         self?.settingsWindow?.orderOut(nil)
                                         UserDefaults.standard.removeObject(forKey: Self.onboardingDoneKey)
                                         self?.showOnboarding()
                                     })
        let controller = NSHostingController(rootView: view)
        let win        = NSWindow(contentViewController: controller)
        win.title                = "ClipHistory Settings"
        win.styleMask            = NSWindow.StyleMask([.titled, .closable])
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win

        win.makeKeyAndOrderFront(NSApp)
        NSRunningApplication.current.activate()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Onboarding

    private static let onboardingDoneKey = "onboardingComplete"

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) else { return }
        showOnboarding()
    }

    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate()
            return
        }

        let view = OnboardingView(settings: settings) { [weak self] in
            self?.dismissOnboarding()
        }
        let controller = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: controller)
        win.title                = "ClipHistory Setup"
        win.styleMask            = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win

        // Use a delegate to catch the window's close button as well
        onboardingDelegate.onClose = { [weak self] in self?.dismissOnboarding() }
        win.delegate = onboardingDelegate

        win.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
    }

    private func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    // MARK: - Source-app tracking

    private func startFrontmostAppTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        updateFrontmostSource()   // capture the app that's active right now
    }

    @objc private func frontmostAppDidChange(_ note: Notification) {
        updateFrontmostSource()
    }

    private func updateFrontmostSource() {
        guard let app  = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let name = app.localizedName
        else { return }
        lastFrontmostSource = SourceApp(bundleID: app.bundleIdentifier ?? "", name: name)
    }

    // MARK: - Clipboard polling

    private func startClipboardMonitoring() {
        // Capture whatever is already on the clipboard at launch
        store.pollClipboard(source: lastFrontmostSource)

        var lastCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let count = NSPasteboard.general.changeCount
            if count != lastCount {
                lastCount = count
                guard let self else { return }
                let source = self.lastFrontmostSource
                // Skip apps the user has excluded from capture.
                if let bid = source?.bundleID,
                   self.settings.excludedBundleIDs.contains(bid) { return }
                self.store.pollClipboard(source: source)
            }
        }
    }

    // MARK: - Global hotkey

    private func requestAccessibilityAndRegisterHotkey() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        reRegisterHotkey()
    }

    private func reRegisterHotkey() {
        installHotkeyHandlerIfNeeded()
        unregisterHotkey()

        let hotkeyID = EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyID)
        let status = RegisterEventHotKey(
            UInt32(settings.hotkey.keyCode),
            settings.hotkey.carbonModifierFlags,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            NSLog("ClipHistory failed to register hotkey: \(status)")
        }
    }

    fileprivate func showPopupFromHotkey() {
        DispatchQueue.main.async { [weak self] in
            self?.popup.show(near: NSEvent.mouseLocation)
        }
    }

    private func installHotkeyHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            clipHistoryHotkeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("ClipHistory failed to install hotkey handler: \(status)")
        }
    }

    private func unregisterHotkey() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    private static let hotkeySignature: OSType = 0x43484B59 // "CHKY"
    private static let hotkeyID: UInt32 = 1
}

// MARK: - Onboarding window delegate

/// Thin NSWindowDelegate that fires a closure when the window is about to close.
/// Used so the "× close" button marks onboarding complete just like "Get Started".
final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void = {}
    func windowWillClose(_ notification: Notification) { onClose() }
}

// MARK: -

private extension HotkeyShortcut {
    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        let modifiers = modifierFlags

        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { flags |= UInt32(shiftKey) }

        return flags
    }
}
