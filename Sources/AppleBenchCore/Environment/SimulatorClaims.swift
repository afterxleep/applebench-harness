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

    /// Claims every run on this machine can see, whatever runs directory it
    /// writes to.
    ///
    /// Claims used to live only beside a run's own results. A fixture
    /// verification writing to a temporary runs directory could not see a
    /// benchmark's claims, reaped its simulator mid-grading, and the
    /// benchmark recorded failures for a device that no longer existed.
    static var sharedDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-claimed-simulators", isDirectory: true)
    }

    /// Records that a run is using `udid`. Best effort: a claim that cannot be
    /// written costs cleanup safety, never the run itself.
    public static func claim(_ udid: String, in runsRoot: URL) {
        for directory in [directory(in: runsRoot), sharedDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data().write(to: directory.appendingPathComponent(udid))
        }
    }

    public static func release(_ udid: String, in runsRoot: URL) {
        for directory in [directory(in: runsRoot), sharedDirectory] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(udid))
        }
    }

    /// Every device another run still holds, on this machine.
    public static func active(in runsRoot: URL, now: Date = Date()) -> Set<String> {
        live(in: directory(in: runsRoot), now: now).union(live(in: sharedDirectory, now: now))
    }

    private static func live(in directory: URL, now: Date) -> Set<String> {
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
