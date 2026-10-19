import AppKit
import Foundation

/// The orchestrator. Hotkey in → paste or HUD out. Owns the form-fill loop.
@MainActor @Observable
public final class SmartPasteController {
    public private(set) var busy = false
    /// One-line record of the most recent outcome — the menu bar shows it so
    /// a silent fallback is never mysterious ("plain paste · model unreachable").
    public private(set) var lastAction: String?

    private let store: ClipStore
    private let settings: AppSettings
    private let executor: PasteExecutor
    private let hud: HUDController
    private let redactor: (any Redacting)?
    private let prefetch: DecisionPrefetch
    private let makeProvider: (TimeInterval) -> (any DecisionProvider)?
    private var formFiller: FormFiller?

    public init(store: ClipStore, settings: AppSettings,
                executor: PasteExecutor, hud: HUDController,
                redactor: (any Redacting)?, prefetch: DecisionPrefetch,
                makeProvider: @escaping (TimeInterval) -> (any DecisionProvider)?) {
        self.store = store
        self.settings = settings
        self.executor = executor
        self.hud = hud
        self.redactor = redactor
        self.prefetch = prefetch
        self.makeProvider = makeProvider
        // Assigned last: the closure weak-captures self, legal once every
        // stored property above is initialized.
        self.formFiller = FormFiller(executor: executor) { [weak self] ctx in
            guard let self else { return nil }
            return await self.decisionForFormField(ctx)
        }
    }

    /// Entry point for an intercepted ⌘V (`intercepted`) and for the smart-paste hotkey, which is
    /// always an explicit pick — even when ⌘V is intercepted too.
    public func smartPaste(intercepted: Bool) {
        // Intercept contract: the real keystroke was already eaten — every
        // exit must produce a paste. Hotkey mode ate nothing, so a bail just
        // informs instead.
        func bail(_ action: String, toast: String? = nil) {
            lastAction = action
            if let toast { hud.showStatus(toast) }
            if intercepted { pasteLatest() }
        }

        if busy || hud.isShowingChoices {
            // HUD up → this press belongs to it; treat as "none of these".
            if hud.isShowingChoices { hud.dismiss() }
            bail("plain paste · busy", toast: intercepted ? nil : "Still deciding…")
            return
        }
        guard ContextCaptor.isTrusted else {
            ContextCaptor.requestTrust()
            // Untrusted shouldn't intercept at all (the hotkey isn't
            // registered) — a race can still land here; repost is a no-op
            // if CGEvent is also untrusted, so the toast carries the info.
            bail("plain paste · needs Accessibility",
                 toast: "Accessibility permission needed — check System Settings")
            return
        }
        let ctx = ContextCaptor.capture()

        // Image/file on the pasteboard → the user wants that, not a text pick.
        if PasteboardGate.shouldPassThrough() {
            lastAction = "plain paste · image/file on clipboard"
            pasteLatest()
            return
        }
        // Never think about password fields: plain paste, no API call.
        if ctx.field.isSecure {
            lastAction = "plain paste · secure field"
            pasteLatest()
            return
        }
        // Queue mode: deterministic FIFO, no model call.
        if settings.queueMode, let clip = store.popQueue() {
            lastAction = "queued paste" // never log clip contents
            paste(clip.text, clip: clip)
            return
        }
        guard !store.clips.isEmpty else {
            bail("plain paste · history empty",
                 toast: intercepted ? nil : "Clipboard history is empty")
            return
        }

        busy = true
        let startedAt = ContinuousClock.now
        Task {
            let indicator = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.busy else { return }
                self.hud.showDeciding(near: HUDController.anchor(caret: ctx.caretRect, field: ctx.fieldRect))
            }
            defer {
                indicator.cancel()
                busy = false
            }
            let engine = makeEngine()
            let mode: DecisionEngine.Mode = intercepted ? .intercept : .hotkey
            let outcome = await prefetch.outcome(
                context: ctx,
                candidates: store.clips,
                mode: mode,
                engine: engine
            )
            await handle(outcome, ctx: ctx, since: startedAt, intercepted: intercepted)
        }
    }

    /// Raw-paste hotkey / .pasteLatest fallthrough: send ⌘V for whatever is
    /// on the pasteboard right now — not our store's possibly-stale view.
    /// No toast: this is the user's normal paste.
    public func pasteLatest() {
        executor.pasteCurrent()
    }

    /// History-window/menu action: paste a specific clip into whatever app
    /// had focus. The caller is responsible for restoring focus first.
    public func pasteClip(_ clip: Clip) {
        paste(clip.text, clip: clip)
    }

    /// Manual picker hotkey — always shows the picker, no model call.
    public func showPicker() {
        let candidates = store.candidates().map {
            ScoredCandidate(clip: $0, probability: 0, confidence: 0)
        }
        guard !candidates.isEmpty else { return }
        let ctx = ContextCaptor.capture()
        hud.showPicker(candidates: candidates, near: HUDController.anchor(caret: ctx.caretRect, field: ctx.fieldRect)) { [weak self] pick in
            guard let self else { return }
            guard let pick else { self.pasteLatest(); return }
            self.paste(pick.clip.text, clip: pick.clip)
        }
    }

    private func handle(_ outcome: PasteOutcome, ctx: ContextSnapshot,
                        since startedAt: ContinuousClock.Instant, intercepted: Bool) async {
        let e = startedAt.duration(to: .now).components
        let ms = " · \(Int(e.seconds * 1000 + e.attoseconds / 1_000_000_000_000_000)) ms"
        // lastAction is a status line: action + kind + latency, never content.
        switch outcome {
        case .paste(let d):
            lastAction = "pasted" + (d.detail.map { " · \($0)" } ?? "") + ms
            hud.dismiss() // a shown deciding indicator must not linger
            paste(d.text, clip: d.clip)
            confirm(d, ctx: ctx)
            if d.isForm { await formFiller?.run() }
        case .choose(let opts):
            lastAction = "showed chooser" + ms
            hud.showChooser(options: opts, history: store.clips, near: HUDController.anchor(caret: ctx.caretRect, field: ctx.fieldRect),
                            fieldLabel: ctx.field.label) { [weak self] pick in
                guard let self else { return }
                // Esc/⌘V means "plain paste" — the chooser promises it.
                guard let pick else { self.lastAction = "plain paste · declined options"; self.pasteLatest(); return }
                self.lastAction = "pasted picked option"
                self.paste(pick.option.text, clip: pick.option.clip)
            }
        case .pasteLatest(let reason):
            lastAction = "plain paste · \(reason.label) · \(Self.fieldNote(ctx))" + ms
            hud.dismiss() // a shown deciding indicator must not linger
            // Hotkey mode only — intercept is the user's normal ⌘V and stays silent.
            if case .nothingFits = reason, !intercepted {
                hud.showStatus("Nothing here fits this field")
            }
            pasteLatest()
        }
    }

    /// The form-fill loop's per-field decision. Returns nil to stop.
    private func decisionForFormField(_ ctx: ContextSnapshot) async -> Decision? {
        let engine = makeEngine()
        let outcome = await engine.decide(
            context: ctx,
            candidates: store.clips,
            mode: .formFill
        )
        guard case .paste(let d) = outcome else { return nil }
        store.markPasted(d.clip)
        return d
    }

    /// What Cue could see of the field, for the menu-bar note — never the field's contents.
    static func fieldNote(_ ctx: ContextSnapshot) -> String {
        if ctx.field.role.isEmpty { return "no field visible to Cue" }
        return ctx.field.label.isEmpty ? "unlabelled field" : "field “\(ctx.field.label.prefix(30))”"
    }

    private func paste(_ text: String, clip: Clip) {
        executor.paste(text)
        store.markPasted(clip)
    }

    /// Cue chose on its own: say what kind of thing landed and where it came from, next to the caret.
    /// Never the text itself: the note is visible to anyone watching the screen.
    private func confirm(_ d: Decision, ctx: ContextSnapshot) {
        guard settings.showStatusToast else { return }
        let kind = d.detail.map { $0 == "url" ? "link" : $0 }
        let what = ["Pasted", kind].compactMap { $0 }.joined(separator: " ")
        let note = d.clip.sourceApp.isEmpty ? what : "\(what) from \(d.clip.sourceApp)"
        hud.showStatus(note, near: HUDController.anchor(caret: ctx.caretRect, field: ctx.fieldRect))
    }

    /// Internal: the practice session builds its engine through the same path.
    func makeEngine(timeout: TimeInterval = 2.5) -> DecisionEngine {
        var engine = DecisionEngine(
            provider: makeProvider(timeout),
            redactor: settings.effectivePIIRedaction ? redactor : nil
        )
        engine.timeout = timeout
        return engine
    }
}
