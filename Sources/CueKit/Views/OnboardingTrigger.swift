import SwiftUI

extension OnboardingView {
    var triggerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            triggerRow(
                title: "Use \u{2318}V",
                detail: "Cue pastes what fits the field. Your shortcut still shows the choices.",
                selected: settings.triggerMode == .intercept
            ) {
                setTrigger(.intercept)
            } accessory: {
                EmptyView()
            }
            triggerRow(
                title: "Only my shortcut",
                detail: "\u{2318}V stays ordinary. Cue steps in when you ask.",
                selected: settings.triggerMode == .hotkey
            ) {
                setTrigger(.hotkey)
            } accessory: {
                EmptyView()
            }
            HStack(spacing: 10) {
                Text("Shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OBTheme.textSecondary)
                HotkeyRecorder(
                    value: settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
                        ?? HotkeyManager.Action.smartPaste.default
                ) { hk in recordSmartPaste(hk) }
                .frame(width: 116, height: 30)
            }
            .padding(.top, 8)
            if let recorderConflict {
                Text(recorderConflict)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    var triggerStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Copied message")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OBTheme.textTertiary)
                    HighlightedParagraph(
                        text: "Reach Mira at mira@example.com or +44 7700 900123.",
                        highlights: [OnboardingSample.Target.email.expected],
                        fontSize: 15, width: 336)
                }
            }
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OBTheme.textTertiary)
                    Text(OnboardingSample.Target.email.expected)
                        .font(.system(size: 15))
                        .foregroundStyle(OBTheme.textPrimary)
                }
            }
        }
    }

    func triggerRow<Accessory: View>(
        title: String, detail: String, selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    OBRadio(selected: selected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OBTheme.textPrimary)
                        Text(detail).font(.system(size: 13))
                            .foregroundStyle(OBTheme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    func setTrigger(_ mode: AppSettings.TriggerMode) {
        settings.triggerMode = mode
        model.hotkeys.interceptCmdV = mode == .intercept
    }

    /// Reject bindings that collide with another Cue action — the recorder
    /// keeps its prior value when we refuse to persist.
    func recordSmartPaste(_ hk: AppSettings.Hotkey) {
        for action in HotkeyManager.Action.allCases where action != .smartPaste {
            let other = settings.hotkey(for: action.rawValue) ?? action.default
            if other.keyCode == hk.keyCode && other.modifiers == hk.modifiers {
                recorderConflict = "That shortcut is already used for “\(action.title)”."
                return
            }
        }
        recorderConflict = nil
        settings.setHotkey(hk, for: HotkeyManager.Action.smartPaste.rawValue)
        model.hotkeys.reregister()
    }

}
