import Foundation

/// Lightweight in-app analytics recorder.
///
/// Isolated to the main actor so its mutable state has a single, statically
/// known execution context under Swift 6 strict concurrency.
@MainActor
final class Analytics {
    static let shared = Analytics()

    private(set) var events: [String] = []

    func track(_ name: String) {
        events.append(name)
    }
}
