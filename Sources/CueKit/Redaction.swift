import Foundation
import Redact

/// The seam between the decision engine and PII scrubbing — Redact SDK in
/// production, a stub in tests.
public protocol Redacting: Sendable {
    /// Returns text with PII replaced by placeholders (`[EMAIL_1]`, …).
    /// Throws when the model isn't usable — callers must not ship the raw
    /// text to a remote endpoint after a failure.
    func redact(_ text: String) async throws -> String
}

/// On-device PII redaction via the desert-ant `redact` model — a 23-language
/// token classifier, ~11.6 MB of Core ML that downloads on first use and runs
/// on the Neural Engine. No clip text leaves the machine for this step.
@MainActor @Observable
public final class PIIRedactor: Redacting {
    public private(set) var status: Status = .idle
    public enum Status: Sendable, Equatable {
        case idle
        case downloading(Double)
        case ready
        case failed(String)
    }

    private let engine = Redact()

    public init() {
        if engine.isDownloaded() { status = .ready }
    }

    /// Downloads the model ahead of time (onboarding calls this so the first
    /// redacted paste doesn't pay the download latency). Safe to re-call.
    public func prepare() async {
        guard status != .ready else { return }
        do {
            try await engine.download { [weak self] fraction in
                Task { @MainActor in self?.status = .downloading(fraction) }
            }
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Model isn't on disk and a download isn't in flight yet.
    public var needsDownload: Bool {
        if case .ready = status { return false }
        if case .downloading = status { return false }
        return !engine.isDownloaded()
    }

    public func redact(_ text: String) async throws -> String {
        guard !text.isEmpty else { return text }
        // First call lazily downloads+loads the model; a failure propagates —
        // the engine degrades to a plain paste rather than send unredacted
        // text anywhere.
        let r = try await engine.redaction(of: text)
        status = .ready
        return r.redactedText
    }
}
