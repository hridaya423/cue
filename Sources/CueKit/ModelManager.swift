import Foundation

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
                let elapsed = began.duration(to: .now)
                warmupMilliseconds[spec.id] = Int(elapsed.milliseconds)
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
