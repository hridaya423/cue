import AppKit
import SwiftUI

/// Screen 4's content: the one recommended model, with every other choice behind "Other options".
/// All metadata and readiness come from ModelCatalog/ModelManager, never invented. A local model
/// downloads in the background: Continue never waits on it, and until it is ready a paste stays plain.
struct OnboardingModels: View {
    var model: AppModel
    /// The screen's footer primary is stateful (Continue / Test connection…) — the picker publishes it up to the shell.
    @Binding var primary: OBPrimary?

    enum Choice: Equatable {
        case local(String), hosted, gateway, custom, off
    }

    @State private var choice: Choice = .off
    @State private var expanded = false
    @State private var browsing = false
    @State private var advancedExpanded = false
    @State private var testing = false
    @State private var testResult: AppModel.ProviderConnectionResult?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onAdvance: () -> Void = {}

    private var settings: AppSettings { model.settings }

    init(model: AppModel, primary: Binding<OBPrimary?>, onAdvance: @escaping () -> Void) {
        self.model = model
        self._primary = primary
        self.onAdvance = onAdvance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if browsing {
                browser
            } else if expanded {
                ForEach(headline) { localRow($0) }
                if let spec = selectedSpec, !headline.contains(where: { $0.id == spec.id }) { localRow(spec) }
                if !rest.isEmpty { moreButton }
                hostedRow
                disclosure("Advanced", isExpanded: $advancedExpanded) {
                    gatewayRow
                    customRow
                    offRow
                }
            } else {
                selectedRow
                Button {
                    withAnimation(reduceMotion ? nil : OBMotion.moderate) { expanded = true }
                } label: {
                    HStack(spacing: 4) {
                        Text("Other options")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OBTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: seedSelection)
        .onChange(of: choice) { _, _ in syncPrimary() }
        .onChange(of: settings.localVariantID) { _, _ in syncPrimary() }
        .onChange(of: model.models.states) { _, _ in syncPrimary() }
        .onChange(of: testResult) { _, _ in syncPrimary() }
        .onChange(of: testing) { _, _ in syncPrimary() }
    }

    // MARK: - Rows

    /// Catalog order: the role holders first, everything else behind "More models".
    private var headline: [ModelSpec] { ModelCatalog.featured }
    /// Everything that can run here: supported before experimental, each in catalog order.
    private var rest: [ModelSpec] {
        let head = Set(headline.map(\.id))
        let usable = ModelCatalog.all.sorted { $0.rank < $1.rank }
            .filter { !head.contains($0.id) && !$0.support.isUnsupported }
        return usable.filter { $0.support == .supported } + usable.filter { $0.support != .supported }
    }

    private var moreButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : OBMotion.moderate) { browsing = true }
        } label: {
            HStack(spacing: 4) {
                Text("More models")
                Text("\(rest.count)").foregroundStyle(OBTheme.textTertiary).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OBTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The long tail as one bounded, scrolling panel: measured numbers where Cue has them, nothing invented.
    private var browser: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : OBMotion.moderate) { browsing = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("More models")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OBTheme.textSecondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rest) { spec in
                        BrowseRow(spec: spec, facts: browseFacts(spec), selected: selectedSpec?.id == spec.id) {
                            select(.local(spec.id))
                        }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.automatic)
            .frame(height: 252)
            .background(OBTheme.sheet, in: shape)
            .overlay(shape.stroke(OBTheme.separator, lineWidth: 0.5))
        }
        .transition(.opacity)
    }

    private func browseFacts(_ spec: ModelSpec) -> String {
        let size = resolvedVariant(spec)?.diskLabel
        guard let b = ModelRoles.benchmark(of: spec.id) else {
            return ["Not measured yet", size].compactMap { $0 }.joined(separator: " · ")
        }
        return ["\(Int((b.resolved * 100).rounded()))% right", "\(Int(b.p95)) ms", size]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var selectedSpec: ModelSpec? {
        if case .local(let id) = choice { return ModelCatalog.model(id) ?? headline.first }
        return nil
    }

    @ViewBuilder private var selectedRow: some View {
        switch choice {
        case .local:
            if let spec = selectedSpec { localRow(spec) }
        case .hosted: hostedRow
        case .gateway: gatewayRow
        case .custom: customRow
        case .off: offRow
        }
    }

    private func localRow(_ spec: ModelSpec) -> some View {
        let v = resolvedVariant(spec)
        let state = model.models.status(of: spec.id)
        let size = state == .notInstalled ? v.map { "\($0.diskLabel) download" } : v.map { "\($0.ramLabel) memory" }
        let facts = [spec.reason, size].compactMap { $0 }.joined(separator: " · ")
        return optionRow(choice: .local(spec.id), title: spec.title, subtitle: facts,
                         recommended: spec.rank == 1, dimmed: spec.support.isUnsupported) {
            ModelMark(modelID: spec.id)
        } detail: {
            if case .experimental(let why) = spec.support {
                Text("Experimental · \(why)").font(.system(size: 11)).foregroundStyle(.orange)
            }
            if case .unsupported(let why) = spec.support {
                Text("Unavailable here · \(why)").font(.system(size: 11)).foregroundStyle(OBTheme.textTertiary)
            }
            if state != .notInstalled { setupStatus(spec, variant: v, state: state) }
        }
    }

    private var hostedRow: some View {
        optionRow(choice: .hosted, title: "Hosted", subtitle: "No download · needs a TypeSafe key") {
            ProviderMark(asset: "typesafe", size: 32)
        } detail: {
            keyField
        }
    }

    private var gatewayRow: some View {
        optionRow(choice: .gateway, title: "Vercel AI Gateway", subtitle: "The hosted model through your Vercel key") {
            ProviderMark(asset: "vercel", size: 32)
        } detail: {
            keyField
        }
    }

    private var customRow: some View {
        optionRow(choice: .custom, title: "Custom endpoint", subtitle: "Your own System One server") {
            ProviderMark(asset: "", size: 32)
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                TextField("https://host:port", text: customURLBinding).textFieldStyle(.roundedBorder)
                TextField("Model", text: customModelBinding).textFieldStyle(.roundedBorder)
                SecureField("Bearer key (optional)", text: customKeyBinding).textFieldStyle(.roundedBorder)
                testStatusLine
            }
        }
    }

    private var offRow: some View {
        optionRow(choice: .off, title: "No model", subtitle: "Every paste stays plain until you choose one") {
            ProviderMark(asset: "", size: 32, fallback: "nosign")
        } detail: {
            EmptyView()
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(choice == .gateway ? "Gateway key" : "API key", text: keyBinding)
                .textFieldStyle(.roundedBorder)
            testStatusLine
        }
    }

    private func optionRow<Mark: View, Detail: View>(
        choice option: Choice, title: String, subtitle: String, recommended: Bool = false, dimmed: Bool = false,
        @ViewBuilder mark: () -> Mark, @ViewBuilder detail: () -> Detail
    ) -> some View {
        let selected = choice == option
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Button { select(option) } label: {
                HStack(spacing: 12) {
                    mark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OBTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(OBTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 6)
                    if recommended {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(OBTheme.action)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selected ? OBTheme.canvas : OBTheme.selectionFill, in: Capsule())
                            .fixedSize()
                    }
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if selected { detail().padding(.leading, 44) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? OBTheme.selectionFill : .clear, in: shape)
        .overlay(shape.stroke(selected ? OBTheme.selectionStroke : .clear, lineWidth: 1))
        .opacity(dimmed ? 0.5 : 1)
    }

    private func disclosure<Content: View>(
        _ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        let rows = content()
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 6) { rows }.padding(.top, 6)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OBTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Selecting is confirming: hosted choices persist at once so the key field and the test read them.
    private func select(_ option: Choice) {
        withAnimation(reduceMotion ? nil : OBMotion.fast) { choice = option }
        switch option {
        case .local(let id):
            settings.provider = .local
            settings.localModelID = id
            if let spec = ModelCatalog.model(id), spec.variants.allSatisfy({ $0.id != settings.localVariantID }),
               let def = ModelCatalog.defaultVariant(of: spec) {
                settings.localVariantID = def.id
            }
        case .hosted: settings.provider = .jevDirect
        case .gateway: settings.provider = .jevGateway
        case .custom: settings.provider = .custom
        case .off: settings.provider = .off
        }
        testResult = nil
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


    @ViewBuilder
    private var testStatusLine: some View {
        switch testResult {
        case .connected(let m):
            Label("Connected to \(m)", systemImage: "checkmark.circle.fill")
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
        ModelsStageChoice.shared.pick = stagePick
        switch choice {
        case .local: primary = localPrimary
        case .off: primary = OBPrimary(title: "Continue") { onAdvance() }
        case .hosted, .gateway, .custom: primary = hostedPrimary
        }
    }

    /// What the right-hand stage demonstrates: the picker's live choice.
    private var stagePick: ModelsStageScene.Pick {
        switch choice {
        case .local: .init(name: selectedSpec?.title ?? "On-device model", detail: "On this Mac · private", symbol: "lock.fill")
        case .hosted, .gateway: .init(name: settings.provider.title, detail: "Hosted", symbol: "cloud.fill")
        case .custom: .init(name: "Custom endpoint", detail: "Your server", symbol: "network")
        case .off: .init(name: "No model", detail: "Plain paste", symbol: "nosign")
        }
    }

    private var localPrimary: OBPrimary? {
        guard let spec = selectedSpec else { return nil }
        if spec.support.isUnsupported { return OBPrimary(title: "Choose another model", enabled: false) }
        return OBPrimary(title: "Continue") {
            prepare(spec)
            onAdvance()
        }
    }

    private var hostedPrimary: OBPrimary {
        if settings.provider.needsAPIKey,
           (settings.provider == .jevGateway ? settings.gatewayKey : settings.apiKey)?.isEmpty != false {
            return OBPrimary(title: "Test connection", enabled: false)
        }
        if testing { return OBPrimary(title: "Testing…", enabled: false) }
        if case .connected = testResult {
            return OBPrimary(title: "Continue") { onAdvance() }
        }
        return OBPrimary(title: "Test connection") { runTest() }
    }

    // MARK: - Actions

    private func seedSelection() {
        let recommended = headline.first?.id ?? ""
        switch settings.provider {
        case .jevDirect: choice = .hosted
        case .jevGateway: choice = .gateway
        case .custom: choice = .custom
        // A first run arrives with no provider: show the recommended model, saved only on Continue.
        case .local, .off: choice = .local(ModelCatalog.model(settings.localModelID)?.id ?? recommended)
        }
        advancedExpanded = [.gateway, .custom].contains(choice)
        #if DEBUG
        if let open = ProcessInfo.processInfo.environment["OB_MODELS_OPEN"] {
            expanded = true
            browsing = open == "more"
        }
        #endif
        syncPrimary()
    }

    private func resolvedVariant(_ spec: ModelSpec) -> WeightSpec? {
        spec.variants.first { $0.id == settings.localVariantID }
            ?? ModelCatalog.defaultVariant(of: spec)
    }

    /// Saves the choice and gets the model ready without waiting on it: install if needed, then start.
    private func prepare(_ spec: ModelSpec) {
        select(.local(spec.id))
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        let models = model.models
        let wanted = models.installedVariant(of: spec.id) == r.variant.id
        switch models.status(of: spec.id) {
        case .installing, .starting: return
        case .running where wanted: return
        case .installed where wanted, .failed where wanted:
            Task { await models.start(r) }
        default:
            Task {
                models.stop()
                await models.install(r)
                guard case .installed = models.status(of: spec.id) else { return }
                await models.start(r)
            }
        }
    }

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
    var fallback = "network"

    private var image: NSImage? {
        guard !asset.isEmpty, let url = Bundle.module.url(forResource: asset, withExtension: "png") else { return nil }
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
                Image(systemName: fallback)
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

/// The background setup's one line in the footer, so a model downloading after Continue is never silent.
struct OBModelProgress: View {
    var model: AppModel

    var body: some View {
        if model.settings.provider == .local, let spec = ModelCatalog.model(model.settings.localModelID) {
            let transfer = model.models.transfers[spec.id]
            let percent = transfer.map { " \(Int($0.fraction * 100))%" } ?? ""
            switch model.models.status(of: spec.id) {
            case .installing, .starting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(transfer == nil ? "Setting up \(spec.title)" : "Downloading \(spec.title)\(percent)")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            case .failed:
                Text("\(spec.title) didn\u{2019}t set up. Retry in Settings.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            default:
                EmptyView()
            }
        }
    }
}

private struct BrowseRow: View {
    var spec: ModelSpec
    var facts: String
    var selected: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(spec.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OBTheme.textPrimary)
                        if case .experimental = spec.support {
                            Text("Experimental")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(facts)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(OBTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OBTheme.action)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(selected ? OBTheme.selectionFill : hover ? OBTheme.textTertiary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
