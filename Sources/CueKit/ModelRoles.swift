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

    /// Accuracy that charges a wrong paste double — a wrong paste costs an
    /// undo plus a re-paste, a miss costs one keypress.
    public var quality: Double { resolved - 2 * wrong }
    public var meetsLatency: Bool { p50 <= 500 && p95 <= 1200 }
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
    /// - Fastest: lowest p50 with resolved ≥ 80%.
    /// - Best balance: highest `quality − 0.10·p50/500 − 0.05·diskGB/2`.
    /// Only models inside the latency budget (p50 ≤ 500, p95 ≤ 1200) qualify.
    public static func roles(from data: [ModelBenchmark]) -> [(role: ModelRole, bench: ModelBenchmark)] {
        var pool = data.filter(\.meetsLatency)
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
        take(.fastest, pool.filter { $0.resolved >= 0.8 }.min { $0.p50 < $1.p50 })
        take(.bestBalance, pool.max { balance($0) < balance($1) })
        return ModelRole.allCases.compactMap { r in out.first { $0.0 == r } }
    }

    static func balance(_ b: ModelBenchmark) -> Double {
        b.quality - 0.10 * b.p50 / 500 - 0.05 * b.diskGB / 2
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
            return s
        }
    }
}
