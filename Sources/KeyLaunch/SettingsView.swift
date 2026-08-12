import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            VStack(spacing: 6) {
                ForEach(store.mappings) { mapping in
                    MappingRow(mapping: mapping)
                }
            }
            .padding(12)

            Divider()
            footer
        }
        .frame(width: 400)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Keyboard shortcuts")
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(subtitleColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        if !trusted { return "Accessibility access is off, so keys cannot be captured." }
        if store.learningID != nil { return "Press a key now. Escape cancels." }
        if let fired = store.lastFired { return "Opened \(fired)" }
        return "Click a key slot, press the key you want, then pick an app."
    }

    private var subtitleColor: Color {
        trusted ? .secondary : .orange
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if !trusted {
                Button("Grant Access") {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .controlSize(.small)
            }
            Button {
                store.mappings.append(Mapping())
            } label: {
                Image(systemName: "plus")
            }
            .controlSize(.small)
            .help("Add another shortcut")

            Spacer()

            Button("Quit KeyLaunch") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct MappingRow: View {
    let mapping: Mapping
    @ObservedObject var store = Store.shared
    @State private var hovering = false

    private var isLearning: Bool { store.learningID == mapping.id }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.learningID = isLearning ? nil : mapping.id
            } label: {
                Text(keyLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .frame(width: 128)
                    .padding(.vertical, 5)
                    .background(keyBackground)
                    .foregroundStyle(isLearning ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            Button(action: chooseApp) {
                HStack(spacing: 6) {
                    if let url = mapping.appURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(mapping.appName ?? "")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    } else {
                        Text("Choose app…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Button {
                if store.mappings.count > 1 {
                    store.mappings.removeAll { $0.id == mapping.id }
                } else {
                    store.clear(mapping.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .onHover { hovering = $0 }
    }

    private var keyLabel: String {
        if isLearning { return "Press a key…" }
        return mapping.trigger?.label ?? "Set key"
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(isLearning ? 0.03 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isLearning ? Color.accentColor : .clear, lineWidth: 1)
            )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.setApp(url, for: mapping.id)
        }
    }
}
