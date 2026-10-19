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
            .frame(width: 372, height: 504, alignment: .topLeading)
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

/// System Settings › Privacy & Security › Accessibility, drawn large enough to bleed off the stage's
/// bottom edge. The switch next to Cue plays a calm loop (cursor glides in, clicks, switch lights up) and
/// sleeps between loops; with Reduce Motion, or once access is granted, it shows the finished state.
struct PermissionScene: View {
    var granted: Bool
    @State private var cueOn = false
    @Environment(\.colorScheme) private var scheme

    private static let sidebar: [(String, Color, String)] = [
        ("wifi", .blue, "Wi\u{2011}Fi"), ("bell.badge.fill", .red, "Notifications"), ("speaker.wave.2.fill", .pink, "Sound"),
        ("moon.fill", .indigo, "Focus"), ("gearshape.fill", .gray, "General"), ("circle.lefthalf.filled", .blue, "Appearance"),
        ("figure.arms.open", .blue, "Accessibility"), ("hand.raised.fill", .blue, "Privacy & Security"),
    ]
    private static let apps: [(String?, Bool)] = [
        ("com.apple.Automator", false), (nil, false), ("com.apple.Notes", false), ("com.apple.Preview", false),
        ("com.apple.reminders", false), ("com.apple.Safari", true), ("com.apple.ScriptEditor2", false),
        ("com.apple.shortcuts", true), ("com.apple.Terminal", true), ("com.apple.TextEdit", false),
    ]
    private static let names = ["Automator", "Cue", "Notes", "Preview", "Reminders", "Safari", "Script Editor", "Shortcuts", "Terminal", "TextEdit"]

    var body: some View {
        ZStack(alignment: .topLeading) {
            window
                .frame(width: 424, height: 620)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.76), .init(color: .black.opacity(0.1), location: 0.95)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.16 : 0.7), lineWidth: 0.75))
                .shadow(color: Color(red: 0.01, green: 0.05, blue: 0.25).opacity(0.5), radius: 34, y: 20)
                .shadow(color: Color(red: 0.01, green: 0.05, blue: 0.25).opacity(0.3), radius: 4, y: 2)
                .offset(x: -22, y: 30)
            appIcon(NSApp.applicationIconImage, size: 88)
                .rotationEffect(.degrees(-7))
                .shadow(color: Color(red: 0.01, green: 0.05, blue: 0.25).opacity(0.45), radius: 16, y: 10)
                .offset(x: 296, y: -26)
            toast
                .offset(x: -8, y: -6)
        }
        .allowsHitTesting(false)
    }

    private var toast: some View {
        let shown = cueOn || granted
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility is on").font(.system(size: 13, weight: .semibold))
                Text("Cue can read field labels").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 48)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.6), lineWidth: 0.75))
        .shadow(color: Color(red: 0.01, green: 0.05, blue: 0.25).opacity(0.35), radius: 14, y: 8)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 8)
        .scaleEffect(shown ? 1 : 0.96, anchor: .bottomLeading)
        .animation(.spring(duration: 0.5, bounce: 0.12), value: shown)
    }

    private var window: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.9)).frame(width: 12, height: 12) }
                }
                .padding(.bottom, 10)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.bottom, 8)
                ForEach(Self.sidebar, id: \.2) { symbol, tint, title in
                    let selected = title == "Privacy & Security"
                    HStack(spacing: 7) {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text(title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .padding(.horizontal, 6)
                    .frame(height: 30)
                    .background(selected ? OBTheme.action : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .frame(width: 172)
            .background(.black.opacity(0.04))
            .overlay(alignment: .trailing) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5) }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right").opacity(0.35)
                    Text("Accessibility").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(height: 46)
                Text("Allow the applications below to control your computer.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(Array(Self.names.enumerated()), id: \.offset) { i, name in
                        if i > 0 { Divider().padding(.leading, 46) }
                        appRow(i, name)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder private func appRow(_ i: Int, _ name: String) -> some View {
        let isCue = i == 1
        let on = isCue ? cueOn || granted : Self.apps[i].1
        HStack(spacing: 10) {
            if isCue {
                appIcon(NSApp.applicationIconImage, size: 28)
            } else {
                appIcon(Self.icon(Self.apps[i].0), size: 28)
            }
            Text(name).font(.system(size: 13, weight: isCue ? .semibold : .regular))
            Spacer()
            if isCue {
                PermissionSwitchDemo(granted: granted, isOn: $cueOn)
            } else {
                SettingsSwitch(on: on)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(isCue ? OBTheme.action.opacity(cueOn || granted ? 0.1 : 0) : .clear)
        .animation(.easeOut(duration: 0.4), value: cueOn)
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

/// A macOS switch; the knob slides with a spring and the track fills with the accent.
struct SettingsSwitch: View {
    var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? OBTheme.action : Color.primary.opacity(0.16))
            .frame(width: 38, height: 22)
            .overlay {
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: on ? 8 : -8)
            }
            .animation(.spring(duration: 0.3, bounce: 0.18), value: on)
    }
}

/// Cue's switch: a cursor glides in, clicks, the switch lights up with a ring and a soft glow, the scene
/// holds, then resets. Every pause is a sleep, so nothing redraws between steps.
struct PermissionSwitchDemo: View {
    var granted: Bool
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var visible = false
    @State private var pressing = false
    @State private var ring = false

    private static let away = CGSize(width: -150, height: 120)

    var body: some View {
        let lit = isOn || granted
        ZStack {
            Circle()
                .fill(OBTheme.action)
                .frame(width: 64, height: 64)
                .blur(radius: 16)
                .opacity(lit ? 0.55 : 0)
                .scaleEffect(lit ? 1 : 0.4)
            Capsule()
                .strokeBorder(OBTheme.action.opacity(0.7), lineWidth: 2)
                .frame(width: 38, height: 22)
                .scaleEffect(ring ? 2.1 : 1)
                .opacity(ring ? 0 : (lit && !reduceMotion ? 0.8 : 0))
            SettingsSwitch(on: lit)
                .shadow(color: OBTheme.action.opacity(lit ? 0.55 : 0), radius: 8)
        }
        .animation(.easeOut(duration: 0.5), value: lit)
        .overlay(alignment: .topLeading) {
            if !reduceMotion && !granted {
                Image(nsImage: NSCursor.arrow.image)
                    .scaleEffect(1.35, anchor: .topLeading)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .scaleEffect(pressing ? 0.86 : 1, anchor: .topLeading)
                    .opacity(visible ? 1 : 0)
                    .offset(arrived ? CGSize(width: 12, height: 12) : Self.away)
            }
        }
        .frame(width: 38, height: 22)
        .task(id: granted || reduceMotion) {
            guard !granted && !reduceMotion else { isOn = true; return }
            while !Task.isCancelled {
                isOn = false; ring = false; arrived = false
                guard await pause(0.5) else { return }
                withAnimation(.easeOut(duration: 0.3)) { visible = true }
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.3)) { arrived = true }
                guard await pause(1.5) else { return }
                withAnimation(.easeOut(duration: 0.1)) { pressing = true }
                guard await pause(0.14) else { return }
                withAnimation(.easeOut(duration: 0.14)) { pressing = false }
                isOn = true
                withAnimation(.easeOut(duration: 0.9)) { ring = true }
                guard await pause(1.4) else { return }
                withAnimation(.easeIn(duration: 0.4)) { visible = false }
                guard await pause(3.0) else { return }
                isOn = false
                guard await pause(1.0) else { return }
            }
        }
    }

    private func pause(_ s: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(s))
        return !Task.isCancelled
    }
}
