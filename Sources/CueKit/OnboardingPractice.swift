import AppKit
import Foundation
import SwiftUI

/// The fixed sample used across onboarding — one message with an email, a
/// phone and a URL so the extract transforms have something to find.
/// Lives at the demo/practice boundary; screens reference this instead of
/// duplicating literals.
public enum OnboardingSample {
    public static let message =
        "Hey, here are the details for the launch. Reach Mira at mira@example.com " +
        "or +44 7700 900123. The brief is at https://example.com/launch. " +
        "Let’s review everything on Friday."

    public static let practiceMessage =
        "Reach Mira at mira@example.com or +44 7700 900123. " +
        "The project brief is at https://example.com/launch."

    /// Second round ("Try another"): three plausible recipients, so the
    /// engine — not the transform — decides. Priya leads so the
    /// deterministic extractor picks hers.
    public static let anotherMessage =
        "Loop in Priya at priya@example.com for the launch, cc Mira " +
        "at mira@example.com, and send the invoice to billing@example.com."

    public enum Target: String, CaseIterable, Sendable {
        case email = "Email"
        case website = "Website"

        /// What the deterministic transform should produce for this field —
        /// the practice pass/fail bar, computed from the real extractor.
        public var expected: String {
            expected(in: message)
        }

        public func expected(in text: String) -> String {
            switch self {
            case .email: Transform.extractEmail.apply(text)
            case .website: Transform.extractURL.apply(text)
            }
        }
    }
}

/// The guided first-paste. Real engine, real provider, real ⌘V — but scoped:
/// one sample clip, one labeled field, consumed only while that field is
/// focused. Success is *observed* (field text == expected extraction), never
/// assigned.
@MainActor @Observable
public final class OnboardingPractice {
    public enum Phase: Equatable {
        case intro
        case armed                        // copied; waiting for the trigger
        case deciding                     // engine call in flight
        case succeeded(observed: String)  // field == expected extraction
        case ordinaryPaste(observed: String) // a paste happened but not the extraction
        case uncertain                    // model wanted confirmation (top3/picker)
        case failed(String)               // error / no paste arrived
        case lostPermission               // AX trust gone
        case unavailable                  // no provider configured (off/no key)
    }

    /// Where a landed value came from — only engine-originated text counts
    /// as a smart paste.
    public enum PickOrigin: Sendable {
        case none          // plain ⌘V / fallback / typed
        case enginePick    // the engine returned .paste
        case chooserPick   // the engine returned .choose and a row was picked
    }

    public private(set) var phase: Phase = .intro
    public private(set) var elapsedMilliseconds: Int?
    public var target = OnboardingSample.Target.email
    /// 0 = the first guided paste; 1 = the "Try another" round.
    public private(set) var round = 0
    /// The observed practice-field text — kept in sync by the field bridge.
    public var fieldText = ""

    /// Round 2's field is a reply box, not a bare "Email" label.
    public var fieldLabel: String { round == 0 ? target.rawValue : "Reply to Priya" }
    /// The message this round copies to the pasteboard.
    public var sampleText: String {
        round == 0 ? OnboardingSample.practiceMessage : OnboardingSample.anotherMessage
    }

    /// The practice field — set by the view bridge; used for focus + reads.
    public weak var field: NSTextField?

    /// Where the last landed value came from (vs plain paste).
    private var lastOrigin: PickOrigin = .none
    /// Bumps on every attempt — stale async results check it before landing.
    private var epoch = 0
    private var decisionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var startedAt: ContinuousClock.Instant?
    private var lastCtx: ContextSnapshot?

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
        if model.makeProvider() == nil { phase = .unavailable }
    }

    public var expected: String { target.expected(in: sampleText) }

    /// The trigger hint shown in "Now press …" — the user's real binding.
    public var triggerHint: String {
        if model.settings.triggerMode == .intercept { return "⌘V" }
        return (model.settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
            ?? HotkeyManager.Action.smartPaste.default).displayString
    }

    /// "Copy sample" — a real pasteboard write (labeled as such in the UI), marked transient so
    /// the sample never lands in the user's history; the decision below only sees this one clip.
    public func copySample() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sampleText, forType: .string)
        NSPasteboard.general.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        focus()
        phase = model.makeProvider() == nil ? .unavailable : .armed
    }

    public func reset(target newTarget: OnboardingSample.Target? = nil) {
        cancel()
        elapsedMilliseconds = nil
        lastOrigin = .none
        if let newTarget { target = newTarget }
        field?.stringValue = ""
        fieldText = ""
        if model.makeProvider() == nil {
            phase = .unavailable
        } else {
            copySample()
        }
    }

    /// "Try another": a second guided round against the three-email sample.
    /// Success is still observed — same engine, same field check.
    public func tryAnother() {
        round += 1
        target = .email
        reset(target: .email)
    }

    /// SmartPasteController's dispatch seam: returns true if the practice
    /// consumed this trigger. Consumes only when armed and the practice field
    /// is being edited — a live field editor is a stronger signal than AX
    /// frontmost/label for our own LSUIElement window, and cheaper.
    public func handleTrigger() -> Bool {
        switch phase {
        case .deciding: return true // swallow repeats while a call is in flight
        case .armed: break
        default: return false
        }
        guard field?.currentEditor() != nil else { return false }
        guard ContextCaptor.isTrusted else {
            phase = .lostPermission
            return true
        }
        var ctx = ContextCaptor.capture()
        // The practice knows its target field — don't rely on the field's
        // AXTitle propagating through the text editor the captor reads.
        if ctx.field.label.isEmpty { ctx.field.label = fieldLabel }
        if ctx.field.placeholder.isEmpty {
            ctx.field.placeholder = target == .email ? "name@example.com" : "https://…"
        }

        phase = .deciding
        startedAt = .now
        lastCtx = ctx
        lastOrigin = .none
        epoch += 1
        let myEpoch = epoch
        let candidates = [sampleClip()]
        let engine = model.controller.makeEngine(timeout: 1.8)
        let mode: DecisionEngine.Mode =
            model.settings.triggerMode == .intercept ? .intercept : .hotkey

        decisionTask = Task { [weak self] in
            let outcome = await engine.decide(context: ctx, candidates: candidates, mode: mode)
            guard !Task.isCancelled else { return }
            self?.resolve(outcome, epoch: myEpoch)
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.epoch == myEpoch, self.phase == .deciding else { return }
            self.decisionTask?.cancel()
            self.resolve(.pasteLatest(.unreachable), epoch: myEpoch)
        }
        return true
    }

    private func resolve(_ outcome: PasteOutcome, epoch myEpoch: Int) {
        guard epoch == myEpoch, phase == .deciding else { return }
        timeoutTask?.cancel()
        guard field?.currentEditor() != nil else {
            phase = .failed("Click the field and try your shortcut again.")
            return
        }
        switch outcome {
        case .paste(let d):
            // A real pick — possibly with an extraction transform.
            lastOrigin = .enginePick
            deliver(d.text)
            scheduleObservation(epoch: myEpoch)
        case .pasteLatest:
            // Engine fell back — the paste delivers the whole sample. That's
            // an honest "ordinary paste" result, not a failure.
            lastOrigin = .none
            deliver(nil)
            scheduleObservation(epoch: myEpoch)
        case .choose(let opts):
            // The model asked for confirmation — show the real chooser at
            // the practice field; a pick pastes like production, Esc/⌘V is
            // an ordinary paste. Observed via the same field path.
            model.hud.showChooser(options: opts, near: lastCtx?.caretRect ?? lastCtx?.fieldRect) { [weak self] pick in
                guard let self, self.epoch == myEpoch else { return }
                self.lastOrigin = pick != nil ? .chooserPick : .none
                self.deliver(pick?.option.text)
                self.scheduleObservation(epoch: myEpoch)
            }
        }
    }

    /// Deliver the result into the practice field through its field editor —
    /// the same seam SelfCheck uses. The executor still does its real work
    /// (pasteboard write, intercept suspend/resume); only the keystroke leg
    /// is redirected, because a synthetic ⌘V only ever reaches the
    /// system-frontmost app — which is not reliably our own window.
    private func deliver(_ text: String?) {
        guard let editor = field?.currentEditor() else { return }
        model.executor.onWouldPost = { s in editor.insertText(s) }
        if let text { model.executor.paste(text) } else { model.executor.pasteCurrent() }
        model.executor.onWouldPost = nil
    }

    /// The synthetic ⌘V lands on the next runloop turns; check what the
    /// field actually contains shortly after executing.
    private func scheduleObservation(epoch myEpoch: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                guard let self, self.epoch == myEpoch, self.phase == .deciding else { return }
                self.classifyField()
            }
        }
    }

    /// Also driven live by the field's textDidChange — kept separate so a
    /// paste that never arrives still resolves via the timeout above.
    public func observeFieldText(_ text: String) {
        fieldText = text
        if phase == .deciding, !text.isEmpty { classifyField(); return }
        // An unintercepted ⌘V (no Accessibility, or plain ⌘V in hotkey mode)
        // lands the clipboard verbatim while we're armed — classify it as an
        // honest ordinary paste instead of leaving "Now press ⌘V" forever.
        // Gated on the landed text actually being the pasteboard's content,
        // so ordinary typing doesn't trip it.
        guard phase == .armed, !text.isEmpty else { return }
        let pb = NSPasteboard.general.string(forType: .string) ?? ""
        if Self.landedViaPaste(fieldText: text, pasteboard: pb, expected: expected) {
            classifyField()
        }
    }

    /// The armed-phase paste test, pure so tests pin it: the field's new
    /// content counts as a paste when it equals the live pasteboard (or the
    /// expected extraction); anything else is typing, not a paste.
    nonisolated static func landedViaPaste(fieldText: String, pasteboard: String,
                                           expected: String) -> Bool {
        fieldText == pasteboard || fieldText == expected
    }

    private func classifyField() {
        let observed = field?.stringValue ?? fieldText
        if let startedAt {
            let elapsed = startedAt.duration(to: .now).components
            elapsedMilliseconds = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        }
        phase = Self.classify(observed: observed, expected: expected,
                              origin: lastOrigin,
                              trusted: ContextCaptor.isTrusted)
    }

    /// The pass/fail rule, pure so tests can pin it: success requires the
    /// observed text to equal the extraction AND the value to have come from
    /// the engine — a direct pick or a chooser pick. A verbatim landing of
    /// the sample is an ordinary paste.
    nonisolated static func classify(observed: String, expected: String,
                         origin: PickOrigin, trusted: Bool) -> Phase {
        if observed == expected {
            return origin == .none ? .ordinaryPaste(observed: observed)
                                   : .succeeded(observed: observed)
        }
        if observed.isEmpty {
            return trusted
                ? .failed("Nothing was pasted — the keystroke didn't reach the field")
                : .lostPermission
        }
        return .ordinaryPaste(observed: observed)
    }

    private func sampleClip() -> Clip {
        Clip(text: sampleText, kind: .text, sourceApp: "Cue")
    }

    public func focus() {
        guard let field, let window = field.window else { return }
        window.makeFirstResponder(field)
    }

    public func cancel() {
        epoch += 1
        decisionTask?.cancel()
        timeoutTask?.cancel()
    }
}

// MARK: - Field bridge

/// The practice destination: a real NSTextField with the target's AX label,
/// so the production capture path sees a genuine "Email"/"Website" field.
@MainActor
struct PracticeField: NSViewRepresentable {
    var label: String
    var placeholder: String
    var practice: OnboardingPractice

    func makeCoordinator() -> Coordinator { Coordinator(practice: practice) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.setAccessibilityTitle(label)
        f.font = .systemFont(ofSize: 15)
        f.delegate = context.coordinator
        f.bezelStyle = .roundedBezel
        f.focusRingType = .default
        f.appearance = NSAppearance(named: .aqua) // sits on a white card in both modes
        practice.field = f
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        f.setAccessibilityTitle(label)
        if f.placeholderString != placeholder { f.placeholderString = placeholder }
        context.coordinator.practice = practice
        if f.stringValue != practice.fieldText { f.stringValue = practice.fieldText }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var practice: OnboardingPractice
        init(practice: OnboardingPractice) { self.practice = practice }
        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            practice.observeFieldText(f.stringValue)
        }
    }
}
