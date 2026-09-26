import Foundation

// MARK: - Catalog

/// One downloadable weight set for a model family.
public struct WeightSpec: Sendable, Equatable, Identifiable {
    public var id: String
    public var paramsLabel: String   // "4B"
    public var diskLabel: String     // "~9 GB"
    public var ramLabel: String      // "~10 GB"
    public var recommended = false
    /// Meter bars in the picker, 0…1. Editorial estimates — replace with
    /// eval_systemone.py numbers when we have real benchmark data.
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
    /// what kev/laya/von are; "Best balance" is what they can choose on.
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
        /// `uv venv` + `uv pip install <pkgs>`; serve = our bundled shim script.
        case shim(packages: [String])
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
    /// recommended badge; kev/laya also get top-level rows in the picker.
    public static let all: [ModelSpec] = [kev, laya, von, jevons, jevlite, decider]

    /// kev and laya are top-level picker rows; everything else is "Others".
    public static var others: [ModelSpec] {
        all.filter { $0.id != "kev" && $0.id != "laya" }.sorted { $0.rank < $1.rank }
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
        blurb: "Fewest wrong pastes in Cue’s benchmark (1%), about 250 ms per decision.",
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
        ])

    public static let laya = ModelSpec(
        id: "laya", title: "Laya", rank: 2, reason: "Best balance", defaultPort: 8765,
        blurb: "Under 1 GB, about 300 ms per decision, and rarely wrong (3% in Cue’s benchmark).",
        kind: .shim(packages: ["laya"]),
        support: .supported,
        variants: [
            WeightSpec(id: "laya-en", paramsLabel: "421M", diskLabel: "~900 MB", ramLabel: "~1 GB",
                       recommended: true, accuracy: 0.8, speed: 0.8,
                       serveModel: "laya", hfRepo: "convaiinnovations/laya"),
            WeightSpec(id: "laya-multi", paramsLabel: "322M", diskLabel: "~700 MB", ramLabel: "~1 GB",
                       accuracy: 0.6, speed: 0.95,
                       serveModel: "multilingual", hfRepo: "convaiinnovations/laya-multilingual"),
            WeightSpec(id: "laya-typed", paramsLabel: "421M", diskLabel: "~900 MB", ramLabel: "~1 GB",
                       accuracy: 0.7, speed: 0.9,
                       serveModel: "typed-decisions", hfRepo: "convaiinnovations/laya-typed-decisions"),
        ])

    public static let von = ModelSpec(
        id: "von", title: "Von", rank: 3, reason: "Fastest", defaultPort: 8766,
        blurb: "Quickest decisions, about 215 ms. Finds the most, but pastes the wrong thing more often (10%).",
        kind: .venv(packages: ["von-sdk"],
                    serveArgv: ["von", "serve", "--host", "127.0.0.1", "--port", "{port}"]),
        support: .supported,
        variants: [
            WeightSpec(id: "von-1.0", paramsLabel: "395M", diskLabel: "~1.5 GB", ramLabel: "~2 GB",
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

    /// flash-linear-attention is a hard dep and Triton has no macOS wheels —
    /// listed so the catalog is complete, but not installable here.
    public static let decider = ModelSpec(
        id: "decider", title: "Decider", rank: 6, reason: "Largest local", defaultPort: 8769,
        blurb: "1.9B Qwen3.5 full fine-tune, one-pass typed decisions.",
        kind: .venv(packages: ["decider @ git+https://github.com/Mapika/decider"],
                    serveArgv: ["python", "-m", "decider.serve", "--port", "{port}"]),
        support: .unsupported("needs NVIDIA/Triton kernels"),
        variants: [
            WeightSpec(id: "decider-2b", paramsLabel: "1.9B", diskLabel: "~4 GB", ramLabel: "~5 GB",
                       accuracy: 0.8, speed: 0.4,
                       serveModel: "decider-2b", hfRepo: "Mapika/decider-2b"),
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
            case .venv(let packages, _), .shim(let packages):
                try await runStep(spec.id, "creating venv",
                                  uvArgv(["venv", dir.appendingPathComponent("venv").path, "--python", "3.12"]), cwd: dir)
                let py = dir.appendingPathComponent("venv/bin/python").path
                try await runStep(spec.id, "installing packages",
                                  uvArgv(["pip", "install", "--python", py] + packages), cwd: dir)
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
        if serverModelID == spec.id, server?.isRunning == true {
            switch status(of: spec.id) {
            case .running, .starting: return
            default: break
            }
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
        }
        switch r.spec.kind {
        case .venv(_, let argv): return argv.map(sub)
        case .repo(_, _, _, let argv, _): return argv.map(sub)
        case .shim:
            return ["python", Self.shimPath, "{port}"].map(sub)
        }
    }
    private func serveEnv(_ spec: ModelSpec) -> [String: String] {
        if case .repo(_, _, _, _, let env) = spec.kind { return env }
        return [:]
    }

    /// The bundled shim: inside a .app it lives in Resources; during
    /// development it lives in Scripts/ next to Package.swift.
    static var shimPath: String {
        if let p = Bundle.main.path(forResource: "laya_server", ofType: "py") { return p }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/laya_server.py")
        return dev.path
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
}
