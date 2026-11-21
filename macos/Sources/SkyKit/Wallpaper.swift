import AppKit
import Foundation

/// The desktop picture, and the files skybg gives it.
public enum Wallpaper {
    public static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// The largest display, in pixels.
    public static func screenSize() -> (width: Int, height: Int) {
        let sizes = NSScreen.screens.map { screen in
            (Int((screen.frame.width * screen.backingScaleFactor).rounded()),
             Int((screen.frame.height * screen.backingScaleFactor).rounded()))
        }
        return sizes.max(by: { $0.0 * $0.1 < $1.0 * $1.1 }) ?? (2560, 1600)
    }

    /// The picture each display shows in the current Space.
    public static func current() -> [URL] {
        NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.resolvingSymlinksInPath() }
    }

    /// Show `url` on every display, in the current Space.
    public static func set(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
    }

    /// Whether the main display's picture is one of skybg's renders.
    public static var isOurs: Bool {
        guard let shown = current().first else { return false }
        return shown.path.hasPrefix(Settings.stateDirectory.resolvingSymlinksInPath().path + "/")
    }

    /// Real paths of every image the macOS wallpaper store records, for any
    /// Space or display, current or long gone. Each choice is a nested
    /// binary plist; an unreadable store records nothing.
    public static func storePaths(in store: URL = store) -> Set<String> {
        var found = Set<String>()
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            } else if let data = value as? Data, data.starts(with: Array("bplist".utf8)) {
                // A corrupt blob is skipped, and the rest kept.
                if let nested = try? PropertyListSerialization.propertyList(from: data, format: nil) { walk(nested) }
            } else if let string = value as? String, string.hasPrefix("file://"), let url = URL(string: string) {
                found.insert(url.resolvingSymlinksInPath().path)
            }
        }
        if let data = try? Data(contentsOf: store),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            walk(plist)
        }
        return found
    }

    /// The renders on disk, newest first.
    static func renders(in directory: URL = Settings.stateDirectory) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("sky-") && $0.pathExtension == "png" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0.resolvingSymlinksInPath() }
    }

    /// Real paths of renders that must not be overwritten yet: the image
    /// each Space and display was last given, and the last two renders. The
    /// desktop may not have reached the latest yet, and macOS keeps the one
    /// before it loaded for a few seconds after it is replaced, bringing
    /// that image back if its path is set again meanwhile.
    static func rendersInUse() -> Set<String> {
        storePaths().union(renders().prefix(2).map(\.path))
    }

    /// A name for the next render. The wallpaper agent reuses the image it
    /// decoded for a path while any Space still shows that path, so a render
    /// never takes the name of one in use. But the names come from a small
    /// pool, sky-0.png upward: macOS remembers every image file it is ever
    /// given and rechecks that whole list on every change, so a new name
    /// each time makes every change slower than the last.
    static func nextRender(in directory: URL = Settings.stateDirectory, avoiding inUse: Set<String>) -> URL {
        let directory = directory.resolvingSymlinksInPath()
        for k in 0... {
            let url = directory.appendingPathComponent("sky-\(k).png")
            if !inUse.contains(url.path) { return url }
        }
        fatalError("unreachable")
    }

    /// Delete renders other than `keep`.
    static func prune(in directory: URL = Settings.stateDirectory, keeping keep: Set<String>) {
        for url in renders(in: directory) where !keep.contains(url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
