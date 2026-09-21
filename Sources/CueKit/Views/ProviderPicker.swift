import SwiftUI

/// The provider picker shared by onboarding and Settings.
/// Users don't know what kev/laya/von are — the picker leads with what each
/// model is *for*: Jev hosted on top, then local cards pitched by reason
/// (best balance / best accuracy / fastest) with meters, sizes, and inline
/// install/run controls. Everything else is one disclosure away.
public struct ProviderPicker: View {
    var model: AppModel

    @State private var testing = false
    @State private var testResult: String?
    @State private var othersExpanded = false

    public init(model: AppModel) { self.model = model }

    private var settings: AppSettings { model.settings }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            jevCard
            sectionHeader("Local models — on-device, private")
            modelCard(ModelCatalog.von)
            modelCard(ModelCatalog.kev)
            modelCard(ModelCatalog.laya)
            othersRow
            sectionHeader("Advanced")
            customRow
            offRow
        }
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: - Jev (hosted)

    private var jevCard: some View {
        let selected = settings.provider == .jevDirect || settings.provider == .jevGateway
        return card(selected: selected) {
            settings.provider = .jevDirect
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Jev").font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            pill("Hosted · best quality")
                            if selected { pill("Active", accent: true) }
                        }
                    }
                    Spacer()
                    meters(accuracy: 0.95, speed: 0.65)
                }
                Text("TypeSafe's hosted decision model — strongest picks, ~100ms, needs an API key. Via TypeSafe direct or Vercel AI Gateway.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if selected {
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            subCard("TypeSafe direct", "api.typesafe.ai",
                                    selected: settings.provider == .jevDirect) {
                                settings.provider = .jevDirect
                            }
                            subCard("AI Gateway", "ai-gateway.vercel.sh",
                                    selected: settings.provider == .jevGateway) {
                                settings.provider = .jevGateway
                            }
                        }
                        SecureField("API key", text: jevKeyBinding)
                            .textFieldStyle(.roundedBorder)
                        testRow
                    }
                }
            }
        }
    }

    // MARK: - Local model cards

    private func modelCard(_ spec: ModelSpec) -> some View {
        let selected = settings.provider == .local && settings.localModelID == spec.id
        let v = resolvedVariant(spec)
        let state = model.models.status(of: spec.id)
        let unsupported = spec.support.isUnsupported
        return card(selected: selected, dimmed: unsupported) {
            selectLocal(spec)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(spec.title).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            pill(spec.reason)
                            if spec.rank == 1 { pill("Recommended") }
                            if state == .running { pill("Active", accent: true) }
                            if case .experimental = spec.support { pill("Experimental") }
                        }
                    }
                    Spacer()
                    if let v { meters(accuracy: v.accuracy, speed: v.speed) }
                }
                Text(spec.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.5)
                metaRow(spec, variant: v)
                if selected {
                    if spec.variants.count > 1 {
                        Picker("Weights", selection: variantBinding(spec)) {
                            ForEach(spec.variants) { w in
                                Text("\(w.paramsLabel) · \(w.diskLabel)").tag(w.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                    supportNote(spec)
                    stateRow(spec)
                }
            }
        }
    }

    /// params · disk · RAM · port — the reference card's meta strip.
    private func metaRow(_ spec: ModelSpec, variant v: WeightSpec?) -> some View {
        HStack(spacing: 14) {
            if let v {
                metaItem("cpuchip", "\(v.paramsLabel) params")
                metaItem("internaldrive", v.diskLabel)
                metaItem("memorychip", "\(v.ramLabel) RAM")
            }
            metaItem("network", ":\(spec.defaultPort)")
            Spacer()
        }
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
    }

    /// Two thin bars like the reference: accuracy and speed for the variant.
    private func meters(accuracy: Double, speed: Double) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            meter("accuracy", accuracy)
            meter("speed", speed)
        }
    }

    private func meter(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor)
                    .frame(width: 52 * max(0.05, min(1, value)))
            }
            .frame(width: 52, height: 4)
        }
    }

    private func pill(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accent ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                        in: Capsule())
            .foregroundStyle(accent ? Color.accentColor : .secondary)
    }

    // MARK: - State actions (install/start/stop/health)

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
                Text("running")
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

    // MARK: - More local models / advanced

    private var othersRow: some View {
        let others = ModelCatalog.others
        let selected = settings.provider == .local && others.contains { $0.id == settings.localModelID }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { othersExpanded.toggle() }
            } label: {
                HStack {
                    Text("More local models")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: othersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if othersExpanded {
                VStack(spacing: 8) {
                    ForEach(others) { spec in modelCard(spec) }
                }
            }
        }
    }

    private var customRow: some View {
        card(selected: settings.provider == .custom) {
            settings.provider = .custom
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom endpoint").font(.system(size: 14, weight: .semibold))
                Text("Any server answering POST {base}/v1/systemone — self-hosted or third-party.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.provider == .custom {
                    Divider().opacity(0.5)
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
                }
            }
        }
    }

    private var offRow: some View {
        card(selected: settings.provider == .off) {
            settings.provider = .off
        } content: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Off").font(.system(size: 14, weight: .semibold))
                    Text("No model calls — smart pastes pass through as normal ⌘Vs. History, queue, and picker still work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Card scaffolding

    /// The card chrome shared by every row: plain-button hit area, quaternary
    /// fill, accent ring when selected.
    private func card<Content: View>(
        selected: Bool, dimmed: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.12),
                    lineWidth: selected ? 1.5 : 0.5))
        .opacity(dimmed ? 0.55 : 1)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: action)
    }

    private func subCard(_ title: String, _ detail: String, selected: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .medium))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(detail).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

private extension ModelSpec.Support {
    var isUnsupported: Bool { if case .unsupported = self { return true }; return false }
}
