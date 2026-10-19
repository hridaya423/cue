import SwiftUI

extension OnboardingView {
    /// Locality from the real endpoint, not the conservative mayBeRemote —
    /// a loopback custom endpoint is local.
    var privacyIsRemote: Bool {
        switch settings.provider {
        case .jevDirect, .jevGateway: true
        case .local, .off: false
        case .custom: model.makeProvider()?.isRemote ?? false
        }
    }

    var privacyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Hide names and emails from hosted models", isOn: redactionToggle)
                .toggleStyle(.switch)
                .font(.system(size: 15))
                .fixedSize()
            Text("The detail you paste keeps its original text.")
                .font(.system(size: 13))
                .foregroundStyle(OBTheme.textTertiary)
            if settings.piiRedaction != nil {
                Button("Use automatic setting") { settings.piiRedaction = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(OBTheme.textTertiary)
            }
            redactorLine
        }
        .task(id: model.redactor.status) {
            if model.redactor.status == .ready {
                redactedSample = try? await model.redactor.redact(
                    "Send the launch brief to Mira at mira@example.com.")
            }
        }
    }

    var privacyStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You copied").font(.system(size: 12, weight: .semibold)).foregroundStyle(OBTheme.textTertiary)
                    HighlightedParagraph(
                        text: "Send the launch brief to Mira at mira@example.com.",
                        highlights: ["Mira", "mira@example.com"],
                        fontSize: 15, width: 336)
                }
            }
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.effectivePIIRedaction ? "The model sees" : "The model sees, unmasked")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(OBTheme.textTertiary)
                    HighlightedParagraph(
                        text: scrubbedSample,
                        highlights: Self.placeholderTokens(in: scrubbedSample),
                        fontSize: 15, width: 336, masked: true)
                }
            }
        }
    }

    /// Bracketed placeholders like `[NAME]`/`[EMAIL_1]` — whatever the real
    /// redactor emits, plus the static example's tokens.
    static func placeholderTokens(in text: String) -> [String] {
        var out: [String] = []
        for m in text.matches(of: /\[[A-Z0-9_]+\]/) {
            let t = String(m.output)
            if !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// Live redactor output when ready, else the labeled static example.
    var scrubbedSample: String {
        settings.effectivePIIRedaction
            ? redactedSample ?? "Send the launch brief to [NAME] at [EMAIL]."
            : "Send the launch brief to Mira at mira@example.com."
    }

    @ViewBuilder
    var redactorLine: some View {
        switch model.redactor.status {
        case .idle:
            EmptyView()
        case .downloading(let f):
            HStack(spacing: 8) {
                ProgressView(value: f).frame(width: 120)
                Text("Getting the redaction model… \(Int(f * 100))%")
                    .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        case .ready:
            Label("Redaction ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        case .failed(let msg):
            Label("Download failed — \(msg)", systemImage: "xmark.circle")
                .font(.system(size: 12)).foregroundStyle(.red)
                .frame(maxWidth: .infinity)
        }
    }


    /// The tri-state: toggling writes an explicit override; auto is shown as
    /// the current effective value.
    var redactionToggle: Binding<Bool> {
        Binding(
            get: { settings.effectivePIIRedaction },
            set: { settings.piiRedaction = $0 }
        )
    }

    /// Privacy primary: remote + redaction-on-but-model-missing gates on
    /// "Set up redaction" / "Downloading…" / "Retry download".
    var privacyPrimary: OBPrimary {
        guard privacyIsRemote, settings.effectivePIIRedaction else {
            return OBPrimary(title: "Continue") { advance() }
        }
        switch model.redactor.status {
        case .ready:
            return OBPrimary(title: "Continue") { advance() }
        case .downloading:
            return OBPrimary(title: "Downloading…", enabled: false)
        case .failed:
            return OBPrimary(title: "Retry download") {
                Task { await model.redactor.prepare() }
            }
        case .idle:
            return OBPrimary(title: "Set up redaction") {
                Task { await model.redactor.prepare() }
            }
        }
    }

}
