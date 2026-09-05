import Foundation

/// Which simulators a run currently owns, visible across processes.
///
/// The reaper deletes every benchmark device except the caller's own, which is
/// right when the leftovers are stranded and wrong the moment two runs share a
/// machine: the second run loses its device mid-grade and the failure is
/// recorded against its model. A claim is a file named for the UDID, so a
/// separate process can see it without either run knowing about the other.
public enum SimulatorClaims {
    /// A claim older than this is treated as abandoned. Longer than any task's
    /// wall clock, so an in-flight run is never mistaken for a dead one, and
    /// short enough that a killed run's device is still cleaned up soon after.
    public static let maxAge: TimeInterval = 2 * 60 * 60

    static func directory(in runsRoot: URL) -> URL {
        runsRoot.appendingPathComponent(".claimed-simulators", isDirectory: true)
    }

    /// Records that a run is using `udid`. Best effort: a claim that cannot be
    /// written costs cleanup safety, never the run itself.
    public static func claim(_ udid: String, in runsRoot: URL) {
        let directory = directory(in: runsRoot)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: directory.appendingPathComponent(udid))
    }

    public static func release(_ udid: String, in runsRoot: URL) {
        try? FileManager.default.removeItem(at: directory(in: runsRoot).appendingPathComponent(udid))
    }

    /// Every device another run still holds.
    public static func active(in runsRoot: URL, now: Date = Date()) -> Set<String> {
        let directory = directory(in: runsRoot)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var live: Set<String> = []
        for url in contents {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) < maxAge {
                live.insert(url.lastPathComponent)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return live
    }
}
