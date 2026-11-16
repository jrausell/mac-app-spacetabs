import Foundation

/// Finder can supply directory URLs with different directory hints/trailing
/// slashes. Compare canonical path components, not NSURL representation equality.
public enum DesktopMenuScope {
    public static func matches(_ target: URL?, desktop: URL) -> Bool {
        guard let target, target.isFileURL, desktop.isFileURL else { return false }
        return target.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            == desktop.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}
