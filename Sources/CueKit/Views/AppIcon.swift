import AppKit
import SwiftUI

/// The clip's source-app icon, resolved from its recorded bundle ID.
/// Cached process-wide — NSWorkspace.icon hits disk otherwise.
struct SourceAppIcon: View {
    let clip: Clip
    var size: CGFloat = 18

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        if let image = Self.image(for: clip.sourceBundleID) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    static func image(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
