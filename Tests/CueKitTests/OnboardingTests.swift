import Foundation
import Testing
@testable import CueKit

struct OnboardingSampleTests {
    @Test func expectedIsARealExtraction() {
        // The practice pass/fail bar must be what the deterministic
        // transforms actually produce — never a hand-written literal.
        #expect(OnboardingSample.Target.email.expected
                == Transform.extractEmail.apply(OnboardingSample.message))
        #expect(OnboardingSample.Target.website.expected
                == Transform.extractURL.apply(OnboardingSample.message))
    }

    @Test func expectedIsASubstringOfTheSample() {
        // Extraction can only return spans that exist in the message.
        for target in OnboardingSample.Target.allCases {
            #expect(OnboardingSample.message.contains(target.expected))
        }
    }

    @Test func sampleCarriesTheDetailsWeDemo() {
        // One paragraph, several usable details — the welcome demo and the
        // practice both rely on all of these existing.
        #expect(!SpanExtractor.emails(in: OnboardingSample.message).isEmpty)
        #expect(!SpanExtractor.urls(in: OnboardingSample.message).isEmpty)
        #expect(!SpanExtractor.phones(in: OnboardingSample.message).isEmpty)
    }

    @Test func extractionDropsTheRestOfTheMessage() {
        // What made the original paste feel magical: the field gets just
        // the fitting detail, not the paragraph.
        #expect(OnboardingSample.Target.email.expected == "mira@example.com")
        #expect(OnboardingSample.Target.website.expected == "https://example.com/launch")
    }

    @Test func practiceSampleHighlightsItsDetails() {
        // The practice reuses the welcome narrative — same Mira message, so
        // the extraction the user just saw demoed is the one they perform.
        let text = OnboardingSample.practiceMessage
        #expect(OnboardingSample.Target.email.expected(in: text) == "mira@example.com")
        #expect(OnboardingSample.Target.website.expected(in: text)
                == "https://example.com/launch")
        #expect(text.contains(OnboardingSample.Target.email.expected(in: text)))
        #expect(text.contains(OnboardingSample.Target.website.expected(in: text)))
    }
}

struct PracticeClassifyTests {
    let expected = OnboardingSample.Target.email.expected

    @Test func enginePickPlusObservedIsSuccess() {
        let p = OnboardingPractice.classify(
            observed: expected, expected: expected,
            origin: .enginePick, trusted: true)
        #expect(p == .succeeded(observed: expected))
    }

    @Test func chooserPickPlusObservedIsSuccess() {
        // A chooser pick is engine-originated too — the model narrowed it to
        // the top options and the user confirmed one.
        let p = OnboardingPractice.classify(
            observed: expected, expected: expected,
            origin: .chooserPick, trusted: true)
        #expect(p == .succeeded(observed: expected))
    }

    @Test func observedAloneIsNotSuccess() {
        // The field showing the right text without an engine pick (e.g. a
        // typed-in value) is an ordinary paste, not a smart one.
        let p = OnboardingPractice.classify(
            observed: expected, expected: expected,
            origin: .none, trusted: true)
        #expect(p == .ordinaryPaste(observed: expected))
    }

    @Test func wholeParagraphPasteIsNotSuccess() {
        let p = OnboardingPractice.classify(
            observed: OnboardingSample.message, expected: expected,
            origin: .none, trusted: true)
        #expect(p == .ordinaryPaste(observed: OnboardingSample.message))
    }

    @Test func unrelatedTextIsNotSuccess() {
        let p = OnboardingPractice.classify(
            observed: "hello", expected: expected,
            origin: .enginePick, trusted: true)
        #expect(p == .ordinaryPaste(observed: "hello"))
    }

    @Test func emptyFieldIsFailureOrPermissionLoss() {
        let trusted = OnboardingPractice.classify(
            observed: "", expected: expected, origin: .enginePick, trusted: true)
        guard case .failed = trusted else {
            Issue.record("empty field while trusted should be a failed paste")
            return
        }
        let untrusted = OnboardingPractice.classify(
            observed: "", expected: expected, origin: .enginePick, trusted: false)
        #expect(untrusted == .lostPermission)
    }
}

struct PracticeAnotherRoundTests {
    @Test func secondSampleCarriesThreeEmails() {
        // "Try another" gives the engine three plausible recipients.
        #expect(SpanExtractor.emails(in: OnboardingSample.anotherMessage).count == 3)
        for addr in ["priya@example.com", "mira@example.com", "billing@example.com"] {
            #expect(OnboardingSample.anotherMessage.contains(addr))
        }
    }

    @Test func secondRoundExpectedIsPriyaViaRealExtractor() {
        // "Reply to Priya" → Priya's address, derived, never hard-coded.
        // extractEmail returns the first detected span, so Priya must lead.
        #expect(OnboardingSample.Target.email.expected(in: OnboardingSample.anotherMessage)
                == "priya@example.com")
    }

    @Test func secondRoundChooserPickSucceeds() {
        let expected = OnboardingSample.Target.email.expected(in: OnboardingSample.anotherMessage)
        let p = OnboardingPractice.classify(
            observed: expected, expected: expected,
            origin: .chooserPick, trusted: true)
        #expect(p == .succeeded(observed: expected))
    }
}
