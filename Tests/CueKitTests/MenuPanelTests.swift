import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CueKit

@MainActor
struct MenuPanelTests {
    @Test func secretsAreMaskedAndTypedClipsKeepTheirLook() {
        let key = Clip(text: "sk-live-4f9a8b2c7d1e6f3a9b8c7d6e5f4a3b2c", kind: .text)
        #expect(ClipLook.of(key) == .secret)
        #expect(ClipLook.masked(key.text).hasSuffix("••••••••3b2c"))
        #expect(!ClipLook.masked(key.text).contains("7d1e6f3a"))
        #expect(ClipLook.of(Clip(text: "1Z999AA10123456784", kind: .text)) == .code)
        #expect(ClipLook.of(Clip(text: "a3f9c2e81b7d", kind: .text)) == .code)
        #expect(ClipLook.of(Clip(text: "#2F5BEA", kind: .text)) == .color)
        #expect(ClipLook.of(Clip(text: "func f() {\n    g()\n}", kind: .text)) == .snippet)
        #expect(ClipLook.of(Clip(text: "Milk\nEggs", kind: .text)) == .multiline)
        #expect(ClipLook.of(Clip(text: "priya.raman@northwind.co", kind: .text)) == .email)
    }

    @Test func sectionsFollowCalendarDays() {
        let now = Date()
        let cal = Calendar.current
        let clips = [Clip(text: "a", kind: .text, copiedAt: now),
                     Clip(text: "b", kind: .text, copiedAt: cal.date(byAdding: .day, value: -1, to: now)!),
                     Clip(text: "c", kind: .text, copiedAt: cal.date(byAdding: .day, value: -5, to: now)!),
                     Clip(text: "d", kind: .text, copiedAt: now, pinned: true)]
        #expect(MenuPanel.sections(clips, now: now).map(\.title) == ["Pinned", "Today", "Yesterday", "Earlier"])
    }

    /// `PANEL_SHOT=<dir> swift test --filter MenuPanelTests/render` writes the panel and a preview, light and dark,
    /// rendered off-screen from `PANEL_CLIPS` (a history.json), so the panel can be judged without running Cue.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANEL_SHOT"] != nil))
    func render() throws {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["PANEL_SHOT"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clips: [Clip] = try env["PANEL_CLIPS"].map {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .secondsSince1970
            return try d.decode([Clip].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        } ?? []
        let actions = MenuPanelActions(paste: { _ in }, togglePin: { _ in }, remove: { _ in },
                                       openHistory: {}, openSettings: {})
        _ = NSApplication.shared
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let panel = MenuPanel(status: .init(.ready, "Ready"), detail: nil, clips: clips,
                                  mode: .constant(.smart), paused: .constant(false), actions: actions)
            try snapshot(panel, material: .menu, appearance: appearance, to: dir.appendingPathComponent("panel-\(name).png"))
            for clip in clips.prefix(8) where [.snippet, .color, .secret].contains(ClipLook.of(clip)) {
                try snapshot(ClipPreview(clip: clip), material: .popover, appearance: appearance,
                             to: dir.appendingPathComponent("preview-\(ClipLook.of(clip))-\(name).png"))
            }
        }
    }

    /// `PANEL_SHOT=<dir> swift test --filter MenuPanelTests/renderWindows` draws History and every Settings tab.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANEL_SHOT"] != nil))
    func renderWindows() throws {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["PANEL_SHOT"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clips: [Clip] = try env["PANEL_CLIPS"].map {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .secondsSince1970
            return try d.decode([Clip].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        } ?? []
        let actions = MenuPanelActions(paste: { _ in }, togglePin: { _ in }, remove: { _ in },
                                       openHistory: {}, openSettings: {})
        _ = NSApplication.shared
        let model = AppModel(live: false)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try snapshot(HistoryPanel(clips: clips, queued: nil, smartPasteKeys: "⌘V", actions: actions)
                            .frame(width: 760, height: 500),
                         material: .windowBackground, appearance: appearance,
                         to: dir.appendingPathComponent("history-\(name).png"))
            for tab in SettingsTab.allCases {
                try snapshot(SettingsView(model: model, tab: tab), material: .windowBackground, appearance: appearance,
                             to: dir.appendingPathComponent("settings-\(tab.rawValue.lowercased())-\(name).png"))
            }
        }
    }

    private func snapshot(_ view: some View, material: NSVisualEffectView.Material, appearance: NSAppearance.Name,
                          to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let backdrop = NSVisualEffectView(frame: host.frame)
        backdrop.material = material
        backdrop.state = .active
        backdrop.addSubview(host)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: host.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        window.contentView = backdrop
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

