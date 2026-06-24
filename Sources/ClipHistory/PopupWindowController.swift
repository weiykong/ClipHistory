import AppKit
import SwiftUI
import CoreGraphics

final class PopupWindowController {
    private var panel:      NSPanel?
    private let store:      ClipboardStore
    private let settings:   AppSettings
    private let popupState = PopupState()

    private var clickMonitor: Any?
    private var eventTap:     CFMachPort?
    private var tapSource:    CFRunLoopSource?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store    = store
        self.settings = settings
    }

    // MARK: - Show / Hide

    func show(near mouse: NSPoint) {
        popupState.reset(keepSelection: settings.rememberScrollPosition)
        // Clamp the remembered index in case clips were trimmed/added while
        // the popup was closed, so it never points past the end of the list.
        if settings.rememberScrollPosition {
            let count = store.filtered(query: "", showImages: !settings.hideImages).count
            popupState.selectedIndex = min(popupState.selectedIndex, max(0, count - 1))
        }

        if panel == nil { buildPanel() }
        guard let panel else { return }

        let size = CGSize(width: 360, height: 420)
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 14)

        // Keep fully on-screen
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let sf = screen?.visibleFrame {
            origin.x = max(sf.minX + 8, min(origin.x, sf.maxX - size.width - 8))
            if origin.y + size.height > sf.maxY - 8 {
                origin.y = mouse.y - size.height - 14
            }
            origin.y = max(sf.minY + 8, origin.y)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        // makeKeyAndOrderFront so SwiftUI buttons inside the panel receive clicks.
        // .nonactivatingPanel guarantees our *app* is never activated, meaning
        // App A remains the active application.  Its text cursor / first-responder
        // state is preserved inside its own window and resumes the moment our
        // panel closes, which is exactly what we need before firing Cmd+V.
        panel.makeKeyAndOrderFront(nil)
        startEventTap()
        addClickMonitor()
    }

    func hide() {
        stopEventTap()
        removeClickMonitor()
        panel?.orderOut(nil)
        // No focus restoration needed — App A never lost focus.
    }

    // MARK: - Paste

    func pasteItem(_ item: ClipItem) {
        // Suppress the monitor so our own clipboard write doesn't re-insert the item.
        store.suppressNextPoll = true

        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.content {
        case .text(let text):
            pb.setString(text, forType: .string)
        case .image(let data):
            if let img = NSImage(data: data) { pb.writeObjects([img]) }
        }

        hide()

        // Short delay so the panel finishes dismissing before Cmd+V fires.
        // App A's text field kept focus the whole time (nonactivatingPanel),
        // so no activate() call is needed — the Cmd+V lands directly into App A.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.simulateCmdV()
        }
    }

    // MARK: - Filtered items

    private var filteredItems: [ClipItem] {
        store.filtered(query: popupState.searchText,
                       showImages: !settings.hideImages)
    }

    private func selectCurrentItem() {
        let items = filteredItems
        guard items.indices.contains(popupState.selectedIndex) else { return }
        pasteItem(items[popupState.selectedIndex])
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: .zero,
            // .nonactivatingPanel: clicking / ordering-front does NOT activate our app,
            // so the previously-focused app (and its text cursor) remain active.
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level              = .popUpMenu
        p.isFloatingPanel    = true
        p.hidesOnDeactivate  = false
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false  // Shadow drawn via SwiftUI .shadow() modifier so it follows the rounded shape

        p.contentView = NSHostingView(rootView: PopupView(
            store:     store,
            settings:  settings,
            state:     popupState,
            onSelect:  { [weak self] item in self?.pasteItem(item) },
            onDismiss: { [weak self] in self?.hide() }
        ))
        panel = p
    }

    // MARK: - CGEvent tap (keyboard interception while popup is visible)
    //
    // Because the panel is non-activating, App A retains keyboard focus and
    // SwiftUI's onKeyPress would never fire.  We install a session-level
    // intercepting event tap instead so ALL key-down events are routed here.

    private func startEventTap() {
        stopEventTap()   // clean up any stale tap

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask    = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .defaultTap,          // intercepting (events can be consumed)
            eventsOfInterest: mask,
            callback: { (_, type, cgEvent, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let ctrl = Unmanaged<PopupWindowController>
                    .fromOpaque(userInfo).takeUnretainedValue()
                // macOS silently disables taps that are slow to respond (e.g.
                // after sleep/wake or heavy load). Re-enable instead of letting
                // keyboard handling die for the rest of the session.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ctrl.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                return ctrl.handleKeyDown(event: cgEvent)
            },
            userInfo: selfPtr
        )

        guard let tap else { return }   // Accessibility permission not granted — degrade gracefully
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap  = tap
        tapSource = src
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap  = nil
        tapSource = nil
    }

    /// Called from the CGEvent tap callback (may be on any thread).
    /// Returns nil to consume the event; returns the event to pass it through.
    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags

        // Always pass Cmd and Ctrl combos through so the OS / App A can handle
        // things like Cmd+Q, Cmd+Tab, Ctrl+C, etc.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return Unmanaged.passRetained(event)
        }

        switch keyCode {
        case 53:                        // Escape
            DispatchQueue.main.async { [weak self] in self?.hide() }
            return nil

        case 126:                       // ↑ Up arrow
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.popupState.selectedIndex = max(0, self.popupState.selectedIndex - 1)
            }
            return nil

        case 125:                       // ↓ Down arrow
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let count = self.filteredItems.count
                self.popupState.selectedIndex = min(max(count - 1, 0),
                                                    self.popupState.selectedIndex + 1)
            }
            return nil

        case 36, 76:                    // Return / numpad Enter
            DispatchQueue.main.async { [weak self] in self?.selectCurrentItem() }
            return nil

        case 51:                        // Backspace / Delete
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.popupState.searchText.isEmpty {
                    self.popupState.searchText.removeLast()
                    self.popupState.selectedIndex = 0
                }
            }
            return nil

        case 123, 124:                  // ← → arrows — no meaning in popup, consume
            return nil

        default:
            // Decode the typed character (respects shift, option-accent, etc.)
            var unicodeChars = [UniChar](repeating: 0, count: 4)
            var length       = 0
            event.keyboardGetUnicodeString(maxStringLength: 4,
                                           actualStringLength: &length,
                                           unicodeString: &unicodeChars)
            guard length > 0 else { return Unmanaged.passRetained(event) }

            let typed = String(decoding: unicodeChars.prefix(length), as: Unicode.UTF16.self)

            // Drop control characters (value < 32) and DEL (127)
            let printable = typed.filter { ch in
                guard let v = ch.unicodeScalars.first?.value else { return false }
                return v >= 32 && v != 127
            }
            guard !printable.isEmpty else { return Unmanaged.passRetained(event) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.popupState.searchText += printable
                self.popupState.selectedIndex = 0
            }
            return nil
        }
    }

    // MARK: - Click monitor (dismiss when user clicks outside the popup)

    private func addClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    // MARK: - Paste simulation

    private static func simulateCmdV() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
