import SwiftUI

/// The hierarchical provider picker shared by onboarding and Settings.
/// Rows: Jev → Kev → Laya → Other local models → Custom endpoint → Off.
/// Selecting a row sets `settings.provider`; rows expand to their detail.
public struct ProviderPicker: View {
    var model: AppModel

    @State private var testing = false
    @State private var testResult: String?
    @State private var othersExpanded = false

    public init(model: AppModel) { self.model = model }

    private var settings: AppSettings { model.settings }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            jevRow
            localRow(ModelCatalog.kev)
            localRow(ModelCatalog.laya)
            othersRow
            customRow
            offRow
        }
    }

    // MARK: - Rows

    private var jevRow: some View {
        row(
            title: "Jev",
            detail: "TypeSafe's hosted decision model — best quality, ~100ms. Via TypeSafe direct or Vercel AI Gateway.",
            selected: settings.provider == .jevDirect || settings.provider == .jevGateway
        ) {
            if settings.provider != .jevDirect && settings.provider != .jevGateway {
                settings.provider = .jevDirect
            }
        } detail: {
            if settings.provider == .jevDirect || settings.provider == .jevGateway {
                VStack(alignment: .leading, spacing: 8) {
                    subCard("TypeSafe direct", "api.typesafe.ai · TYPESAFE_API_KEY",
                            selected: settings.provider == .jevDirect) {
                        settings.provider = .jevDirect
                    }
                    subCard("AI Gateway", "ai-gateway.vercel.sh/typesafe · AI_GATEWAY_API_KEY",
                            selected: settings.provider == .jevGateway) {
                        settings.provider = .jevGateway
                    }
                    SecureField("API key", text: jevKeyBinding)
                        .textFieldStyle(.roundedBorder)
                    testRow
                }
                .padding(.top, 6)
            }
        }
    }

    private func localRow(_ spec: ModelSpec) -> some View {
        let selected = settings.provider == .local && settings.localModelID == spec.id
        return row(
            title: spec.title,
            detail: spec.blurb,
            selected: selected
        ) {
            selectLocal(spec)
        } detail: {
            if selected { localDetail(spec).padding(.top, 6) }
        }
    }

    private var othersRow: some View {
        let others = ModelCatalog.others
        let selected = settings.provider == .local && others.contains { $0.id == settings.localModelID }
        return row(
            title: "Other local models",
            detail: "More open System One models — ranked by benchmark. Same contract, fully on-device.",
            selected: selected,
            accessory: othersExpanded ? "chevron.up" : "chevron.down"
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { othersExpanded.toggle() }
        } detail: {
            if othersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(others) { spec in
                        let sel = selected && settings.localModelID == spec.id
                        subCard("\(spec.title)", spec.blurb, selected: sel, badge: badge(for: spec)) {
                            selectLocal(spec)
                        }
                        if sel { localDetail(spec).padding(.leading, 12) }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var customRow: some View {
        row(
            title: "Custom endpoint",
            detail: "Any server answering POST {base}/v1/systemone — self-hosted or third-party.",
            selected: settings.provider == .custom
        ) {
            settings.provider = .custom
        } detail: {
            if settings.provider == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Endpoint") {
                        TextField("https://host:port", text: customURLBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        TextField("model", text: customModelBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                    SecureField("Bearer key (optional)", text: customKeyBinding)
                        .textFieldStyle(.roundedBorder)
                    testRow
                }
                .padding(.top, 6)
            }
        }
    }

    private var offRow: some View {
        row(
            title: "Off",
            detail: "No model calls. ⌘V and the smart hotkey paste normally — Cue just keeps history.",
            selected: settings.provider == .off
        ) {
            settings.provider = .off
        } detail: { EmptyView() }
    }

    // MARK: - Local model detail

    @ViewBuilder
    private func localDetail(_ spec: ModelSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if spec.variants.count > 1 {
                Picker("Weights", selection: variantBinding(spec)) {
                    ForEach(spec.variants) { v in
                        Text("\(v.paramsLabel) · \(v.diskLabel)").tag(v.id)
                    }
                }
                .pickerStyle(.menu)
            }
            if let v = resolvedVariant(spec) {
                Text("\(v.paramsLabel) params · \(v.diskLabel) disk · \(v.ramLabel) RAM")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            supportNote(spec)
            stateRow(spec)
        }
    }

    @ViewBuilder
    private func supportNote(_ spec: ModelSpec) -> some View {
        switch spec.support {
        case .supported: EmptyView()
        case .experimental(let why):
            Label("Experimental — \(why)", systemImage: "exclamationmark.triangle")
                .font(.system(size: 11)).foregroundStyle(.orange)
        case .unsupported(let why):
            Label("Not installable on this Mac — \(why)", systemImage: "xmark.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stateRow(_ spec: ModelSpec) -> some View {
        switch model.models.status(of: spec.id) {
        case .notInstalled:
            if case .unsupported = spec.support { EmptyView() }
            else {
                Button("Install") { installSelected(spec) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case .installing(let phase):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase).font(.system(size: 11))
                    if let tail = model.models.logTail[spec.id] {
                        Text(tail).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        case .installed:
            let mismatch = model.models.installedVariant(of: spec.id) != settings.localVariantID
            HStack(spacing: 8) {
                if mismatch {
                    Button("Install selected weights") { installSelected(spec) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button("Start") { startSelected(spec) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button("Uninstall") { model.models.uninstall(spec) }
                    .controlSize(.small)
            }
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("starting — first launch downloads weights")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .running:
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("running on :\(spec.defaultPort)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Stop") { model.models.stop() }.controlSize(.small)
                Spacer()
                testRow
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                Text(msg).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                Button("Retry") { installSelected(spec) }.controlSize(.small)
            }
        }
    }

    private var testRow: some View {
        HStack(spacing: 8) {
            Button(testing ? "Testing…" : "Test connection") {
                Task {
                    testing = true
                    defer { testing = false }
                    testResult = await model.testProvider()
                }
            }
            .disabled(testing)
            .controlSize(.small)
            if let testResult {
                Text(testResult).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    // MARK: - Card scaffolding

    private func row<Detail: View>(
        title: String, detail: String, selected: Bool,
        accessory: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder detail detailContent: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let accessory {
                        Image(systemName: accessory)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 6)
            detailContent().padding(.horizontal, 12).padding(.bottom, 6)
        }
    }

    private func subCard(_ title: String, _ detail: String, selected: Bool,
                         badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    if let badge {
                        Text(badge).font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func badge(for spec: ModelSpec) -> String? {
        switch spec.support {
        case .supported: spec.rank == 1 ? "recommended" : nil
        case .experimental: "experimental"
        case .unsupported: "unavailable"
        }
    }

    // MARK: - Actions & bindings

    private func selectLocal(_ spec: ModelSpec) {
        settings.provider = .local
        settings.localModelID = spec.id
        if spec.variants.allSatisfy({ $0.id != settings.localVariantID }),
           let def = ModelCatalog.defaultVariant(of: spec) {
            settings.localVariantID = def.id
        }
    }

    private func resolvedVariant(_ spec: ModelSpec) -> WeightSpec? {
        spec.variants.first { $0.id == settings.localVariantID } ?? ModelCatalog.defaultVariant(of: spec)
    }

    private func variantBinding(_ spec: ModelSpec) -> Binding<String> {
        Binding(get: { resolvedVariant(spec)?.id ?? "" },
                set: { settings.localVariantID = $0 })
    }

    private func installSelected(_ spec: ModelSpec) {
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        Task {
            await model.models.install(r)
            await model.models.start(r)
        }
    }

    private func startSelected(_ spec: ModelSpec) {
        guard let r = ModelCatalog.variant(modelID: spec.id, variantID: settings.localVariantID) else { return }
        Task { await model.models.start(r) }
    }

    private var jevKeyBinding: Binding<String> {
        Binding(
            get: { settings.provider == .jevGateway
                ? settings.gatewayKey ?? "" : settings.apiKey ?? "" },
            set: { if settings.provider == .jevGateway {
                settings.gatewayKey = $0.isEmpty ? nil : $0
            } else {
                settings.apiKey = $0.isEmpty ? nil : $0
            } }
        )
    }
    private var customURLBinding: Binding<String> {
        Binding(get: { settings.customURL }, set: { settings.customURL = $0 })
    }
    private var customModelBinding: Binding<String> {
        Binding(get: { settings.customModel }, set: { settings.customModel = $0 })
    }
    private var customKeyBinding: Binding<String> {
        Binding(get: { settings.customKey ?? "" },
                set: { settings.customKey = $0.isEmpty ? nil : $0 })
    }
}
