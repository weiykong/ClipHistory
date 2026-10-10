# macOS 26 smoke test — ClipHistory v1.3.4

Run once per major macOS release. Takes ~10 minutes. Last run: **macOS 26.6.2 (build 25G83), Swift 6.3.3** — all pass.

## Automated probe (already verified)

These are the APIs ClipHistory depends on; they are the ones macOS tightens between releases.
Run `swift probe.swift` from a process that has Accessibility granted:

| Check | Result on macOS 26.6.2 |
|---|---|
| `AXIsProcessTrusted()` | true |
| `CGEvent.tapCreate` (session tap, keyDown mask) | OK |
| `CGEvent.tapEnable` re-enable after timeout-disable | OK, no crash |
| `NSPasteboard.general.changeCount` polling | OK |
| `org.nspasteboard.ConcealedType` constant | present, unchanged |
| AES-256-GCM seal/open round-trip | OK |
| Keychain `SecItemAdd` for the encryption key | OK |

## Manual checklist

1. **Hotkey** — press `⌥V` from Finder, a browser, and a text editor. Popup opens at the cursor.
2. **Hotkey change (PR #3 fix)** — Settings → recorder field. Click once, it must flip to
   "Type shortcut…", then press e.g. `⌥⌘C`. It must capture, not beep, and the new hotkey must
   open the popup. *Before the fix, the first click disarmed the recorder because AppKit made the
   view the window's initial first responder.*
3. **Paste** — select an item, press `↵`; it lands in the target app.
4. **Images** — copy a screenshot; the row shows a thumbnail and pastes as an image.
5. **Concealed items** — copy a password from a password manager; it must not appear in history.
6. **Per-app exclusion** — exclude one app, copy from it, nothing recorded.
7. **Search + pin** — filter by content and by source app name; pinned item survives a new copy.
8. **Persistence** — quit and relaunch; history is still there (`~/Library/Application Support/ClipHistory/history.json.enc`).
9. **Launch at Login** — toggle in Settings, verify the login item appears.
10. **Update banner** — popup shows the banner when a newer GitHub release exists.

## Known constraints

- Ad-hoc signature only (no Developer ID): Gatekeeper rejects it, so first launch needs the
  `xattr -d com.apple.quarantine` step documented in the README. This is a distribution
  constraint, not a bug — fixing it requires an Apple Developer ID certificate ($99/yr) plus
  hardened runtime and notarization.
- Event taps can be disabled by macOS after a timeout; the app re-enables them
  (`PopupWindowController.swift`). Re-check this on every OS bump.
