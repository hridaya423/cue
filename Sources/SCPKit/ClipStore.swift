import Foundation

/// Clipboard history: in-memory list backed by one JSON file.
/// Newest first. `queue` is a FIFO of clip ids used by queue mode.
@MainActor @Observable
public final class ClipStore {
    public private(set) var clips: [Clip] = []
    public private(set) var queue: [Clip] = []

    private let fileURL: URL
    private let capacity: () -> Int

    public init(fileURL: URL = ClipStore.defaultFileURL, capacity: @autoclosure @escaping () -> Int = 1000) {
        self.fileURL = fileURL
        self.capacity = capacity
        load()
    }

    public static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartCopyPaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    /// Insert a copied clip. Re-copying an existing clip moves it to the front.
    /// In queue mode the caller sets `queued` on the clip.
    public func add(_ clip: Clip) {
        if let i = clips.firstIndex(where: { $0.id == clip.id }) {
            var moved = clips.remove(at: i)
            moved.copiedAt = clip.copiedAt
            moved.queued = clip.queued || moved.queued
            clips.insert(moved, at: 0)
            if clip.queued, !queue.contains(where: { $0.id == clip.id }) {
                queue.append(moved)
            }
        } else {
            clips.insert(clip, at: 0)
            if clip.queued { queue.append(clip) }
        }
        evictIfNeeded()
        save()
    }

    /// Pop the front of the paste queue.
    @discardableResult
    public func popQueue() -> Clip? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    public func clearQueue() {
        for i in clips.indices { clips[i].queued = false }
        queue.removeAll()
        save()
    }

    public func togglePin(_ clip: Clip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].pinned.toggle()
        save()
    }

    public func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        queue.removeAll { $0.id == clip.id }
        save()
    }

    public func markPasted(_ clip: Clip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].timesPasted += 1
        if clips[i].queued {
            clips[i].queued = false
            queue.removeAll { $0.id == clip.id }
        }
        save()
    }

    public var latest: Clip? { clips.first }

    /// Candidates offered to the decision engine, newest first.
    public func candidates(limit: Int = 40) -> [Clip] {
        Array(clips.prefix(limit))
    }

    private func evictIfNeeded() {
        let cap = capacity()
        guard clips.count > cap else { return }
        let evictable = clips.enumerated()
            .filter { !$0.element.pinned }
            .sorted { $0.element.copiedAt < $1.element.copiedAt }
        let overflow = clips.count - cap
        let evictIDs = Set(evictable.prefix(overflow).map(\.element.id))
        clips.removeAll { evictIDs.contains($0.id) }
        queue.removeAll { evictIDs.contains($0.id) }
    }

    private func save() {
        do {
            let data = try JSONEncoder.clips.encode(clips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SmartCopyPaste: failed to save history: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var decoded = try? JSONDecoder.clips.decode([Clip].self, from: data)
        else { return }
        decoded.sort { $0.copiedAt > $1.copiedAt }
        clips = decoded
        queue = decoded.filter(\.queued)
    }
}

extension JSONEncoder {
    static let clips: JSONEncoder = {
        let e = JSONEncoder()
        // Raw timestamps, not ISO8601: fractional seconds preserve sub-second
        // copy ordering across save/load.
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.timeIntervalSince1970)
        }
        return e
    }()
}

extension JSONDecoder {
    static let clips: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try c.decode(Double.self))
        }
        return d
    }()
}
