import AppKit
import SwiftUI

// MARK: - AppKit recorder view

final class HotkeyRecorderNSView: NSView {
    var hotkey: HotkeyShortcut { didSet { needsDisplay = true } }
    var onChanged: (HotkeyShortcut) -> Void

    private var isRecording = false { didSet { needsDisplay = true } }

    init(hotkey: HotkeyShortcut, onChanged: @escaping (HotkeyShortcut) -> Void) {
        self.hotkey = hotkey
        self.onChanged = onChanged
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool { true }

    // Recording must NOT start from becomeFirstResponder: AppKit makes this view the
    // window's initial first responder when the settings window opens, which arms
    // recording before any click and inverts the mouseDown toggle below (the first
    // click then takes the stop branch, so keyDown never fires).
    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let mods    = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Escape cancels recording without saving
        if keyCode == 53 { window?.makeFirstResponder(nil); return }

        // Require at least one real modifier (Cmd / Ctrl / Opt)
        guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else { return }

        let newHotkey = HotkeyShortcut(keyCode: keyCode, modifiers: mods.rawValue)
        hotkey = newHotkey
        onChanged(newHotkey)
        window?.makeFirstResponder(nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.82)
        ).setFill()
        path.fill()

        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.70)
            : NSColor.separatorColor.withAlphaComponent(0.70)
        ).setStroke()
        path.lineWidth = 1
        path.stroke()

        let label = isRecording ? "Type shortcut…" : hotkey.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz  = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                             y: (bounds.height - sz.height) / 2))
    }
}

// MARK: - SwiftUI wrapper

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: HotkeyShortcut

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        HotkeyRecorderNSView(hotkey: hotkey) { hotkey = $0 }
    }

    func updateNSView(_ view: HotkeyRecorderNSView, context: Context) {
        view.hotkey    = hotkey
        view.onChanged = { hotkey = $0 }
    }
}
