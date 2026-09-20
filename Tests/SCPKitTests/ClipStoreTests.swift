import Foundation
import Testing
@testable import SCPKit

@MainActor
struct ClipStoreTests {
    private func makeStore(capacity: Int = 1000) -> ClipStore {
        ClipStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("scp-test-\(UUID().uuidString).json"),
            capacity: capacity)
    }

    @Test func addsNewestFirst() {
        let store = makeStore()
        store.add(Clip(text: "first", kind: .text))
        store.add(Clip(text: "second", kind: .text))
        #expect(store.clips.map(\.text) == ["second", "first"])
    }

    @Test func recopyMovesToFront() {
        let store = makeStore()
        store.add(Clip(text: "a", kind: .text))
        store.add(Clip(text: "b", kind: .text))
        store.add(Clip(text: "a", kind: .text))
        #expect(store.clips.map(\.text) == ["a", "b"])
        #expect(store.clips.count == 2)
    }

    @Test func capEvictsOldestUnpinned() {
        let store = makeStore(capacity: 3)
        var pinned = Clip(text: "keep me", kind: .text)
        pinned.pinned = true
        pinned.copiedAt = Date(timeIntervalSince1970: 0) // oldest but pinned
        store.add(pinned)
        for i in 0..<4 { store.add(Clip(text: "clip \(i)", kind: .text)) }
        #expect(store.clips.count == 3)
        #expect(store.clips.contains { $0.text == "keep me" })
        #expect(!store.clips.contains { $0.text == "clip 0" })
    }

    @Test func queueIsFIFO() {
        let store = makeStore()
        store.add(Clip(text: "q1", kind: .text, queued: true))
        store.add(Clip(text: "q2", kind: .text, queued: true))
        store.add(Clip(text: "plain", kind: .text))
        #expect(store.queue.map(\.text) == ["q1", "q2"])
        #expect(store.popQueue()?.text == "q1")
        #expect(store.popQueue()?.text == "q2")
        #expect(store.popQueue() == nil)
    }

    @Test func markPastedRemovesFromQueue() {
        let store = makeStore()
        let clip = Clip(text: "queued", kind: .text, queued: true)
        store.add(clip)
        store.markPasted(clip)
        #expect(store.queue.isEmpty)
        #expect(store.clips[0].timesPasted == 1)
    }

    @Test func persistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scp-test-\(UUID().uuidString).json")
        let store = ClipStore(fileURL: url, capacity: 100)
        store.add(Clip(text: "survives restart", kind: .url, sourceApp: "Safari"))

        let reloaded = ClipStore(fileURL: url, capacity: 100)
        #expect(reloaded.clips.count == 1)
        #expect(reloaded.clips[0].text == "survives restart")
        #expect(reloaded.clips[0].kind == .url)
        #expect(reloaded.clips[0].sourceApp == "Safari")
    }

    @Test func subSecondOrderSurvivesReload() {
        // Same-second copies must keep their order across save/load — this is
        // why the encoder writes raw timestamps, not ISO8601.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scp-test-\(UUID().uuidString).json")
        let store = ClipStore(fileURL: url, capacity: 100)
        let base = Date()
        store.add(Clip(text: "first", kind: .text, copiedAt: base))
        store.add(Clip(text: "second", kind: .text, copiedAt: base.addingTimeInterval(0.4)))

        let reloaded = ClipStore(fileURL: url, capacity: 100)
        #expect(reloaded.clips.map(\.text) == ["second", "first"])
    }

    @Test func classifiesURLs() {
        #expect(Clip.classify("https://example.com/path?q=1") == .url)
        #expect(Clip.classify("  https://example.com  ") == .url)
        #expect(Clip.classify("just text") == .text)
        #expect(Clip.classify("example.com no scheme") == .text)
        #expect(Clip.classify("ftp://x.com") == .text)
    }
}
