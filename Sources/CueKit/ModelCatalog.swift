import Foundation

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
        decider, s1lite, jevk5lite, kenning, truetype,
    ])

    /// The role holders (Recommended first) are the picker's top-level rows; everything else is "Others".
    public static var featured: [ModelSpec] {
        ModelRoles.roles(from: ModelRoles.benchmarks).compactMap { model($0.bench.model) }
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

}
