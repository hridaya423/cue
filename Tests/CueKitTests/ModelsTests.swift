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

    @Test func catalogRanksComeFromTheFrozenBenchmark() {
        // The shipped benchmarks.json drives rank + reason; rank 1 is the
        // first role (Recommended), and every role model beats every
        // non-role model.
        let roles = ModelRoles.roles(from: ModelRoles.benchmarks)
        #expect(!roles.isEmpty)
        let top = ModelCatalog.all.min(by: { $0.rank < $1.rank })
        #expect(top?.id == roles.first?.bench.model)
        #expect(top?.reason == roles.first?.role.rawValue)
        let roleIDs = Set(roles.map(\.bench.model))
        let worstRole = ModelCatalog.all.filter { roleIDs.contains($0.id) }.map(\.rank).max() ?? 0
        #expect(ModelCatalog.all.filter { !roleIDs.contains($0.id) }.allSatisfy { $0.rank > worstRole })
    }
}

struct ModelRolesTests {
    func b(_ m: String, _ r: Double, _ w: Double, _ p95: Double, disk: Double = 1) -> ModelBenchmark {
        ModelBenchmark(model: m, variant: m, resolved: r, wrong: w, p50: 0, p95: p95,
                       diskGB: disk, ramGB: disk)
    }

    @Test func wrongPastesWeighDouble() {
        // 88% right with 10% wrong loses accuracy to 84% with 1% wrong.
        let r = ModelRoles.roles(from: [b("bold", 0.88, 0.10, 200), b("careful", 0.84, 0.01, 250)])
        #expect(r.first?.role == .mostAccurate)
        #expect(r.first?.bench.model == "careful")
        #expect(r.contains { $0.role == .smallest && $0.bench.model == "bold" })
    }

    @Test func aDoubleWinnerFillsOnlyOneRole() {
        // "a" is best at everything; it takes Most accurate and the next
        // best fill the later roles.
        let r = ModelRoles.roles(from: [b("a", 0.95, 0, 100, disk: 0.4), b("b", 0.85, 0.02, 200),
                                        b("c", 0.82, 0.02, 300, disk: 0.5)])
        #expect(r.map(\.role) == [.mostAccurate, .smallest])
        #expect(r.map(\.bench.model) == ["a", "c"])
    }

    @Test func smallestLeadsOnAnEightGigabyteMac() {
        let data = [b("accurate", 0.92, 0.01, 250, disk: 3), b("light", 0.89, 0.04, 350, disk: 0.7)]
        #expect(ModelRoles.roles(from: data, ramGB: 16).map(\.bench.model) == ["accurate", "light"])
        #expect(ModelRoles.roles(from: data, ramGB: 8).map(\.role) == [.smallest, .mostAccurate])
    }

    @Test func tieOnQualityGoesToFewerWrong() {
        let r = ModelRoles.roles(from: [b("x", 0.90, 0.05, 300), b("y", 0.84, 0.02, 300)])
        #expect(r.first?.bench.model == "y")
    }

    @Test func overBudgetModelsGetNoRole() {
        let r = ModelRoles.roles(from: [b("slow", 0.99, 0, 2000), b("ok", 0.8, 0.02, 300)])
        #expect(!r.contains { $0.bench.model == "slow" })
    }

    @Test func aModelThatLeansOnTheChooserGetsNoRole() {
        var asker = b("asker", 0.92, 0, 150)
        asker.chooser = 0.48
        var decider = b("decider", 0.85, 0.01, 112)
        decider.chooser = 0.18
        let r = ModelRoles.roles(from: [asker, decider])
        #expect(r.map(\.bench.model) == ["decider"])
    }
}

@MainActor
struct ModelManagerTests {
    @Test func startOnUninstalledSpecDoesNotThrowCwdError() async {
        // A start() against a model dir that doesn't exist used to die in
        // Process.run with a cwd error — the manifest guard must settle it
        // as .notInstalled without launching anything.
        let spec = ModelSpec(
            id: "not-installed-\(UUID().uuidString)",
            title: "Ghost", rank: 99, reason: "test", defaultPort: 0,
            blurb: "", kind: .venv(packages: [], serveArgv: ["serve"]),
            support: .supported,
            variants: [WeightSpec(id: "w", paramsLabel: "0B", diskLabel: "0",
                                  ramLabel: "0", serveModel: "m", hfRepo: "x")])
        let manager = ModelManager()
        await manager.start(.init(spec: spec, variant: spec.variants[0]))
        #expect(manager.status(of: spec.id) == .notInstalled)
        #expect(!manager.isRunning)
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
