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
        OBStageCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy & Security \u{203A} Accessibility")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OBTheme.textSecondary)
                HStack(spacing: 12) {
                    Group {
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "paperclip")
                        }
                    }
                    .frame(width: 32, height: 32)
                    Text("Cue").font(.system(size: 15, weight: .medium)).foregroundStyle(OBTheme.textPrimary)
                    Spacer()
                    PermissionSwitchDemo(granted: trusted)
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 14)
            }
        }
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
