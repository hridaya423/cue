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
        "Invoice #CU-1847 is approved for £2,480. Priya can help at priya@example.com. " +
        "The billing portal is https://example.com/invoices/CU-1847. " +
        "Please submit it before 4:30 PM Thursday."

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

    public private(set) var phase: Phase = .intro
    public private(set) var elapsedMilliseconds: Int?
    public var target = OnboardingSample.Target.email
    /// The observed practice-field text — kept in sync by the field bridge.
    public var fieldText = ""

    /// The practice field — set by the view bridge; used for focus + reads.
    public weak var field: NSTextField?

    /// Whether the last engine outcome was a real pick (vs plain paste).
    private var lastWasExtraction = false
    /// Bumps on every attempt — stale async results check it before landing.
    private var epoch = 0
    private var decisionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var startedAt: ContinuousClock.Instant?

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
        if model.makeProvider() == nil { phase = .unavailable }
    }

    public var expected: String { target.expected(in: OnboardingSample.practiceMessage) }

    /// The trigger hint shown in "Now press …" — the user's real binding.
    public var triggerHint: String {
        if model.settings.triggerMode == .intercept { return "⌘V" }
        return (model.settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
            ?? HotkeyManager.Action.smartPaste.default).displayString
    }

    /// "Copy sample" — a real pasteboard write (labeled as such in the UI).
    /// The clipboard monitor may legitimately record it; the decision below
    /// still only sees this one sample clip.
    public func copySample() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(OnboardingSample.practiceMessage, forType: .string)
        focus()
        phase = model.makeProvider() == nil ? .unavailable : .armed
    }

    public func reset(target newTarget: OnboardingSample.Target? = nil) {
        cancel()
        elapsedMilliseconds = nil
        lastWasExtraction = false
        if let newTarget { target = newTarget }
        field?.stringValue = ""
        fieldText = ""
        if model.makeProvider() == nil {
            phase = .unavailable
        } else {
            copySample()
        }
    }

    /// SmartPasteController's dispatch seam: returns true if the practice
    /// consumed this trigger. Consumes only when armed and the practice field
    /// is the focused element — anything else falls through to normal smart
    /// paste untouched.
    public func handleTrigger() -> Bool {
        switch phase {
        case .deciding: return true // swallow repeats while a call is in flight
        case .armed: break
        default: return false
        }
        guard ContextCaptor.isTrusted else {
            phase = .lostPermission
            return true
        }
        let ctx = ContextCaptor.capture()
        // The practice field must be the focused element — frontmost app is
        // Cue and the field carries the target's AX label.
        guard ctx.bundleID == Bundle.main.bundleIdentifier || ctx.appName == "Cue",
              ctx.field.label == target.rawValue
        else { return false }

        phase = .deciding
        startedAt = .now
        lastWasExtraction = false
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
        guard field?.currentEditor() != nil, field?.window?.isKeyWindow == true else {
            phase = .failed("Click the field and try your shortcut again.")
            return
        }
        switch outcome {
        case .paste(let d):
            // A real pick — possibly with an extraction transform. Deliver it
            // like production does: pasteboard write + synthetic ⌘V into the
            // focused field, then observe what actually arrived.
            lastWasExtraction = true
            model.executor.paste(d.text)
            scheduleObservation(epoch: myEpoch)
        case .pasteLatest:
            // Engine fell back — the paste delivers the whole sample. That's
            // an honest "ordinary paste" result, not a failure.
            lastWasExtraction = false
            model.executor.pasteCurrent()
            scheduleObservation(epoch: myEpoch)
        case .choose:
            // The model asked for confirmation — a truthful non-success.
            phase = .uncertain
        }
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
        if phase == .deciding && !text.isEmpty { classifyField() }
    }

    private func classifyField() {
        let observed = field?.stringValue ?? fieldText
        if let startedAt {
            let elapsed = startedAt.duration(to: .now).components
            elapsedMilliseconds = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        }
        phase = Self.classify(observed: observed, expected: expected,
                              wasExtraction: lastWasExtraction,
                              trusted: ContextCaptor.isTrusted)
    }

    /// The pass/fail rule, pure so tests can pin it: success requires the
    /// observed text to equal the extraction AND the engine to have made a
    /// pick — a verbatim landing of the sample is an ordinary paste.
    nonisolated static func classify(observed: String, expected: String,
                         wasExtraction: Bool, trusted: Bool) -> Phase {
        if observed == expected {
            return wasExtraction ? .succeeded(observed: observed)
                                 : .ordinaryPaste(observed: observed)
        }
        if observed.isEmpty {
            return trusted
                ? .failed("Nothing was pasted — the keystroke didn't reach the field")
                : .lostPermission
        }
        return .ordinaryPaste(observed: observed)
    }

    private func sampleClip() -> Clip {
        Clip(text: OnboardingSample.practiceMessage, kind: .text, sourceApp: "Cue")
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
