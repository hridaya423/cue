import AppKit
import Foundation
import Testing
@testable import CueKit

struct ModelCatalogTests {
    @Test func idsAndPortsAreUnique() {
        let ids = ModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let ports = ModelCatalog.all.map(\.defaultPort)
        #expect(Set(ports).count == ports.count)
    }

    @Test func everySpecHasVariantsAndResolves() {
        for spec in ModelCatalog.all {
            #expect(!spec.variants.isEmpty, "\(spec.id) has no variants")
            // No variantID → falls back to first variant.
            let r = ModelCatalog.variant(modelID: spec.id, variantID: "")
            #expect(r?.variant.id == spec.variants.first?.id)
            // Explicit variant resolves to itself.
            for v in spec.variants {
                #expect(ModelCatalog.variant(modelID: spec.id, variantID: v.id)?.variant.id == v.id)
            }
        }
    }

    @Test func unknownModelResolvesToNil() {
        #expect(ModelCatalog.variant(modelID: "nope", variantID: "") == nil)
        #expect(ModelCatalog.model("nope") == nil)
    }

    @Test func variantsRankBestFirst() {
        // The list the "Others" section renders is benchmark-ranked, not
        // alphabetical — positions must be explicit and dense.
        let ranks = ModelCatalog.all.map(\.rank).sorted()
        #expect(ranks == Array(1...ModelCatalog.all.count))
    }

    @Test func endpointIsLoopback() {
        for spec in ModelCatalog.all {
            let r = ModelCatalog.variant(modelID: spec.id, variantID: "")!
            #expect(!JevEndpoint(url: r.endpointURL, model: r.serveModel).isRemote, "\(spec.id) should be loopback")
            #expect(r.endpointURL.path.hasSuffix("/v1/systemone"))
        }
    }

    @Test func recommendedVariants() {
        for spec in ModelCatalog.all {
            let count = spec.variants.filter(\.recommended).count
            // Installable models (supported or experimental) need exactly one
            // recommended default for the variant picker; unsupported ones
            // are greyed out and never install.
            let installable = if case .unsupported = spec.support { false } else { true }
            #expect(count == (installable ? 1 : 0),
                    "\(spec.id) has \(count) recommended variants")
        }
    }

    @Test func everySpecHasUserFacingReason() {
        // Cards pitch models by what they're FOR — a blank reason renders
        // as an empty pill, so the catalog must always provide one.
        for spec in ModelCatalog.all {
            #expect(!spec.reason.isEmpty, "\(spec.id) missing reason")
        }
    }

    @Test func variantScoresAreSane() {
        for spec in ModelCatalog.all {
            for v in spec.variants {
                #expect((0...1).contains(v.accuracy), "\(v.id) accuracy \(v.accuracy) out of 0…1")
                #expect((0...1).contains(v.speed), "\(v.id) speed \(v.speed) out of 0…1")
            }
        }
    }

    @Test func vonIsTheTopRecommendation() {
        // Rank 1 leads the local recommendations — the "best balance" pick.
        let top = ModelCatalog.all.min(by: { $0.rank < $1.rank })
        #expect(top?.id == "von")
        #expect(ModelCatalog.von.reason == "Best balance")
        #expect(ModelCatalog.kev.reason == "Best local accuracy")
        #expect(ModelCatalog.laya.reason == "Fastest")
    }
}

struct ModelTransferProgressTests {
    @Test func parsesTqdmPercentages() {
        #expect(ModelTransferProgress.parse("model.safetensors: 47%|████▋| 47/100")?.fraction == 0.47)
        #expect(ModelTransferProgress.parse("model.safetensors: 100%|██████████| 100/100")?.fraction == 1)
    }

    @Test func ignoresLinesWithoutPercentages() {
        #expect(ModelTransferProgress.parse("Downloading model files") == nil)
        #expect(ModelTransferProgress.parse("1000%|██████████") == nil)
    }
}

struct PasteboardGateTests {
    private func t(_ name: String) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(name)
    }

    @Test func imageAndFileTypesPassThrough() {
        #expect(PasteboardGate.shouldPassThrough([t("public.png")]))
        #expect(PasteboardGate.shouldPassThrough([t("public.tiff")]))
        #expect(PasteboardGate.shouldPassThrough([t("public.jpeg")]))
        #expect(PasteboardGate.shouldPassThrough([t("public.file-url")]))
        #expect(PasteboardGate.shouldPassThrough([t("public.image"), t("public.utf8-plain-text")]))
    }

    @Test func textTypesDoNotPassThrough() {
        #expect(!PasteboardGate.shouldPassThrough([t("public.utf8-plain-text")]))
        #expect(!PasteboardGate.shouldPassThrough([t("public.url")]))
        #expect(!PasteboardGate.shouldPassThrough([]))
        #expect(!PasteboardGate.shouldPassThrough(nil))
    }
}

@MainActor
struct ProviderStatusTests {
    @Test func recordsSuccessAndFailure() async throws {
        let status = ProviderStatus()
        #expect(status.state == .unknown)

        let ok = StatusTrackingProvider(
            StubProvider(response: JevResponse(model: "m", answers: [:], inputTokens: 0)),
            status: status)
        _ = try await ok.evaluate(state: .string("s"), questions: [:])
        try await Task.sleep(for: .milliseconds(50))
        #expect(status.state == .ok)

        var fail = StubProvider(response: JevResponse(model: "m", answers: [:], inputTokens: 0))
        fail.error = JevError.http(500, "x")
        let tracked = StatusTrackingProvider(fail, status: status)
        _ = try? await tracked.evaluate(state: .string("s"), questions: [:])
        try await Task.sleep(for: .milliseconds(50))
        #expect(status.state == .unreachable)
    }
}

@MainActor
struct SettingsMigrationTests {
    private func freshDefaults() -> UserDefaults {
        let name = "cue-test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func v2KevProviderBecomesLocalWithModelID() {
        let defaults = freshDefaults()
        // Provider strings persist JSON-encoded via `set` — write it that way.
        defaults.set(try! JSONEncoder().encode("kev"), forKey: "provider")
        let s = AppSettings(defaults: defaults)
        #expect(s.provider == .local)
        #expect(s.localModelID == "kev")
    }

    @Test func triStatePIIDefaultsToProviderRemote() {
        let defaults = freshDefaults()
        let s = AppSettings(defaults: defaults)

        s.provider = .jevDirect
        #expect(s.piiRedaction == nil)
        #expect(s.effectivePIIRedaction) // remote → auto-on

        s.provider = .local
        #expect(!s.effectivePIIRedaction) // local → auto-off

        s.piiRedaction = true // explicit override wins over local auto-off
        #expect(s.effectivePIIRedaction)

        s.provider = .custom // custom may be remote → auto-on
        s.piiRedaction = nil
        #expect(s.effectivePIIRedaction)
    }
}
