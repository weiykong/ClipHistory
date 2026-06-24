import Foundation
import AppKit
import Observation
import ServiceManagement

@Observable
final class AppSettings {

    // MARK: - Stored properties

    var hotkey: HotkeyShortcut = .default {
        didSet { save(); onHotkeyChanged?(hotkey) }
    }

    var maxItems: Int = 50 {
        didSet { save(); onMaxItemsChanged?(maxItems) }
    }

    var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    /// Hide image items from the popup list.
    var hideImages: Bool = false {
        didSet { save() }
    }

    /// When true, reopening the popup keeps the previous selection/scroll
    /// position instead of jumping back to the newest clip at the top.
    var rememberScrollPosition: Bool = false {
        didSet { save() }
    }

    /// Bundle IDs of apps whose clipboard changes are silently ignored.
    var excludedBundleIDs: Set<String> = [] {
        didSet { save() }
    }

    // MARK: - Callbacks (set by AppDelegate)

    var onHotkeyChanged:   ((HotkeyShortcut) -> Void)?
    var onMaxItemsChanged: ((Int) -> Void)?

    // MARK: - Init

    init() { load() }

    // MARK: - Persistence

    private enum Keys {
        static let hotkey                 = "hotkey"
        static let maxItems               = "maxItems"
        static let hideImages             = "hideImages"
        static let rememberScrollPosition = "rememberScrollPosition"
        static let excludedBundleIDs      = "excludedBundleIDs"
    }

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Keys.hotkey),
           let saved = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
            hotkey = saved
        }
        let n = d.integer(forKey: Keys.maxItems)
        if n >= 5 { maxItems = n }

        hideImages = d.bool(forKey: Keys.hideImages)
        rememberScrollPosition = d.bool(forKey: Keys.rememberScrollPosition)
        if let ids = d.stringArray(forKey: Keys.excludedBundleIDs) {
            excludedBundleIDs = Set(ids)
        }

        // Read ground-truth from the OS — don't call SMAppService again if it
        // already matches (guard in didSet prevents the redundant call).
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(hotkey) {
            d.set(data, forKey: Keys.hotkey)
        }
        d.set(maxItems,                 forKey: Keys.maxItems)
        d.set(hideImages,               forKey: Keys.hideImages)
        d.set(rememberScrollPosition,   forKey: Keys.rememberScrollPosition)
        d.set(Array(excludedBundleIDs), forKey: Keys.excludedBundleIDs)
    }

    // MARK: - Launch at Login

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService throws if the state is already what we asked for,
            // or if it needs user approval — both are non-fatal.
            NSLog("ClipHistory: launch-at-login update: \(error.localizedDescription)")
        }
    }
}
