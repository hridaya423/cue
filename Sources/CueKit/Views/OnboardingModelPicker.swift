import AppKit
import SwiftUI

/// Screen 4's content: "On this Mac" / "Hosted" tabs over a compact,
/// catalog-ranked picker. Presentation is deliberately separate from
/// Settings' ProviderPicker — all metadata and readiness come from
/// ModelCatalog/ModelManager, never invented.
struct OnboardingModels: View {
    var model: AppModel
    /// The screen's footer primary is stateful (Set up / Start / Continue /
    /// Test connection…) — the picker publishes it up to the shell.
    @Binding var primary: OBPrimary?

    @State private var hosted = true
    @State private var moreExpanded = false
    @State private var advancedExpanded = false
    @State private var testing = false
    @State private var testResult: AppModel.ProviderConnectionResult?
    @State private var selectedID: String = ""

    var onAdvance: () -> Void = {}

    private var settings: AppSettings { model.settings }

    init(model: AppModel, primary: Binding<OBPrimary?>, onAdvance: @escaping () -> Void) {
        self.model = model
        self._primary = primary
        self.onAdvance = onAdvance
    }

    var body: some View {
        VStack(spacing: 0) {
            activeFold
        }
        .onAppear(perform: seedSelection)
        .onChange(of: hosted) { _, _ in syncPrimary() }
        .onChange(of: selectedID) { _, _ in syncPrimary() }
        .onChange(of: settings.provider.rawValue) { _, _ in syncPrimary() }
        .onChange(of: settings.localVariantID) { _, _ in syncPrimary() }
        .onChange(of: model.models.states) { _, _ in syncPrimary() }
        .onChange(of: testResult) { _, _ in syncPrimary() }
        .onChange(of: testing) { _, _ in syncPrimary() }
    }

    // MARK: - Local tab

    /// Catalog order: supported models first by rank for the visible list,
    /// the rest (experimental + unsupported) behind "More models".
    private var ranked: [ModelSpec] { ModelCatalog.all.sorted { $0.rank < $1.rank } }
    private var headline: [ModelSpec] {
        ranked.filter { !$0.support.isUnsupported }.prefix(3).map { $0 }
    }
    private var rest: [ModelSpec] {
        let head = Set(headline.map(\.id))
        return ranked.filter { !head.contains($0.id) }
    }

    @ViewBuilder
    private var activeFold: some View {
        FoldOut(verticalPadding: 12, lowerTopPadding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                OBSegmented(items: [(true, "Hosted"), (false, "On this Mac")],
                            selection: $hosted)
                    .frame(width: 240)
                    .frame(maxWidth: .infinity)
                if hosted { hostedUpper } else { localUpper }
            }
        } lower: {
            VStack(alignment: .leading, spacing: 10) {
                if hosted { hostedLower } else { localLower }
            }
        }
    }

    private var selectedSpec: ModelSpec? {
        ModelCatalog.model(selectedID) ?? headline.first
    }

    private var localUpper: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(headline.enumerated()), id: \.element.id) { i, spec in
                if i > 0 { Divider().padding(.leading, 68) }
                modelRow(spec)
            }
            if !rest.isEmpty {
                Divider().padding(.leading, 68)
                DisclosureGroup(isExpanded: $moreExpanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rest) { spec in modelRow(spec) }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("More models")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OBTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func modelRow(_ spec: ModelSpec) -> some View {
        let selected = selectedID == spec.id
        return Button {
            selectedID = spec.id
            // Selecting is confirming: persist through the real bindings.
            settings.provider = .local
            settings.localModelID = spec.id
            if spec.variants.allSatisfy({ $0.id != settings.localVariantID }),
               let def = ModelCatalog.defaultVariant(of: spec) {
                settings.localVariantID = def.id
            }
        } label: {
            HStack(spacing: 12) {
                OBRadio(selected: selected)
                ModelMark(modelID: spec.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text(spec.reason)
                        .font(.system(size: 13))
                        .foregroundStyle(OBTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                if spec.rank == 1 {
                    Text("Recommended")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OBTheme.action)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OBTheme.selectionFill, in: Capsule())
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? OBTheme.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? OBTheme.selectionStroke : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .opacity(spec.support.isUnsupported ? 0.5 : 1)
    }

    /// Lower sheet: the selected model's real detail — variant choice,
    /// disk/RAM, support tier, live manager status.
    private var localLower: some View {
        Group {
            if let spec = selectedSpec {
                let v = resolvedVariant(spec)
                let state = model.models.status(of: spec.id)
                VStack(alignment: .leading, spacing: 8) {
                    // First run shows what the choice means; weight sizes live in Settings.
                    Text(spec.blurb)
                        .font(.system(size: 12))
                        .foregroundStyle(OBTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let v { meta("Private, on this Mac · uses \(v.ramLabel) memory") }
                    if case .experimental(let why) = spec.support {
                        Text("Experimental · \(why)")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    if case .unsupported(let why) = spec.support {
                        Text("Unavailable here · \(why)")
                            .font(.system(size: 11))
                            .foregroundStyle(OBTheme.textTertiary)
                    }
                    setupStatus(spec, variant: v, state: state)
                }
            }
        }
    }

    private func meta(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(OBTheme.textTertiary)
    }

    @ViewBuilder
    private func setupStatus(_ spec: ModelSpec, variant: WeightSpec?, state: ModelManager.State) -> some View {
        switch state {
        case .installing(let phase):
            let transfer = model.models.transfers[spec.id]
            transferStatus(transfer, label: readablePhase(phase), downloading: "Downloading model runtime",
                           symbol: "arrow.down.circle")
        case .starting:
            let transfer = model.models.transfers[spec.id]
            transferStatus(transfer, label: "Loading weights · checking the first decision",
                           downloading: "Downloading model weights", symbol: "cpu")
        case .running:
            let duration = model.models.warmupMilliseconds[spec.id]
            Label(duration.map { "Ready · first decision \($0) ms" } ?? "Ready",
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.circle")
                .font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        case .installed:
            if let variant,
               model.models.installedVariant(of: spec.id) != variant.id {
                Label("A different size is installed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else {
                Label("Downloaded · ready to start", systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
            }
        case .notInstalled:
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                Text("\(variant?.diskLabel ?? "Model weights") to download")
            }
            .font(.system(size: 12)).foregroundStyle(OBTheme.textTertiary)
        }
    }

    private func transferStatus(
        _ transfer: ModelTransferProgress?, label: String, downloading: String, symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: transfer == nil ? symbol : "arrow.down.circle.fill")
                    .foregroundStyle(OBTheme.action)
                Text(transfer == nil ? label : downloading)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OBTheme.textSecondary)
                Spacer(minLength: 4)
                if let transfer {
                    Text("\(Int(transfer.fraction * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(OBTheme.textTertiary)
                }
            }
            if let transfer {
                ProgressView(value: transfer.fraction).tint(OBTheme.action)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func readablePhase(_ phase: String) -> String {
        switch phase {
        case "preparing": "Preparing model"
        case "creating venv": "Preparing its runtime"
        case "installing packages", "installing dependencies": "Downloading model runtime"
        case "cloning repo": "Fetching model files"
        default: phase.capitalized
        }
    }

    // MARK: - Hosted tab

    private var hostedUpper: some View {
        VStack(alignment: .leading, spacing: 0) {
            hostedRow(.jevDirect, title: "TypeSafe direct",
                      detail: "TypeSafe · jev-latest")
            Divider().padding(.leading, 68)
            hostedRow(.jevGateway, title: "AI Gateway",
                      detail: "Vercel AI Gateway · typesafe-ai/jev")
        }
    }

    private func hostedRow(_ p: AppSettings.Provider, title: String, detail: String) -> some View {
        let selected = settings.provider == p
        return Button {
            settings.provider = p
            invalidateTest()
        } label: {
            HStack(spacing: 12) {
                OBRadio(selected: selected)
                ProviderMark(asset: p == .jevDirect ? "typesafe" : "vercel", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(OBTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var hostedLower: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.provider == .jevDirect || settings.provider == .jevGateway {
                LabeledContent {
                    SecureField("API key", text: keyBinding)
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text(settings.provider == .jevGateway ? "Gateway key" : "API key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OBTheme.textSecondary)
                }
                testStatusLine
            } else {
                Text("Pick a hosted provider above.")
                    .font(.system(size: 13)).foregroundStyle(OBTheme.textTertiary)
            }

            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    advancedRow(.custom, "Custom endpoint",
                                "Any server answering POST {base}/v1/systemone")
                    if settings.provider == .custom {
                        LabeledContent("Endpoint") {
                            TextField("https://host:port", text: customURLBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Model") {
                            TextField("model", text: customModelBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                        SecureField("Bearer key (optional)", text: customKeyBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    advancedRow(.off, "No model",
                                "Smart paste will use ordinary paste until you choose a model.")
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced — custom endpoint or no model")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OBTheme.textSecondary)
            }
        }
    }

    private func advancedRow(_ p: AppSettings.Provider, _ title: String, _ detail: String) -> some View {
        let selected = settings.provider == p
        return Button {
            settings.provider = p
            invalidateTest()
        } label: {
            HStack(spacing: 12) {
                OBRadio(selected: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text(detail).font(.system(size: 12))
                        .foregroundStyle(OBTheme.textSecondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var testStatusLine: some View {
        switch testResult {
        case .connected(let m):
            Label("Connected — \(m)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    // MARK: - Primary action sync

    /// The footer button mirrors the real model/connection state.
    private func syncPrimary() {
        if hosted {
            primary = hostedPrimary
        } else {
            primary = localPrimary
        }
    }

    private var localPrimary: OBPrimary? {
        guard let spec = selectedSpec else { return nil }
        if case .unsupported = spec.support {
            return OBPrimary(title: "Choose another model", enabled: false)
        }
        let state = model.models.status(of: spec.id)
        switch state {
        case .notInstalled:
            return OBPrimary(title: "Set up model") { setupSelected(spec) }
        case .installing:
            return OBPrimary(title: "Setting up…", enabled: false)
        case .installed:
            if let v = resolvedVariant(spec), model.models.installedVariant(of: spec.id) != v.id {
                return OBPrimary(title: "Set up selected variant") { setupSelected(spec) }
            }
            return OBPrimary(title: "Start model") { startSelected(spec) }
        case .starting:
            return OBPrimary(title: "Starting model…", enabled: false)
        case .running:
            if selectedIsRunning {
                return OBPrimary(title: "Continue") { advanceFromModels() }
            }
            return OBPrimary(title: "Set up selected size") { setupSelected(spec) }
        case .failed:
            if let variant = resolvedVariant(spec),
               model.models.installedVariant(of: spec.id) == variant.id {
                return OBPrimary(title: "Retry start") { startSelected(spec) }
            }
            return OBPrimary(title: "Retry setup") { setupSelected(spec) }
        }
    }

    private var hostedPrimary: OBPrimary {
        switch settings.provider {
        case .off:
            // Primary stays the forward action; the quiet Finish-later link
            // sits in the footer corner.
            return OBPrimary(title: "Continue") { advanceFromModels() }
        case .jevDirect, .jevGateway, .custom:
            if settings.provider.needsAPIKey,
               (settings.provider == .jevGateway ? settings.gatewayKey : settings.apiKey)?.isEmpty != false {
                return OBPrimary(title: "Test connection", enabled: false)
            }
            if testing { return OBPrimary(title: "Testing…", enabled: false) }
            if case .connected = testResult {
                return OBPrimary(title: "Continue") { advanceFromModels() }
            }
            return OBPrimary(title: "Test connection") { runTest() }
        case .local:
            // Local selection while on the hosted tab → treat as Continue.
            return OBPrimary(title: "Continue") { advanceFromModels() }
        }
    }

    // MARK: - Actions

    private func seedSelection() {
        // On-device is the default: nothing to sign up for, nothing leaves the Mac. Hosted opens first
        // only for someone who already chose it.
        hosted = settings.provider == .jevDirect || settings.provider == .jevGateway
        selectedID = ModelCatalog.model(settings.localModelID)?.id ?? headline.first?.id ?? ""
        moreExpanded = rest.contains { $0.id == selectedID }
        syncPrimary()
    }

    private func resolvedVariant(_ spec: ModelSpec) -> WeightSpec? {
        spec.variants.first { $0.id == settings.localVariantID }
            ?? ModelCatalog.defaultVariant(of: spec)
    }

    private func setupSelected(_ spec: ModelSpec) {
        settings.provider = .local
        settings.localModelID = spec.id
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        Task {
            model.models.stop()
            await model.models.install(r)
            guard case .installed = model.models.status(of: spec.id) else { return }
            await model.models.start(r)
        }
    }

    private func startSelected(_ spec: ModelSpec) {
        settings.provider = .local
        settings.localModelID = spec.id
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        Task { await model.models.start(r) }
    }

    /// The running server must be *this* model+variant to enable Continue.
    private var selectedIsRunning: Bool {
        guard let spec = selectedSpec, model.models.status(of: spec.id) == .running,
              let v = resolvedVariant(spec) else { return false }
        return model.models.installedVariant(of: spec.id) == v.id
    }

    private func advanceFromModels() { onAdvance() }
    private func configFingerprint() -> [String] {
        [settings.provider.rawValue, settings.model, settings.customURL,
         settings.apiKey ?? "", settings.gatewayKey ?? "", settings.customKey ?? ""]
    }

    private func runTest() {
        testing = true
        let fp = configFingerprint()
        Task {
            let result = await model.testConnection()
            await MainActor.run {
                testing = false
                // Stale result: user changed provider/key mid-flight → discard.
                guard configFingerprint() == fp else { return }
                testResult = result
            }
        }
    }

    private func invalidateTest() {
        testResult = nil
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { settings.provider == .jevGateway
                ? settings.gatewayKey ?? "" : settings.apiKey ?? "" },
            set: {
                if settings.provider == .jevGateway {
                    settings.gatewayKey = $0.isEmpty ? nil : $0
                } else {
                    settings.apiKey = $0.isEmpty ? nil : $0
                }
                invalidateTest()
            }
        )
    }
    private var customURLBinding: Binding<String> {
        Binding(get: { settings.customURL },
                set: { settings.customURL = $0; invalidateTest() })
    }
    private var customModelBinding: Binding<String> {
        Binding(get: { settings.customModel },
                set: { settings.customModel = $0; invalidateTest() })
    }
    private var customKeyBinding: Binding<String> {
        Binding(get: { settings.customKey ?? "" },
                set: { settings.customKey = $0.isEmpty ? nil : $0; invalidateTest() })
    }
}

private extension ModelSpec.Support {
    var isUnsupported: Bool { if case .unsupported = self { return true }; return false }
}

private struct ProviderMark: View {
    var asset: String
    var size: CGFloat

    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: asset, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .frame(width: size, height: size)
                    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                Image(systemName: "network")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(OBTheme.textSecondary)
                    .frame(width: size, height: size)
                    .background(OBTheme.textTertiary.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .stroke(OBTheme.separator.opacity(0.65), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private struct ModelMark: View {
    var modelID: String
    var size: CGFloat = 32

    private var symbol: String {
        switch modelID {
        case "kev": "cpu"
        case "von": "waveform.path"
        case "jevons": "leaf"
        case "jevlite": "sparkles"
        case "decider": "slider.horizontal.3"
        default: "cpu"
        }
    }

    private var tint: Color {
        switch modelID {
        case "kev": Color(red: 0.43, green: 0.39, blue: 0.86)
        case "von": Color(red: 0.12, green: 0.54, blue: 0.78)
        case "jevons": Color(red: 0.19, green: 0.57, blue: 0.42)
        case "jevlite": Color(red: 0.62, green: 0.46, blue: 0.79)
        default: OBTheme.textSecondary
        }
    }

    var body: some View {
        Group {
            if modelID == "laya" {
                ProviderMark(asset: "laya", size: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(tint.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
