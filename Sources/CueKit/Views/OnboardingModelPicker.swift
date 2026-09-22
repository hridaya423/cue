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

    @State private var hosted = false
    @State private var moreExpanded = false
    @State private var advancedExpanded = false
    @State private var testing = false
    @State private var testResult: AppModel.ProviderConnectionResult?
    @State private var selectedID: String = ""

    var onAdvance: () -> Void = {}
    var onFinishLater: () -> Void = {}

    private var settings: AppSettings { model.settings }

    init(model: AppModel, primary: Binding<OBPrimary?>,
         onAdvance: @escaping () -> Void, onFinishLater: @escaping () -> Void) {
        self.model = model
        self._primary = primary
        self.onAdvance = onAdvance
        self.onFinishLater = onFinishLater
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $hosted) {
                Text("On this Mac").tag(false)
                Text("Hosted").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

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
        .onChange(of: moreExpanded) { _, _ in syncPrimary() }
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
        if hosted {
            FoldOut { hostedUpper } lower: { hostedLower }
        } else {
            FoldOut { localUpper } lower: { localLower }
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
                .padding(.vertical, 8)
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
                Text(String(spec.title.prefix(1)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OBTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(OBTheme.textTertiary.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text(spec.reason)
                        .font(.system(size: 13))
                        .foregroundStyle(OBTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if spec.rank == 1 {
                    Text("Recommended")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OBTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
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
                    HStack {
                        Text(spec.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OBTheme.textPrimary)
                        if case .unsupported(let why) = spec.support {
                            Text("Not installable on this Mac — \(why)")
                                .font(.system(size: 12))
                                .foregroundStyle(OBTheme.textTertiary)
                        } else if case .experimental(let why) = spec.support {
                            Text("Experimental — \(why)")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        if spec.variants.count > 1 {
                            Picker("Weights", selection: variantBinding(spec)) {
                                ForEach(spec.variants) { w in
                                    Text(w.paramsLabel).tag(w.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                    HStack(spacing: 16) {
                        if let v {
                            meta("\(v.paramsLabel) params")
                            meta("\(v.diskLabel) disk")
                            meta("\(v.ramLabel) RAM")
                        }
                        Spacer()
                        statusText(spec, state: state)
                    }
                }
            }
        }
    }

    private func meta(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(OBTheme.textTertiary)
    }

    @ViewBuilder
    private func statusText(_ spec: ModelSpec, state: ModelManager.State) -> some View {
        switch state {
        case .installing(let phase):
            Label(phase, systemImage: "arrow.down.circle")
                .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
        case .starting:
            Text("Starting — first launch downloads weights")
                .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let msg):
            Text(msg).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        case .installed:
            if let v = resolvedVariant(spec),
               model.models.installedVariant(of: spec.id) != v.id {
                Text("Different weights installed — setup will replace them")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else {
                Text("Installed").font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
            }
        case .notInstalled:
            Text("Not installed").font(.system(size: 12)).foregroundStyle(OBTheme.textTertiary)
        }
    }

    // MARK: - Hosted tab

    private var hostedUpper: some View {
        VStack(alignment: .leading, spacing: 0) {
            hostedRow(.jevDirect, title: "TypeSafe direct",
                      detail: "api.typesafe.ai · jev-latest")
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
                Text("J")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OBTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(OBTheme.textTertiary.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .frame(minHeight: 60)
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
            // Only "running" when the running server is this model+variant.
            return OBPrimary(title: "Continue") { advanceFromModels() }
        case .failed:
            // Retry the failed phase — installed manifests retry start only.
            if model.models.installedVariant(of: spec.id) != nil {
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
        switch settings.provider {
        case .local:
            hosted = false
            selectedID = settings.localModelID.isEmpty
                ? (headline.first?.id ?? "") : settings.localModelID
        case .off:
            // Fresh Off shows the hosted tab; Advanced stays collapsed —
            // expanding it is the user's act.
            hosted = true
            selectedID = headline.first?.id ?? ""
        default:
            hosted = true
            selectedID = headline.first?.id ?? ""
        }
        syncPrimary()
    }

    private func resolvedVariant(_ spec: ModelSpec) -> WeightSpec? {
        spec.variants.first { $0.id == settings.localVariantID }
            ?? ModelCatalog.defaultVariant(of: spec)
    }

    private func variantBinding(_ spec: ModelSpec) -> Binding<String> {
        Binding(get: { resolvedVariant(spec)?.id ?? "" },
                set: { settings.localVariantID = $0 })
    }

    private func setupSelected(_ spec: ModelSpec) {
        settings.provider = .local
        settings.localModelID = spec.id
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        Task { await model.models.install(r); await model.models.start(r) }
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
    private func finishLater() { onFinishLater() }

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
