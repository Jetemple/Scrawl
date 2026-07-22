import AppKit

/// Scrawl's icon, loaded from the bundled AboutAppIcon.png (derived from
/// Config/AppIcon.png). Prefer this over NSApp.applicationIconImage: outside a
/// signed .app bundle (swift run, tests) the process icon is the generic
/// executable glyph, which shows up as a blank page/folder in alerts.
enum ScrawlBrandIcon {
    static func image() -> NSImage {
        if let url = resourceBundle?.url(forResource: "AboutAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    /// Locates AppUI's SwiftPM resource bundle without touching `Bundle.module`,
    /// whose generated accessor calls `fatalError` when the bundle is missing. A
    /// `make install` .app ships only the executable, so `Bundle.module` traps
    /// there; returning nil instead lets image() fall back to the app's own icon,
    /// which inside a signed .app is already the real Scrawl icon.
    private static let resourceBundle: Bundle? = {
        let bundleName = "Scrawl_AppUI.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleToken.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for case let base? in candidates {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return nil
    }()

    private final class BundleToken {}
}
