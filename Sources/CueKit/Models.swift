import Foundation

// MARK: - Catalog

/// One downloadable weight set for a model family.
public struct WeightSpec: Sendable, Equatable, Identifiable {
    public var id: String
    public var paramsLabel: String   // "4B"
    public var diskLabel: String     // "~9 GB"
    public var ramLabel: String      // "~10 GB"
    public var recommended = false
    /// Meter bars in the picker, 0…1. Fallback defaults — `ModelRoles.apply`
    /// overwrites them with the frozen benchmark row where one exists.
    public var accuracy: Double
    public var speed: Double
    /// The `model` field sent in requests (e.g. kev-latest, multilingual).
    public var serveModel: String
    /// Hub repo or checkpoint id, substituted for {weights} in serve argv.
    public var hfRepo: String

    public init(id: String, paramsLabel: String, diskLabel: String, ramLabel: String,
                recommended: Bool = false, accuracy: Double = 0.5, speed: Double = 0.5,
                serveModel: String, hfRepo: String) {
        self.id = id; self.paramsLabel = paramsLabel; self.diskLabel = diskLabel
        self.ramLabel = ramLabel; self.recommended = recommended
        self.accuracy = accuracy; self.speed = speed
        self.serveModel = serveModel; self.hfRepo = hfRepo
    }
}

/// A local System One model Cue can install and run for the user.
public struct ModelSpec: Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Lower = better; Others list and recommendations sort on this.
    public var rank: Int
    /// The plain-language pitch shown as the card's badge — users don't know
    /// what kev/laya/von are; "Smallest" is what they can choose on.
    public var reason: String
    public var defaultPort: Int
    public var blurb: String
    public var kind: Kind
    public var support: Support
    public var variants: [WeightSpec]

    public enum Support: Sendable, Equatable {
        case supported
        /// Installable but likely slow/fragile on this Mac (label explains why).
        case experimental(String)
        /// Known-broken here (e.g. Triton deps); shown greyed, no install.
        case unsupported(String)
    }

    /// How the model's Python environment is built and served.
    /// `{port}` and `{weights}` placeholders in argv are substituted at run time.
    public enum Kind: Sendable, Equatable {
        /// `uv venv` + `uv pip install <pkgs>`; serve = `venv/bin/<argv[0]> rest…`
        case venv(packages: [String], serveArgv: [String])
        /// git clone + `uv sync <extras>` + extra `uv run` steps;
        /// serve = `uv run <serveArgv>` inside the repo.
        case repo(url: String, syncExtras: [String], installArgv: [[String]],
                  serveArgv: [String], env: [String: String])
        /// `uv venv` + `uv pip install <pkgs>`; serve = a bundled shim script
        /// (`Scripts/<script>`, or the app Resources copy) run as
        /// `python <script> {port} {weights} {serveModel} {snapshot}`.
        /// `downloadsSnapshot` additionally runs `hf download {weights}` into
        /// `snapshot/` and installs the snapshot's `requirements.txt` first —
        /// for models whose serving code ships inside the weight repo.
        case shim(packages: [String], script: String, downloadsSnapshot: Bool)
    }

    /// Resolved (model, variant) pair with the endpoint the client should hit.
    public struct Resolved: Sendable {
        public var spec: ModelSpec
        public var variant: WeightSpec
        public var endpointURL: URL {
            URL(string: "http://127.0.0.1:\(spec.defaultPort)/v1/systemone")!
        }
        public var serveModel: String { variant.serveModel }
    }
}

public enum ModelCatalog {
    /// The ranked list. Rank drives ordering in "Other local models" and the
    /// recommended badge; the role holders also get top-level rows in the picker.
    public static let all: [ModelSpec] = ModelRoles.apply(to: [
        kev, laya, von, jevons, jevlite,
        jevstyle, jevk5, startlux, vsr, clef, intern, jevnano, minicpm, s1qwen,
        decider, pplxdecider, s1lite, jevk5lite, kenning, truetype, gliner, scorer, openthai, bekko,
    ])

    /// The role holders (Recommended first) are the picker's top-level rows; everything else is "Others".
    public static var featured: [ModelSpec] {
        ModelRoles.roles(from: ModelRoles.benchmarks).compactMap { model($0.bench.model) }
    }

    public static var others: [ModelSpec] {
        let top = Set(featured.map(\.id))
        return all.filter { !top.contains($0.id) }.sorted { $0.rank < $1.rank }
    }

    public static func model(_ id: String) -> ModelSpec? {
        all.first { $0.id == id }
    }

    public static func variant(modelID: String, variantID: String) -> ModelSpec.Resolved? {
        guard let spec = model(modelID) else { return nil }
        let v = spec.variants.first { $0.id == variantID } ?? spec.variants.first
        guard let v else { return nil }
        return ModelSpec.Resolved(spec: spec, variant: v)
    }

    /// Default selection when the user picks a model without choosing weights.
    public static func defaultVariant(of spec: ModelSpec) -> WeightSpec? {
        spec.variants.first { $0.recommended } ?? spec.variants.first
    }

    // MARK: Entries

    public static let kev = ModelSpec(
        id: "kev", title: "Kev", rank: 1, reason: "Most accurate", defaultPort: 8009,
        blurb: "About 250 ms at worst, with 5% wrong pastes in Cue’s tests.",
        kind: .repo(url: "https://github.com/jaredpalmer/kev.git",
                    syncExtras: ["serve"], installArgv: [],
                    serveArgv: ["python", "-m", "kev.serve", "--run", "{weights}", "--port", "{port}"],
                    env: ["KEV_DTYPE": "bf16"]),
        support: .supported,
        variants: [
            WeightSpec(id: "kev-0.8b", paramsLabel: "0.8B", diskLabel: "~2 GB", ramLabel: "~4 GB",
                       recommended: true, accuracy: 0.85, speed: 0.85,
                       serveModel: "kev-latest", hfRepo: "jaredpalmer/kev-0.8b"),
            WeightSpec(id: "kev-4b", paramsLabel: "4B", diskLabel: "~9 GB", ramLabel: "~10 GB",
                       accuracy: 0.75, speed: 0.55,
                       serveModel: "kev-latest", hfRepo: "jaredpalmer/kev-4b"),
            WeightSpec(id: "kev-8b", paramsLabel: "8B", diskLabel: "~17 GB", ramLabel: "~18 GB",
                       accuracy: 0.85, speed: 0.35,
                       serveModel: "kev-latest", hfRepo: "jaredpalmer/kev-8b"),
            WeightSpec(id: "kev-9b", paramsLabel: "9B", diskLabel: "~19 GB", ramLabel: "~20 GB",
                       accuracy: 0.9, speed: 0.3,
                       serveModel: "kev-latest", hfRepo: "jaredpalmer/kev-9b"),
            WeightSpec(id: "kev-27b", paramsLabel: "27B", diskLabel: "~55 GB", ramLabel: "~56 GB",
                       accuracy: 0.95, speed: 0.1,
                       serveModel: "kev-latest", hfRepo: "jaredpalmer/kev-27b"),
        ])

    public static let laya = ModelSpec(
        id: "laya", title: "Laya", rank: 2, reason: "Smallest", defaultPort: 8765,
        blurb: "The quickest here (about 100 ms at worst), with 3% wrong pastes in Cue’s tests.",
        kind: .shim(packages: ["laya"], script: "laya_server.py", downloadsSnapshot: false),
        support: .supported,
        variants: [
            WeightSpec(id: "laya-en", paramsLabel: "421M", diskLabel: "~900 MB", ramLabel: "~1 GB",
                       accuracy: 0.8, speed: 0.8,
                       serveModel: "laya", hfRepo: "convaiinnovations/laya"),
            WeightSpec(id: "laya-multi", paramsLabel: "322M", diskLabel: "~700 MB", ramLabel: "~2 GB",
                       recommended: true, accuracy: 0.6, speed: 0.95,
                       serveModel: "multilingual", hfRepo: "convaiinnovations/laya-multilingual"),
            WeightSpec(id: "laya-typed", paramsLabel: "421M", diskLabel: "~900 MB", ramLabel: "~1 GB",
                       accuracy: 0.7, speed: 0.9,
                       serveModel: "typed-decisions", hfRepo: "convaiinnovations/laya-typed-decisions"),
        ])

    public static let von = ModelSpec(
        id: "von", title: "Von", rank: 3, reason: "Fastest", defaultPort: 8766,
        blurb: "About 200 ms at worst, with 4% wrong pastes in Cue’s tests.",
        kind: .venv(packages: ["von-sdk"],
                    serveArgv: ["von", "serve", "--host", "127.0.0.1", "--port", "{port}"]),
        support: .supported,
        variants: [
            WeightSpec(id: "von-1.0", paramsLabel: "395M", diskLabel: "~1.5 GB", ramLabel: "~4 GB",
                       recommended: true, accuracy: 0.7, speed: 0.95,
                       serveModel: "von-1.0", hfRepo: "wfzyx/von-1.0"),
        ])

    public static let jevons = ModelSpec(
        id: "jevons", title: "Jevons", rank: 4, reason: "Apple Silicon native", defaultPort: 8767,
        blurb: "1.2B LFM2.5 seed LoRA via MLX — native Apple Silicon. Smallest LLM-style option.",
        kind: .repo(url: "https://github.com/gopalanj/jevons.git",
                    syncExtras: ["mlx"],
                    installArgv: [
                        ["hf", "download", "mlx-community/LFM2.5-1.2B-Instruct-8bit", "--local-dir", "models/LFM2.5-1.2B-Instruct-8bit"],
                        ["hf", "download", "gopalanj/jevons-lfm25-1.2b-systemone", "--local-dir", "adapters/lfm25-1.2b-systemone"],
                    ],
                    serveArgv: ["jevons", "serve", "--host", "127.0.0.1", "--port", "{port}"],
                    env: ["JEVONS_MODEL": "models/LFM2.5-1.2B-Instruct-8bit",
                          "JEVONS_ADAPTER": "adapters/lfm25-1.2b-systemone",
                          "JEVONS_TEMPERATURE": "1", "JEVONS_CALIBRATION": "off"]),
        support: .experimental("MLX build; adapter quality still improving"),
        variants: [
            WeightSpec(id: "jevons-1.2b", paramsLabel: "1.2B", diskLabel: "~1.5 GB", ramLabel: "~2 GB",
                       recommended: true, accuracy: 0.6, speed: 0.7,
                       serveModel: "jevons", hfRepo: "gopalanj/jevons-lfm25-1.2b-systemone"),
        ])

    public static let jevlite = ModelSpec(
        id: "jevlite", title: "jev-lite", rank: 5, reason: "Logits decision head", defaultPort: 8768,
        blurb: "QLoRA on Gemma E4B — logits-read decision head, 4-bit base.",
        kind: .repo(url: "https://github.com/vagmi/jevlite.git",
                    syncExtras: [], installArgv: [],
                    serveArgv: ["python", "serve.py", "--host", "127.0.0.1", "--port", "{port}"],
                    env: [:]),
        support: .experimental("bitsandbytes 4-bit is fragile on macOS"),
        variants: [
            WeightSpec(id: "jev-lite-e4b", paramsLabel: "4B", diskLabel: "~4 GB", ramLabel: "~6 GB",
                       recommended: true, accuracy: 0.7, speed: 0.5,
                       serveModel: "jev-lite-gemma4-e4b", hfRepo: "vagmi/jev-lite"),
        ])

    /// Runs on Metal through mlx-lm (`decider_mlx_server.py`): decider's own prompt building and readout,
    /// fp16 weights, padded batches split when that's faster. Parity with decider's torch path: max |Δp|
    /// 0.0099, no argmax flips. The most accurate local model (1% wrong).
    public static let decider = ModelSpec(
        id: "decider", title: "Decider", rank: 15, reason: "Full fine-tunes", defaultPort: 8790,
        blurb: "Picks the right clip most often in Cue’s tests (1% wrong), about 250 ms at worst on Apple silicon.",
        kind: .shim(packages: ["decider-ai==1.9.0", "mlx==0.32.2", "mlx-lm==0.31.3",
                               "fastapi==0.149.0", "uvicorn==0.54.0"],
                    script: "decider_mlx_server.py", downloadsSnapshot: false),
        support: .supported,
        variants: [
            WeightSpec(id: "decider-0.8b", paramsLabel: "0.8B", diskLabel: "~1.6 GB", ramLabel: "~3 GB",
                       recommended: true, accuracy: 0.83, speed: 0.95,
                       serveModel: "decider-0.8b", hfRepo: "Mapika/decider-0.8b"),
            WeightSpec(id: "decider-2b", paramsLabel: "1.9B", diskLabel: "~4 GB", ramLabel: "~5 GB",
                       accuracy: 0.8, speed: 0.6,
                       serveModel: "decider-2b", hfRepo: "Mapika/decider-2b"),
        ])

    /// Cloudflare's Clef decision models — the joint-schema-head readout ships
    /// inside the weight snapshot (`joint_schema_model.py`, `systemone()`).
    /// Apache-2.0, multimodal, fully System One-compatible.
    public static let clef = ModelSpec(
        id: "clef", title: "Clef", rank: 10, reason: "Cloudflare", defaultPort: 8774,
        blurb: "Cloudflare's decision models — multimodal, Jev-native contract, top of the Decision Index.",
        kind: .shim(packages: ["torch>=2.8", "transformers>=5.10.2", "safetensors",
                               "pillow", "accelerate"],
                    script: "clef_server.py", downloadsSnapshot: true),
        support: .experimental("transformers 5 + joint schema head; MPS path unverified"),
        variants: [
            WeightSpec(id: "clef-flash", paramsLabel: "9B", diskLabel: "~19 GB", ramLabel: "~20 GB",
                       recommended: true, accuracy: 0.85, speed: 0.3,
                       serveModel: "clef-flash", hfRepo: "Cloudflare/clef-flash"),
            WeightSpec(id: "clef-27b", paramsLabel: "27B", diskLabel: "~54 GB", ramLabel: "~56 GB",
                       accuracy: 0.9, speed: 0.1,
                       serveModel: "clef", hfRepo: "Cloudflare/clef"),
        ])

    /// StartLux-Decision — ships its own /v1/systemone server in the weight
    /// repo (`startlux_decision.server`) and auto-selects an MLX backend on
    /// Apple Silicon. Weights are CC BY-NC-4.0: non-commercial use only.
    public static let startlux = ModelSpec(
        id: "startlux", title: "StartLux", rank: 8, reason: "Native server", defaultPort: 8772,
        blurb: "Ships its own /v1/systemone server with an Apple Silicon MLX backend. Weights are non-commercial (CC BY-NC).",
        kind: .shim(packages: [], script: "startlux_server.py", downloadsSnapshot: true),
        support: .experimental("CC BY-NC-4.0 weights — non-commercial use only"),
        variants: [
            WeightSpec(id: "slx-4b", paramsLabel: "4B", diskLabel: "~8 GB", ramLabel: "~9 GB",
                       recommended: true, accuracy: 0.8, speed: 0.5,
                       serveModel: "StartLux-Decision-4B", hfRepo: "startlux-models/StartLux-Decision-4B"),
            WeightSpec(id: "slx-2b", paramsLabel: "2B", diskLabel: "~4 GB", ramLabel: "~5 GB",
                       accuracy: 0.72, speed: 0.65,
                       serveModel: "StartLux-Decision-2B", hfRepo: "startlux-models/StartLux-Decision-2B"),
            WeightSpec(id: "slx-0.8b", paramsLabel: "0.8B", diskLabel: "~1.6 GB", ramLabel: "~2.5 GB",
                       accuracy: 0.6, speed: 0.85,
                       serveModel: "StartLux-Decision-0.8B", hfRepo: "startlux-models/StartLux-Decision-0.8B"),
            WeightSpec(id: "slx-9b", paramsLabel: "9B", diskLabel: "~18 GB", ramLabel: "~19 GB",
                       accuracy: 0.85, speed: 0.35,
                       serveModel: "StartLux-Decision-9B", hfRepo: "startlux-models/StartLux-Decision-9B"),
        ])

    /// Jev-Style v3 — chaoliangUNSW's calibrated 0.8B/2B line. The `jev-style`
    /// pip package ships a complete server (`jev-style serve`) that picks MLX
    /// on Apple Silicon. The most turnkey new install.
    public static let jevstyle = ModelSpec(
        id: "jevstyle", title: "Jev-Style", rank: 6, reason: "Best on-device", defaultPort: 8770,
        blurb: "Calibrated 0.8B/2B decision models — MLX-first on Apple Silicon, long-context, 51 languages.",
        kind: .venv(packages: ["jev-style[mlx]"],
                    serveArgv: ["jev-style", "serve", "--host", "127.0.0.1",
                                "--port", "{port}", "--release", "{serveModel}"]),
        support: .experimental("solid pip install path; accuracy unmeasured in Cue's benchmark"),
        variants: [
            WeightSpec(id: "jevstyle-0.8b", paramsLabel: "0.8B", diskLabel: "~0.8 GB", ramLabel: "~1.5 GB",
                       recommended: true, accuracy: 0.7, speed: 0.9,
                       serveModel: "0.8b", hfRepo: "chaoliangUNSW/Jev-Style-0.8B-Decision-v3"),
            WeightSpec(id: "jevstyle-2b", paramsLabel: "2B", diskLabel: "~2 GB", ramLabel: "~3 GB",
                       accuracy: 0.75, speed: 0.7,
                       serveModel: "2b", hfRepo: "chaoliangUNSW/Jev-Style-2B-Decision-v3"),
        ])

    /// JevK5 — 2nd of 76 systems on JevBench v1.4, the top open entrant.
    /// On Mac the documented path is llama.cpp + GGUF; our shim loads it
    /// in-process via llama_cpp and reuses the package's calibration math.
    public static let jevk5 = ModelSpec(
        id: "jevk5", title: "JevK5", rank: 7, reason: "Top open model", defaultPort: 8771,
        blurb: "2nd of 76 on JevBench v1.4 — the strongest open decision model that runs on a laptop.",
        kind: .shim(packages: ["jevk5 @ git+https://github.com/allebee/jevk5@v0.3.2",
                               "llama-cpp-python", "numpy", "huggingface_hub"],
                    script: "jevk5_server.py", downloadsSnapshot: false),
        support: .experimental("in-process llama.cpp GGUF; Metal on Apple Silicon"),
        variants: [
            WeightSpec(id: "jevk5-4b", paramsLabel: "4B", diskLabel: "~4.5 GB", ramLabel: "~6 GB",
                       recommended: true, accuracy: 0.85, speed: 0.5,
                       serveModel: "jevk5-4b-v0.3-Q8_0.gguf", hfRepo: "alibiserikbay/JevK5-GGUF"),
            WeightSpec(id: "jevk5-4b-q4", paramsLabel: "4B Q4", diskLabel: "~2.7 GB", ramLabel: "~4 GB",
                       accuracy: 0.8, speed: 0.6,
                       serveModel: "jevk5-4b-v0.3-Q4_K_M.gguf", hfRepo: "alibiserikbay/JevK5-GGUF"),
            WeightSpec(id: "jevk5-2b", paramsLabel: "2B", diskLabel: "~2 GB", ramLabel: "~3 GB",
                       accuracy: 0.7, speed: 0.75,
                       serveModel: "jevk5-2b-v0.2-Q8_0.gguf", hfRepo: "alibiserikbay/JevK5-GGUF"),
            WeightSpec(id: "jevk5-9b", paramsLabel: "9B", diskLabel: "~9.5 GB", ramLabel: "~11 GB",
                       accuracy: 0.9, speed: 0.3,
                       serveModel: "jevk5-9b-v0.3.3-Q8_0.gguf", hfRepo: "alibiserikbay/JevK5-GGUF"),
        ])

    /// vLLM Semantic Router's Decision 2.0 line — transformers weights whose
    /// remote code exposes `model.system_one()` directly.
    public static let vsr = ModelSpec(
        id: "vsr", title: "Decision 2.0", rank: 9, reason: "vLLM router", defaultPort: 8773,
        blurb: "vLLM Semantic Router's Decision 2.0 — five sizes, one-pass typed decisions.",
        kind: .shim(packages: ["torch>=2.8", "transformers>=5.17", "safetensors", "accelerate"],
                    script: "vsr_server.py", downloadsSnapshot: false),
        support: .experimental("trust_remote_code weights; CPU/MPS path unverified"),
        variants: [
            WeightSpec(id: "vsr-eos", paramsLabel: "0.8B", diskLabel: "~1.6 GB", ramLabel: "~3 GB",
                       recommended: true, accuracy: 0.7, speed: 0.85,
                       serveModel: "Decision-2.0-Eos-0.8B", hfRepo: "vllm-sr/Decision-2.0-Eos-0.8B"),
            WeightSpec(id: "vsr-sol", paramsLabel: "2B", diskLabel: "~4 GB", ramLabel: "~5 GB",
                       accuracy: 0.75, speed: 0.65,
                       serveModel: "Decision-2.0-Sol-2B", hfRepo: "vllm-sr/Decision-2.0-Sol-2B"),
            WeightSpec(id: "vsr-kai", paramsLabel: "0.6B", diskLabel: "~1.3 GB", ramLabel: "~2 GB",
                       accuracy: 0.6, speed: 0.9,
                       serveModel: "Decision-2.0-Kai-0.6B", hfRepo: "vllm-sr/Decision-2.0-Kai-0.6B"),
            WeightSpec(id: "vsr-nox", paramsLabel: "4B", diskLabel: "~8 GB", ramLabel: "~9 GB",
                       accuracy: 0.8, speed: 0.45,
                       serveModel: "Decision-2.0-Nox-4B", hfRepo: "vllm-sr/Decision-2.0-Nox-4B"),
            WeightSpec(id: "vsr-lux", paramsLabel: "9B", diskLabel: "~18 GB", ramLabel: "~19 GB",
                       accuracy: 0.85, speed: 0.3,
                       serveModel: "Decision-2.0-Lux-9B", hfRepo: "vllm-sr/Decision-2.0-Lux-9B"),
        ])

    /// Intern-Decision (internlm) — multimodal, A–Z symbol readout, ships an
    /// in-repo `DecisionEngine` that answers one Jev request at a time.
    public static let intern = ModelSpec(
        id: "intern", title: "Intern-Decision", rank: 11, reason: "Multimodal", defaultPort: 8775,
        blurb: "InternLM's structured decision line — multimodal, calibrated, Apache-2.0.",
        kind: .shim(packages: ["torch>=2.8", "transformers>=5.8", "pillow",
                               "safetensors", "accelerate"],
                    script: "intern_server.py", downloadsSnapshot: true),
        support: .experimental("in-repo inference.py; CUDA-leaning but device-portable"),
        variants: [
            WeightSpec(id: "intern-2b", paramsLabel: "2B", diskLabel: "~4 GB", ramLabel: "~5 GB",
                       recommended: true, accuracy: 0.75, speed: 0.55,
                       serveModel: "Intern-Decision-2B", hfRepo: "internlm/Intern-Decision-2B"),
            WeightSpec(id: "intern-0.8b", paramsLabel: "0.8B", diskLabel: "~1.7 GB", ramLabel: "~2.5 GB",
                       accuracy: 0.65, speed: 0.75,
                       serveModel: "Intern-Decision-0.8B", hfRepo: "internlm/Intern-Decision-0.8B"),
            WeightSpec(id: "intern-4b", paramsLabel: "4B", diskLabel: "~8 GB", ramLabel: "~9 GB",
                       accuracy: 0.8, speed: 0.4,
                       serveModel: "Intern-Decision-4B", hfRepo: "internlm/Intern-Decision-4B"),
        ])

    /// tasksource-jev-nano — a 149M ColBERT (PyLate) decision model. Tiny and
    /// CPU-fast; weakest on knowledge/reasoning but honest about it.
    public static let jevnano = ModelSpec(
        id: "jevnano", title: "jev-nano", rank: 12, reason: "Smallest", defaultPort: 8776,
        blurb: "149M ColBERT decision model — tiny and CPU-fast; weakest on reasoning.",
        kind: .shim(packages: ["pylate"], script: "nano_server.py", downloadsSnapshot: false),
        support: .experimental("score answers synthesized from ordered levels"),
        variants: [
            WeightSpec(id: "jev-nano-v1", paramsLabel: "149M", diskLabel: "~600 MB", ramLabel: "~1 GB",
                       recommended: true, accuracy: 0.4, speed: 0.95,
                       serveModel: "tasksource-jev-nano-v1", hfRepo: "tasksource/tasksource-jev-nano-v1"),
        ])

    /// system-one MiniCPM — mpuig's MIT-licensed System One rebuild: 2B MiniCPM5
    /// fused LoRA at 8-bit MLX, per-primitive calibrated temperatures, and a
    /// native `/v1/systemone` server (`scripts/serve.py`) in the repo.
    public static let minicpm = ModelSpec(
        id: "minicpm", title: "system-one MiniCPM", rank: 13, reason: "MIT + calibrated", defaultPort: 8782,
        blurb: "MIT 2B MLX decision model — per-primitive temperature calibration, 73% out-of-family.",
        kind: .repo(url: "https://github.com/mpuig/system-one.git",
                    syncExtras: [],
                    // The engine fail-closes when the model dir's file hashes
                    // don't match the temperature artifact's backbone_files —
                    // `hf download` leaves adapter/, .cache/ and temperature.json
                    // behind, so we move the artifact out and prune the rest.
                    installArgv: [
                        ["hf", "download", "mpuig/system-one-minicpm5-2b-q8", "--local-dir", "models/system-one-minicpm5-2b-q8"],
                        ["cp", "models/system-one-minicpm5-2b-q8/temperature.json", "temperature-minicpm5-2b-q8.json"],
                        ["python", "-c", "import os, shutil; d='models/system-one-minicpm5-2b-q8'; [shutil.rmtree(d+'/'+p, ignore_errors=True) for p in ('adapter', '.cache')]; os.path.exists(d+'/temperature.json') and os.remove(d+'/temperature.json')"],
                    ],
                    serveArgv: ["python", "scripts/serve.py",
                                "--model", "models/system-one-minicpm5-2b-q8",
                                "--temperature", "temperature-minicpm5-2b-q8.json",
                                "--host", "127.0.0.1", "--port", "{port}"],
                    env: [:]),
        support: .experimental("native server; thresholds calibrated in-family — see card's shift warning"),
        variants: [
            WeightSpec(id: "minicpm-2b", paramsLabel: "2B", diskLabel: "~2.5 GB", ramLabel: "~4 GB",
                       recommended: true, accuracy: 0.73, speed: 0.85,
                       serveModel: "models/system-one-minicpm5-2b-q8", hfRepo: "mpuig/system-one-minicpm5-2b-q8"),
        ])

    /// system-one Qwen3 — the same MIT recipe as a rank-16 LoRA on Qwen3-0.6B;
    /// volume tier: ~1.4 GB of base+adapter.
    public static let s1qwen = ModelSpec(
        id: "s1qwen", title: "system-one Qwen3", rank: 14, reason: "MIT + smallest MLX", defaultPort: 8783,
        blurb: "MIT 0.6B MLX decision model — LoRA on Qwen3, calibrated, the lightest System One build.",
        kind: .repo(url: "https://github.com/mpuig/system-one.git",
                    syncExtras: [],
                    // Same fail-closed identity check as minicpm: the base dir
                    // must hash down to exactly Qwen3-0.6B's seven core files —
                    // no LICENSE/README/.cache. The adapter dir's extras are
                    // fine; only adapters.safetensors is hashed there.
                    installArgv: [
                        ["hf", "download", "Qwen/Qwen3-0.6B", "--local-dir", "models/qwen3-0.6b"],
                        ["hf", "download", "mpuig/system-one-qwen3-0.6b", "--local-dir", "adapters/system-one-qwen3-0.6b"],
                        ["python", "-c", "import os, shutil; d='models/qwen3-0.6b'; [os.remove(d+'/'+f) for f in ('LICENSE','README.md') if os.path.exists(d+'/'+f)]; [shutil.rmtree(p+'/.cache', ignore_errors=True) for p in (d, 'adapters/system-one-qwen3-0.6b')]"],
                    ],
                    serveArgv: ["python", "scripts/serve.py",
                                "--model", "models/qwen3-0.6b",
                                "--adapter", "adapters/system-one-qwen3-0.6b",
                                "--temperature", "adapters/system-one-qwen3-0.6b/temperature.json",
                                "--host", "127.0.0.1", "--port", "{port}"],
                    env: [:]),
        support: .experimental("volume tier: 66% out-of-family per card; same shift warning applies"),
        variants: [
            WeightSpec(id: "s1qwen-0.6b", paramsLabel: "0.6B", diskLabel: "~1.4 GB", ramLabel: "~3 GB",
                       recommended: true, accuracy: 0.66, speed: 0.9,
                       serveModel: "models/qwen3-0.6b", hfRepo: "mpuig/system-one-qwen3-0.6b"),
        ])

    /// Perplexity's pplx-decider — the 27B line that tops the public Decision
    /// Index. Its autojev runtime is CUDA-only and wants ~49 GiB of weights.
    public static let pplxdecider = ModelSpec(
        id: "pplxdecider", title: "pplx-decider", rank: 16, reason: "Perplexity", defaultPort: 8777,
        blurb: "Perplexity's 27B decider — the strongest open decision model. Needs a datacenter GPU.",
        kind: .venv(packages: [], serveArgv: []),
        support: .unsupported("CUDA-only autojev runtime; ~49 GiB bf16 weights"),
        variants: [
            WeightSpec(id: "pplx-decider-v1.1", paramsLabel: "27B", diskLabel: "~54 GB", ramLabel: "~50 GB",
                       accuracy: 0.9, speed: 0.15,
                       serveModel: "pplx-decider-v1.1-27b", hfRepo: "perplexity-ai/pplx-decider-v1.1-27b"),
            WeightSpec(id: "pplx-decider-v1", paramsLabel: "27B", diskLabel: "~54 GB", ramLabel: "~50 GB",
                       accuracy: 0.85, speed: 0.15,
                       serveModel: "pplx-decider-v1-27b", hfRepo: "perplexity-ai/pplx-decider-v1-27b"),
        ])

    /// systemone-lite — a 0.5B hobbyist System One model with its own runtime
    /// (`systemone-lite` CLI). MIT.
    public static let s1lite = ModelSpec(
        id: "s1lite", title: "systemone-lite", rank: 17, reason: "Tiny runtime", defaultPort: 8778,
        blurb: "0.5B Qwen2.5 hobbyist System One — option-token scoring, MIT.",
        kind: .repo(url: "https://github.com/fritzprix/systemone-lite.git",
                    syncExtras: [], installArgv: [],
                    serveArgv: ["systemone-lite", "--model", "{weights}", "--port", "{port}"],
                    env: [:]),
        support: .experimental("unverified upstream; niche 0.5B quality"),
        variants: [
            WeightSpec(id: "s1lite-0.5b", paramsLabel: "0.5B", diskLabel: "~1 GB", ramLabel: "~1.5 GB",
                       recommended: true, accuracy: 0.5, speed: 0.8,
                       serveModel: "systemone-lite-0.5b", hfRepo: "dwidlee/systemone-lite-0.5b"),
        ])

    /// GLiNER2.5-Decide — Fastino's 340M routing classifier. Fast and good on
    /// fast-decisions, but it emits only the winning label, not a distribution.
    public static let gliner = ModelSpec(
        id: "gliner", title: "GLiNER-Decide", rank: 19, reason: "Classifier", defaultPort: 8779,
        blurb: "Fastino's 340M label classifier — fast on routing tasks, but argmax-only output.",
        kind: .venv(packages: [], serveArgv: []),
        support: .unsupported("returns the winning label only — the chooser needs calibrated probabilities"),
        variants: [
            WeightSpec(id: "gliner-decide", paramsLabel: "340M", diskLabel: "~700 MB", ramLabel: "~1 GB",
                       accuracy: 0.5, speed: 0.95,
                       serveModel: "gliner-decide", hfRepo: "fastino/GLiNER2.5-Decide"),
        ])

    /// pngwn's System One scorer — Qwen3.5-4B with a sequence-classification
    /// head. CC BY-NC-4.0 weights and no published server.
    public static let scorer = ModelSpec(
        id: "scorer", title: "S1 Scorer", rank: 20, reason: "Scoring head", defaultPort: 8780,
        blurb: "Qwen3.5-4B + sequence-classification head — single-pass System One scorer.",
        kind: .venv(packages: [], serveArgv: []),
        support: .unsupported("CC BY-NC-4.0 weights; no published server"),
        variants: [
            WeightSpec(id: "scorer-4b", paramsLabel: "4B", diskLabel: "~8 GB", ramLabel: "~9 GB",
                       accuracy: 0.7, speed: 0.4,
                       serveModel: "s1-scorer", hfRepo: "pngwn/system-one-qwen3.5-4b-scorer"),
        ])

    /// OpenThai-SystemOne — a Thai+English decision model on Qwen3.5-0.8B.
    /// Real System One contract; only an Ollama build is published so far.
    public static let openthai = ModelSpec(
        id: "openthai", title: "OpenThai S1", rank: 21, reason: "Thai", defaultPort: 8781,
        blurb: "Thai+English System One on Qwen3.5-0.8B — strong for Thai apps.",
        kind: .venv(packages: [], serveArgv: []),
        support: .unsupported("Thai-optimized; only an Ollama build is published"),
        variants: [
            WeightSpec(id: "openthai-0.8b", paramsLabel: "0.8B", diskLabel: "~1.6 GB", ramLabel: "~2.5 GB",
                       accuracy: 0.6, speed: 0.7,
                       serveModel: "OpenThai-SystemOne", hfRepo: "iapp/OpenThai-SystemOne"),
        ])

    /// JevK5-Lite — 437M DeBERTa-v3 CPU label classifier from the JevK5
    /// project. Generic heads, not a typed-decision runtime: our shim maps
    /// each question to a single-label head and reads calibrated
    /// probabilities back. Its card says preview; on Cue's suite it resolves 89% with 4% wrong.
    public static let jevk5lite = ModelSpec(
        id: "jevk5lite", title: "JevK5-Lite", rank: 18, reason: "CPU classifier", defaultPort: 8784,
        blurb: "Uses the least memory here (under 1 GB). About 350 ms at worst, with 4% wrong pastes in Cue’s tests.",
        kind: .shim(packages: ["jevk5[lite] @ git+https://github.com/allebee/jevk5@v0.3.1"],
                    script: "lite_server.py", downloadsSnapshot: false),
        support: .supported,
        variants: [
            WeightSpec(id: "jevk5-lite", paramsLabel: "437M", diskLabel: "~1.7 GB", ramLabel: "~0.7 GB",
                       recommended: true, accuracy: 0.5, speed: 0.85,
                       serveModel: "JevK5-Lite", hfRepo: "alibiserikbay/JevK5-Lite"),
        ])

    /// Kenning — systemone-builder's Apache-2.0 family, the most complete
    /// open System One implementation found in the sweep: contract-native
    /// wire format, per-type temperatures shipped in the weights, and two
    /// engines. kenning-large-* are cross-encoders (every option scored
    /// against the state in batched pairs); kenning-xl is a Qwen3-1.7B
    /// decoder that escalates to a short reasoning trace on hard
    /// structured questions and beats Clef on agent decisions. The stock
    /// servers bind 0.0.0.0 on CPU, so the shim drives the model classes
    /// directly on loopback with MPS.
    public static let kenning = ModelSpec(
        id: "kenning", title: "Kenning", rank: 24, reason: "Apache-2.0 native", defaultPort: 8788,
        blurb: "Cross-encoder / XL decoder — contract-native, calibrated; the deepest Apache-2.0 family in the sweep.",
        kind: .shim(packages: ["systemone-builder @ git+https://github.com/systemonedev/systemone-builder#subdirectory=backend",
                               "torch", "transformers", "sentencepiece"],
                    script: "kenning_server.py", downloadsSnapshot: false),
        support: .experimental("native contract server via builder shim; cross-encoder cost grows with option count"),
        variants: [
            WeightSpec(id: "kenning-v06", paramsLabel: "~400M", diskLabel: "~1.6 GB", ramLabel: "~3 GB",
                       recommended: true, accuracy: 0.7, speed: 0.6,
                       serveModel: "kenning-large-v0.6", hfRepo: "systemonedev/kenning-large-v0.6"),
            WeightSpec(id: "kenning-v05", paramsLabel: "435M", diskLabel: "~1.7 GB", ramLabel: "~2 GB",
                       accuracy: 0.68, speed: 0.6,
                       serveModel: "kenning-large-v0.5", hfRepo: "systemonedev/kenning-large-v0.5"),
            WeightSpec(id: "kenning-xl-v06", paramsLabel: "1.7B", diskLabel: "~3.4 GB", ramLabel: "~4 GB",
                       accuracy: 0.72, speed: 0.45,
                       serveModel: "kenning-xl-v0.6", hfRepo: "systemonedev/kenning-xl-v0.6"),
        ])

    /// stephenlb/system-one-model — a Gemma-4-12B whose LM head was swapped
    /// for a 26-logit decision head: one forward pass answers every question
    /// type with real probabilities. The publisher benchmarked on Apple
    /// Silicon (117 ms p50). Heavy (~24 GB bf16) and gated behind the Gemma
    /// licence, but contract-native and genuinely local.
    public static let truetype = ModelSpec(
        id: "truetype", title: "System One (Gemma)", rank: 23, reason: "12B single-pass", defaultPort: 8789,
        blurb: "Gemma-4-12B with a decision head — one pass, all primitives; 24 GB, HF-gated.",
        kind: .shim(packages: ["transformers>=5.17", "torch", "accelerate", "sentencepiece", "protobuf"],
                    script: "truetype_server.py", downloadsSnapshot: false),
        support: .experimental("~24 GB download; gated repo — HF login plus Gemma licence required"),
        variants: [
            WeightSpec(id: "truetype-12b", paramsLabel: "12B", diskLabel: "~24 GB", ramLabel: "~26 GB",
                       recommended: true, accuracy: 0.85, speed: 0.5,
                       serveModel: "system-one-model", hfRepo: "stephenlb/system-one-model"),
        ])

    /// bekko-system-one — hotchpotch's 17M/68M/400M ModernBERT typed-decision
    /// family, the smallest native contract models anywhere. S1MB-measured
    /// (400m: Task Avg 50.6 vs Jev 1.13's 59.6). Listed but not installable:
    /// the publisher declares the weights+code license "to be finalized" —
    /// unlicensed weights are all-rights-reserved, so installing them in-app
    /// would be dishonest.
    public static let bekko = ModelSpec(
        id: "bekko", title: "bekko system-one", rank: 22, reason: "Unlicensed", defaultPort: 8785,
        blurb: "17M–400M native typed-decision models — contract-native, but published without a license.",
        kind: .venv(packages: [], serveArgv: []),
        support: .unsupported("weights published with no license (card: 'to be finalized')"),
        variants: [
            WeightSpec(id: "bekko-400m", paramsLabel: "400M", diskLabel: "~1.5 GB", ramLabel: "~1.5 GB",
                       accuracy: 0.65, speed: 0.9,
                       serveModel: "bekko-system-one-v0-400m", hfRepo: "hotchpotch/bekko-system-one-v0-400m"),
            WeightSpec(id: "bekko-68m", paramsLabel: "68M", diskLabel: "~300 MB", ramLabel: "~500 MB",
                       accuracy: 0.5, speed: 0.95,
                       serveModel: "bekko-system-one-v0-68m", hfRepo: "hotchpotch/bekko-system-one-v0-68m"),
            WeightSpec(id: "bekko-17m", paramsLabel: "17M", diskLabel: "~80 MB", ramLabel: "~200 MB",
                       accuracy: 0.35, speed: 0.98,
                       serveModel: "bekko-system-one-v0-17m", hfRepo: "hotchpotch/bekko-system-one-v0-17m"),
        ])
}

// MARK: - Manager

/// Installs and runs local model servers. Models live under
/// `Application Support/Cue/models/<id>/` with a manifest.json marking a
/// completed install. One server runs at a time — switching stops the old one.
@MainActor @Observable
public final class ModelManager {
    public enum State: Equatable, Sendable {
        case notInstalled
        case installing(String)   // phase label
        case installed
        case starting
        case running
        case failed(String)
    }

    public private(set) var states: [String: State] = [:]
    /// Last output line per model — shown under the install progress.
    public private(set) var logTail: [String: String] = [:]
    public private(set) var transfers: [String: ModelTransferProgress] = [:]
    public private(set) var warmupMilliseconds: [String: Int] = [:]

    public private(set) var uvPath: String?
    public private(set) var uvBootstrapping = false

    private var server: Process?
    private var serverModelID: String?

    public init() {
        // Restore installed marks from manifests on disk.
        for spec in ModelCatalog.all where manifestExists(spec.id) {
            states[spec.id] = .installed
        }
        uvPath = Self.findUV()
    }

    public func status(of modelID: String) -> State {
        if let s = states[modelID] { return s }
        return manifestExists(modelID) ? .installed : .notInstalled
    }

    public var isRunning: Bool { server != nil }

    // MARK: - Install

    /// Full pipeline: bootstrap uv → build env → write manifest.
    /// Re-running with a different variant rebuilds and updates the manifest.
    public func install(_ resolved: ModelSpec.Resolved) async {
        let spec = resolved.spec
        if case .installing = status(of: spec.id) { return }
        if case .unsupported = spec.support { return }
        setState(spec.id, .installing("preparing"))

        do {
            try await ensureUV()
            let dir = modelDir(spec.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            switch spec.kind {
            case .venv(let packages, _), .shim(let packages, _, _):
                try await runStep(spec.id, "creating venv",
                                  uvArgv(["venv", dir.appendingPathComponent("venv").path, "--python", "3.12"]), cwd: dir)
                let py = dir.appendingPathComponent("venv/bin/python").path
                var pkgs = packages
                if spec.downloadsSnapshot { pkgs.append("huggingface_hub") }
                try await runStep(spec.id, "installing packages",
                                  uvArgv(["pip", "install", "--python", py] + pkgs), cwd: dir)
                if spec.downloadsSnapshot {
                    let snapshot = dir.appendingPathComponent("snapshot")
                    try await runStep(spec.id, "downloading weights",
                                      [dir.appendingPathComponent("venv/bin/hf").path,
                                       "download", resolved.variant.hfRepo, "--local-dir", snapshot.path], cwd: dir)
                    let reqs = snapshot.appendingPathComponent("requirements.txt")
                    if FileManager.default.fileExists(atPath: reqs.path) {
                        try await runStep(spec.id, "installing model requirements",
                                          uvArgv(["pip", "install", "--python", py, "-r", reqs.path]), cwd: dir)
                    }
                }
            case .repo(let url, let extras, let extraSteps, _, _):
                let repoDir = dir.appendingPathComponent("repo")
                if !FileManager.default.fileExists(atPath: repoDir.path) {
                    try await runStep(spec.id, "cloning repo",
                                      ["/usr/bin/git", "clone", "--depth", "1", url, repoDir.path], cwd: dir)
                }
                let sync = ["sync"] + extras.flatMap { ["--extra", $0] }
                try await runStep(spec.id, "installing dependencies", uvArgv(sync), cwd: repoDir)
                for step in extraSteps {
                    try await runStep(spec.id, "downloading weights",
                                      uvArgv(["run"] + extras.flatMap { ["--extra", $0] } + step), cwd: repoDir)
                }
            }
            try writeManifest(resolved)
            setState(spec.id, .installed)
        } catch {
            setState(spec.id, .failed(error.localizedDescription))
        }
    }

    // MARK: - Serve

    /// Spawn the server and wait for it to answer. First start may download
    /// weights (GBs) — the phase label says so and the timeout is generous.
    public func start(_ resolved: ModelSpec.Resolved) async {
        let spec = resolved.spec
        // Never launch from a missing install dir — the process would fail
        // with a cwd error. Uninstalled specs settle as .notInstalled.
        guard manifestExists(spec.id) else {
            setState(spec.id, .notInstalled)
            return
        }
        if serverModelID == spec.id, server?.isRunning == true {
            switch status(of: spec.id) {
            case .running, .starting: return
            default: break
            }
        }
        // A server already answering on this model's port — an orphan from
        // a prior launch or an eval job — is a working endpoint, not a
        // failure to start. Adopt it rather than spawn-and-crash.
        if await portAnswers(spec.defaultPort) {
            setState(spec.id, .running)
            return
        }
        stop()
        setState(spec.id, .starting)
        transfers[spec.id] = nil
        warmupMilliseconds[spec.id] = nil

        let dir = modelDir(spec.id)
        let argv = serveArgv(resolved)
        let env = serveEnv(spec)
        let cwd: URL = spec.isRepo ? dir.appendingPathComponent("repo") : dir

        let proc = Process()
        if spec.isRepo {
            let full = uvArgv(["run"] + spec.syncExtras.flatMap { ["--extra", $0] } + argv)
            proc.executableURL = URL(fileURLWithPath: full[0])
            proc.arguments = Array(full.dropFirst())
        } else {
            let bin = dir.appendingPathComponent("venv/bin/\(argv[0])")
            proc.executableURL = bin
            proc.arguments = Array(argv.dropFirst())
        }
        proc.currentDirectoryURL = cwd
        var penv = ProcessInfo.processInfo.environment
        env.forEach { penv[$0.key] = $0.value }
        proc.environment = penv

        let logURL = dir.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            logHandle?.write(data)
            if let line = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline).last {
                Task { @MainActor in self?.recordOutput(String(line), for: spec.id) }
            }
        }
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.serverModelID == spec.id else { return }
                self.server = nil
                self.serverModelID = nil
                if self.status(of: spec.id) == .running || self.status(of: spec.id) == .starting {
                    self.setState(spec.id, .failed("Model server stopped before it was ready."))
                }
            }
        }

        do {
            try proc.run()
            server = proc
            serverModelID = spec.id
            let ok = await waitForHealth(port: spec.defaultPort, timeout: 600)
            guard server === proc else { return }
            if ok {
                let client = JevClient(endpoint: JevEndpoint(url: resolved.endpointURL,
                                                            model: resolved.serveModel), timeout: 600)
                let began = ContinuousClock.now
                _ = try await client.evaluate(
                    state: .string("A sample address is ready to paste into an Email field."),
                    questions: ["ready": .choice(instructions: "Which field receives an email address?",
                                                  criteria: ["email": "Email", "phone": "Phone"])])
                guard server === proc else { return }
                let elapsed = began.duration(to: .now).components
                warmupMilliseconds[spec.id] = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
                transfers[spec.id] = nil
                setState(spec.id, .running)
            } else if server != nil {
                setState(spec.id, .failed("Model server did not respond in time."))
                stop()
            }
        } catch {
            guard server == nil || server === proc else { return }
            stop()
            setState(spec.id, .failed(error.localizedDescription))
        }
    }

    public func stop() {
        server?.terminate()
        if let id = serverModelID, status(of: id) == .running || status(of: id) == .starting {
            setState(id, manifestExists(id) ? .installed : .notInstalled)
        }
        server = nil
        serverModelID = nil
    }

    public func uninstall(_ spec: ModelSpec) {
        if serverModelID == spec.id { stop() }
        try? FileManager.default.removeItem(at: modelDir(spec.id))
        setState(spec.id, .notInstalled)
        logTail[spec.id] = nil
    }

    // MARK: - Internals

    private func setState(_ id: String, _ s: State) { states[id] = s }

    private var supportDir: URL {
        ClipStore.defaultFileURL.deletingLastPathComponent()
    }
    private func modelDir(_ id: String) -> URL {
        supportDir.appendingPathComponent("models/\(id)", isDirectory: true)
    }
    private func manifestExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: modelDir(id).appendingPathComponent("manifest.json").path)
    }

    /// The variant actually installed on disk — differs from the selection
    /// when the user picks new weights after installing.
    public func installedVariant(of modelID: String) -> String? {
        let url = modelDir(modelID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return obj["variant"]
    }
    private func writeManifest(_ r: ModelSpec.Resolved) throws {
        let dir = modelDir(r.spec.id)
        let json: [String: String] = ["model": r.spec.id, "variant": r.variant.id]
        try JSONSerialization.data(withJSONObject: json)
            .write(to: dir.appendingPathComponent("manifest.json"))
    }

    /// uv argv prefix — absolute path when known, `/usr/bin/env uv` otherwise
    /// (Process won't do PATH lookups on its own).
    private func uvArgv(_ args: [String]) -> [String] {
        if let uvPath { return [uvPath] + args }
        return ["/usr/bin/env", "uv"] + args
    }

    /// {port} and {weights} substitution + shim path resolution.
    private func serveArgv(_ r: ModelSpec.Resolved) -> [String] {
        let sub = { (s: String) in
            s.replacing("{port}", with: "\(r.spec.defaultPort)")
             .replacing("{weights}", with: r.variant.hfRepo)
             .replacing("{serveModel}", with: r.variant.serveModel)
             .replacing("{snapshot}", with: self.modelDir(r.spec.id).appendingPathComponent("snapshot").path)
        }
        switch r.spec.kind {
        case .venv(_, let argv): return argv.map(sub)
        case .repo(_, _, _, let argv, _): return argv.map(sub)
        case .shim(_, let script, _):
            return ["python", Self.shimPath(script), "{port}", "{weights}", "{serveModel}", "{snapshot}"].map(sub)
        }
    }
    private func serveEnv(_ spec: ModelSpec) -> [String: String] {
        if case .repo(_, _, _, _, let env) = spec.kind { return env }
        return [:]
    }

    /// A bundled shim: inside a .app it lives in Resources; during
    /// development it lives in Scripts/ next to Package.swift.
    static func shimPath(_ script: String) -> String {
        let name = (script as NSString).deletingPathExtension
        if let p = Bundle.main.path(forResource: name, ofType: "py") { return p }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/\(script)")
        return dev.path
    }

    /// One-shot: does *anything* HTTP answer on this port? Any response
    /// (even 404) means a server is bound; only a refused/failed connect
    /// means the port is free. Lets `start` adopt a live endpoint.
    private func portAnswers(_ port: Int) async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 0.8
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<500).contains(http.statusCode)
    }

    private func waitForHealth(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        while Date() < deadline {
            if server == nil { return false }
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                return true
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return false
    }

    // MARK: - uv bootstrap

    private static func findUV() -> String? {
        let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv",
                          NSHomeDirectory() + "/.local/bin/uv",
                          NSHomeDirectory() + "/.cargo/bin/uv"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func ensureUV() async throws {
        if uvPath == nil { uvPath = Self.findUV() }
        if uvPath != nil { return }
        uvBootstrapping = true
        defer { uvBootstrapping = false }
        // Prefer brew when present; fall back to the official installer.
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            _ = try? await run(["/opt/homebrew/bin/brew", "install", "uv"], cwd: nil)
            uvPath = Self.findUV()
        }
        if uvPath == nil {
            _ = try await run(["/bin/sh", "-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"], cwd: nil)
            uvPath = Self.findUV()
        }
        guard uvPath != nil else {
            throw NSError(domain: "Cue.Models", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "uv install failed — install it manually (brew install uv) and retry"])
        }
        // uv manages its own Python — fetch 3.12 so venv creation can't fail
        // on a missing system interpreter.
        _ = try? await run(uvArgv(["python", "install", "3.12"]), cwd: nil)
    }

    private func runStep(_ id: String, _ phase: String, _ argv: [String], cwd: URL) async throws {
        setState(id, .installing(phase))
        transfers[id] = nil
        logTail[id] = argv.joined(separator: " ")
        try await run(argv, cwd: cwd) { [weak self] line in
            Task { @MainActor in self?.recordOutput(line, for: id) }
        }
    }

    private func recordOutput(_ line: String, for id: String) {
        logTail[id] = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let progress = ModelTransferProgress.parse(line) { transfers[id] = progress }
    }

    @discardableResult
    private func run(_ argv: [String], cwd: URL?,
                     onLine: (@Sendable (String) -> Void)? = nil) async throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: argv[0])
        proc.arguments = Array(argv.dropFirst())
        proc.currentDirectoryURL = cwd
        let pipe = Pipe()
        // Always drain: an unread pipe fills its 64KB buffer and deadlocks
        // verbose commands like `uv sync`.
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard let onLine else { return }
            String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline)
                .last.map { onLine(String($0).trimmingCharacters(in: .whitespaces)) }
        }
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        return try await withCheckedThrowingContinuation { cont in
            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 { cont.resume(returning: 0) }
                else {
                    cont.resume(throwing: NSError(
                        domain: "Cue.Models", code: Int(p.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "\(argv[0]) exited \(p.terminationStatus)"]))
                }
            }
        }
    }
}

public struct ModelTransferProgress: Equatable, Sendable {
    public var fraction: Double

    static func parse(_ line: String) -> Self? {
        guard let match = line.range(of: #"\b\d{1,3}%\|"#, options: .regularExpression),
              let percent = Double(line[match].dropLast(2)), (0...100).contains(percent)
        else { return nil }
        return Self(fraction: percent / 100)
    }
}

extension ModelSpec {
    var isRepo: Bool { if case .repo = kind { return true }; return false }
    var syncExtras: [String] {
        if case .repo(_, let extras, _, _, _) = kind { return extras }
        return []
    }
    var downloadsSnapshot: Bool {
        if case .shim(_, _, let snapshot) = kind { return snapshot }
        return false
    }
}
