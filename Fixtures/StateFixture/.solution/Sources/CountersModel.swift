import Foundation

/// A counter the user can increment. The state is shared across
/// three screens and must round-trip cleanly through navigation.
final class CountersModel: ObservableObject {
    @Published var value: Int = 0

    func increment() {
        value += 1
    }
}
