import AppKit

/// Scrawl's icon, loaded from the bundled AboutAppIcon.png (derived from
/// Config/AppIcon.png). Prefer this over NSApp.applicationIconImage: outside a
/// signed .app bundle (swift run, tests) the process icon is the generic
/// executable glyph, which shows up as a blank page/folder in alerts.
enum ScrawlBrandIcon {
    static func image() -> NSImage {
        if let url = Bundle.module.url(forResource: "AboutAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}
