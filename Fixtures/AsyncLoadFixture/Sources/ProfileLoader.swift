import Foundation

struct Profile: Sendable, Equatable {
    var name: String
    var role: String
    var followers: Int
}

/// Loads the signed-in user's profile from the (simulated) account service.
@MainActor
@Observable
final class ProfileLoader {
    private(set) var profile: Profile?

    func load() async {
        try? await Task.sleep(for: .milliseconds(600))
        profile = Profile(name: "Ada Lovelace", role: "Analyst", followers: 1843)
    }
}
