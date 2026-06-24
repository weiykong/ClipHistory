import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store:    ClipboardStore
    var onReopenOnboarding: (() -> Void)?

    @State private var showClearAlert = false

    private var knownSourceApps: [SourceApp] {
        var seen = Set<String>()
        return store.items
            .compactMap(\.sourceApp)
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                settingsHeader
                generalSection
                shortcutSection
                historySection
                privacySection
                footerLink
            }
            .padding(28)
        }
        .frame(width: 480, height: 600)
        .background {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .alert("Clear clipboard history?", isPresented: $showClearAlert) {
            Button("Clear All", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.items.count) stored items.")
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("ClipHistory")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Light. Private. Fast. — v\(UpdateChecker.currentVersion)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer()

            HeaderMetric(value: "\(store.items.count)", label: "Items")
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius))
    }

    // MARK: - Sections

    private var generalSection: some View {
        SettingsSection(title: "General", subtitle: "Launch behavior") {
            SettingsRow(icon: "bolt.fill",
                        iconColor: .accentColor,
                        label: "Launch at Login",
                        hint: "Start ClipHistory automatically when you log in.") {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection(title: "Shortcut", subtitle: "Global access") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(icon: "keyboard.fill",
                            iconColor: .blue,
                            label: "Open Popup",
                            hint: "The combination to show your history.") {
                    HotkeyRecorder(hotkey: $settings.hotkey)
                        .frame(width: 162, height: 32)
                }

                Text("Click the field, then press your desired shortcut.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: "History", subtitle: "Management") {
            VStack(spacing: 0) {
                SettingsRow(icon: "tray.full.fill",
                            iconColor: .accentColor,
                            label: "Max Items",
                            hint: "Oldest unpinned clips are trimmed.") {
                    HStack(spacing: 12) {
                        Text("\(settings.maxItems)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 34, alignment: .trailing)
                        Stepper("", value: $settings.maxItems, in: 5...500)
                            .labelsHidden()
                    }
                }

                Divider().padding(.horizontal, 16).opacity(0.5)

                SettingsRow(icon: "arrow.up.to.line",
                            iconColor: .accentColor,
                            label: "Remember Position",
                            hint: "Reopen where you left off instead of the top.") {
                    Toggle("", isOn: $settings.rememberScrollPosition)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().padding(.horizontal, 16).opacity(0.5)

                SettingsRow(icon: "clock.fill",
                            iconColor: .secondary,
                            label: "Capacity",
                            hint: "Current amount of stored clips.") {
                    Text("\(store.items.count) clips")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.horizontal, 16).opacity(0.5)

                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear All Data")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("This removes all clips permanently.")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }

                    Spacer()

                    Button("Clear") {
                        showClearAlert = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy", subtitle: "Exclusions") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 28, height: 28)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    Text("Sensitive content and password managers are always ignored. You can manually exclude specific apps below.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)

                Divider().padding(.horizontal, 16).opacity(0.5)

                if knownSourceApps.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No apps detected")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Apps appear here after they copy content.")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(knownSourceApps.enumerated()), id: \.element.bundleID) { i, app in
                        if i > 0 { Divider().padding(.horizontal, 16).opacity(0.5) }
                        appExcludeRow(app)
                    }
                }
            }
        }
    }

    private func appExcludeRow(_ app: SourceApp) -> some View {
        let excluded = settings.excludedBundleIDs.contains(app.bundleID)
        return HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(excluded ? "Excluded" : "Monitored")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(excluded ? Color.accentColor : Color.secondary.opacity(0.6))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { excluded },
                set: { on in
                    if on { settings.excludedBundleIDs.insert(app.bundleID) }
                    else  { settings.excludedBundleIDs.remove(app.bundleID) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var footerLink: some View {
        Button {
            onReopenOnboarding?()
        } label: {
            Label("Restart Guide", systemImage: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

// MARK: - Header metric

private struct HeaderMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Reusable section container

private struct SettingsSection<Content: View>: View {
    let title:    String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius))
        }
    }
}

// MARK: - Single labeled row

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconColor: Color = .accentColor
    let label: String
    var hint:  String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Visual Effect View helper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
