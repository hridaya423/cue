import Foundation

/// One model's measured CueEval result — frozen output of a benchmark run
/// (`Resources/benchmarks.json`, see Evals/results/summary.md). Never
/// recomputed at runtime.
public struct ModelBenchmark: Codable, Sendable, Equatable {
    public var model: String
    public var variant: String
    /// Fractions of the 110-case suite: right outcome / confident-wrong.
    public var resolved: Double
    public var wrong: Double
    public var p50: Double      // ms
    public var p95: Double      // ms
    public var diskGB: Double
    public var ramGB: Double
    /// Share of clear cases where the chooser showed instead of the paste (nil = not measured).
    public var chooser: Double? = nil

    /// Accuracy that charges a wrong paste double — a wrong paste costs an
    /// undo plus a re-paste, a miss costs one keypress.
    public var quality: Double { resolved - 2 * wrong }
    /// The engine's gates: inside the latency budget, and not leaning on the chooser for clear cases.
    /// Speed is judged on p95: most pastes never ask the model, so the median is 0 ms for every model.
    public var meetsGates: Bool { p95 <= 1200 && (chooser ?? 0) <= 0.2 }
}

public enum ModelRole: String, Sendable, CaseIterable {
    case mostAccurate = "Most accurate"
    case bestBalance = "Best balance"
    case fastest = "Fastest"

    /// Plain-words row subtitle.
    public var pitch: String {
        switch self {
        case .mostAccurate: "Fewest wrong pastes. Good for most Macs."
        case .bestBalance: "Small download, quick and careful."
        case .fastest: "Quickest decisions; guesses more often."
        }
    }
}

public enum ModelRoles {
    public static let benchmarks: [ModelBenchmark] = {
        guard let url = Bundle.module.url(forResource: "benchmarks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ModelBenchmark].self, from: data)) ?? []
    }()

    /// Roles in display order (the first is Recommended). Assigned in that
    /// order and each model holds at most one role:
    /// - Most accurate: highest `quality`, ties → fewer wrong pastes.
    /// - Fastest: lowest p95 with resolved ≥ 80%.
    /// - Best balance: highest `quality − 0.10·p95/1000 − 0.05·diskGB/2`.
    /// Only models that meet the gates (p95 ≤ 1200, chooser on clear ≤ 20%) qualify.
    public static func roles(from data: [ModelBenchmark]) -> [(role: ModelRole, bench: ModelBenchmark)] {
        var pool = data.filter(\.meetsGates)
        var out: [(ModelRole, ModelBenchmark)] = []
        func take(_ role: ModelRole, _ best: ModelBenchmark?) {
            guard let best else { return }
            out.append((role, best))
            pool.removeAll { $0.model == best.model }
        }
        // Quality compared at 0.1-point resolution so float noise can't
        // break a real tie.
        func q(_ b: ModelBenchmark) -> Double { (b.quality * 1000).rounded() }
        take(.mostAccurate, pool.max { (q($0), -$0.wrong) < (q($1), -$1.wrong) })
        take(.fastest, pool.filter { $0.resolved >= 0.8 }.min { $0.p95 < $1.p95 })
        take(.bestBalance, pool.max { balance($0) < balance($1) })
        return ModelRole.allCases.compactMap { r in out.first { $0.0 == r } }
    }

    static func balance(_ b: ModelBenchmark) -> Double {
        b.quality - 0.10 * b.p95 / 1000 - 0.05 * b.diskGB / 2
    }

    public static func role(of modelID: String) -> ModelRole? {
        roles(from: benchmarks).first { $0.bench.model == modelID }?.role
    }

    public static func benchmark(of modelID: String) -> ModelBenchmark? {
        benchmarks.first { $0.model == modelID }
    }

    /// Catalog with rank/reason taken from the roles: role models lead in
    /// role order, everything else keeps its relative order after them.
    static func apply(to specs: [ModelSpec], data: [ModelBenchmark] = benchmarks) -> [ModelSpec] {
        let roles = roles(from: data)
        guard !roles.isEmpty else { return specs }
        let rest = specs.filter { s in !roles.contains { $0.bench.model == s.id } }
            .sorted { $0.rank < $1.rank }.map(\.id)
        return specs.map { spec in
            var s = spec
            if let i = roles.firstIndex(where: { $0.bench.model == spec.id }) {
                s.rank = i + 1
                s.reason = roles[i].role.rawValue
            } else if let j = rest.firstIndex(of: spec.id) {
                s.rank = roles.count + j + 1
            }
            // Meters are measured, not editorial: accuracy = quality
            // (resolved − 2·wrong), speed = p50 against the 2.6 s ceiling.
            if let b = data.first(where: { $0.model == spec.id }) {
                let acc = min(max(b.quality, 0), 1)
                let spd = min(max(1 - b.p50 / 2600, 0.05), 1)
                s.variants = s.variants.map { v in
                    var v = v; v.accuracy = acc; v.speed = spd; return v
                }
            }
            return s
        }
    }
}
