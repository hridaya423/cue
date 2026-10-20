import AppKit
import SwiftUI

extension OnboardingView {
    var permissionControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            instruction(1, "Open System Settings with the button below.")
            instruction(2, "Turn on Cue under Accessibility.")
            HStack(spacing: 8) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "circle.dotted")
                Text(trusted ? "Access granted" : "Cue brings you back as soon as it\u{2019}s on.")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(trusted ? Color.green : OBTheme.textTertiary)
            .padding(.top, 6)
        }
        .task(id: step == .accessibility) {
            guard step == .accessibility else { return }
            while !Task.isCancelled && step == .accessibility {
                trusted = ContextCaptor.isTrusted
                if trusted {
                    if openedPermissionSettings { model.open(id: "onboarding") }
                    openedPermissionSettings = false
                    advance()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    var permissionStage: some View {
        PermissionScene(granted: trusted)
            .frame(width: 372, height: 504)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("System Settings, Privacy & Security, Accessibility: the switch next to Cue turns on")
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OBTheme.action)
                .frame(width: 26, height: 26)
                .background(OBTheme.action.opacity(0.1), in: Circle())
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(OBTheme.textPrimary)
        }
    }

    func grantAccessibility() {
        openedPermissionSettings = true
        ContextCaptor.requestTrust()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// The Accessibility list in System Settings, cropped to four apps with Cue in focus. One loop: the cursor
/// glides to Cue's switch, clicks, the switch turns on and glows, the result holds, then the pane fades
/// out and back in with the switch already off. With Reduce Motion, or once access is granted, it shows
/// the finished state.
struct PermissionScene: View {
    var granted: Bool
    @State private var cueOn = false
    @State private var shown = true
    @Environment(\.colorScheme) private var scheme

    private static let apps: [(name: String, bundleID: String?, on: Bool)] = [
        ("Automator", "com.apple.Automator", false), ("Cue", nil, false),
        ("Safari", "com.apple.Safari", true), ("Terminal", "com.apple.Terminal", true),
    ]
    private static let ink = Color(red: 0.01, green: 0.05, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accessibility").font(.system(size: 17, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(Array(Self.apps.enumerated()), id: \.offset) { i, app in
                    if i > 0 { Divider().padding(.leading, 58) }
                    appRow(app)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .padding(20)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(scheme == .dark ? 0.16 : 0.7), lineWidth: 0.75))
        .shadow(color: Self.ink.opacity(0.5), radius: 34, y: 20)
        .shadow(color: Self.ink.opacity(0.3), radius: 4, y: 2)
        .opacity(shown ? 1 : 0)
        .animation(shown ? OBMotion.moderate : OBMotion.exit, value: shown)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func appRow(_ app: (name: String, bundleID: String?, on: Bool)) -> some View {
        let isCue = app.name == "Cue"
        HStack(spacing: 12) {
            appIcon(isCue ? NSApp.applicationIconImage : Self.icon(app.bundleID), size: 36)
            Text(app.name).font(.system(size: 16, weight: isCue ? .semibold : .regular))
            Spacer()
            if isCue {
                PermissionSwitchDemo(granted: granted, isOn: $cueOn, shown: $shown)
            } else {
                SettingsSwitch(on: app.on)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .opacity(isCue ? 1 : 0.55)
        .zIndex(isCue ? 1 : 0)
    }

    private func appIcon(_ image: NSImage?, size: CGFloat) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "paperclip").resizable().scaledToFit() }
        }
        .frame(width: size, height: size)
    }

    private static func icon(_ bundleID: String?) -> NSImage? {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// A macOS switch; the knob slides and the track fills with the accent.
struct SettingsSwitch: View {
    var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? OBTheme.action : Color.primary.opacity(0.16))
            .frame(width: 46, height: 26)
            .overlay {
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: on ? 10 : -10)
            }
            .animation(OBMotion.moderate, value: on)
    }
}

/// Cue's switch and the loop that drives the pane. Every pause is a sleep, so nothing redraws between steps.
struct PermissionSwitchDemo: View {
    var granted: Bool
    @Binding var isOn: Bool
    @Binding var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var visible = false
    @State private var pressing = false

    private static let away = CGSize(width: -120, height: 96)

    var body: some View {
        let lit = isOn || granted
        ZStack {
            Circle()
                .fill(OBTheme.action)
                .frame(width: 44, height: 44)
                .blur(radius: 12)
                .opacity(lit ? 0.4 : 0)
            SettingsSwitch(on: lit)
        }
        .animation(OBMotion.slow, value: lit)
        .overlay(alignment: .topLeading) {
            if !reduceMotion && !granted {
                Image(nsImage: NSCursor.arrow.image)
                    .scaleEffect(1.35, anchor: .topLeading)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .scaleEffect(pressing ? 0.86 : 1, anchor: .topLeading)
                    .opacity(visible ? 1 : 0)
                    .offset(arrived ? CGSize(width: 16, height: 14) : Self.away)
            }
        }
        .frame(width: 46, height: 26)
        .task(id: granted || reduceMotion) {
            guard !granted && !reduceMotion else { isOn = true; shown = true; return }
            while !Task.isCancelled {
                guard await pause(1.2) else { return }
                withAnimation(OBMotion.moderate) { visible = true }
                withAnimation(OBMotion.slow) { arrived = true }
                guard await pause(1.0) else { return }
                withAnimation(OBMotion.fast) { pressing = true }
                guard await pause(0.12) else { return }
                withAnimation(OBMotion.fast) { pressing = false }
                isOn = true
                guard await pause(0.7) else { return }
                withAnimation(OBMotion.exit) { visible = false }
                guard await pause(2.8) else { return }
                shown = false
                guard await pause(0.3) else { return }
                isOn = false; arrived = false
                guard await pause(0.7) else { return }
                shown = true
                guard await pause(0.35) else { return }
            }
        }
    }

    private func pause(_ s: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(s))
        return !Task.isCancelled
    }
}
