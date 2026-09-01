import UIKit
import XCTest

/// Benchmark verification: a reused cell must never display the avatar of the
/// contact it previously represented, no matter how loads interleave.
@MainActor
final class ContactCellTests: XCTestCase {
    private let alice = Contact(id: 1, name: "Alice")
    private let bob = Contact(id: 2, name: "Bob")

    func testStaleAvatarForPreviousContactIsDiscarded() {
        let loader = FakeAvatarLoader()
        let cell = ContactCell(style: .default, reuseIdentifier: ContactCell.reuseIdentifier)

        // Row shows Alice; her avatar is still loading when the cell is
        // reused for Bob (fast scroll).
        cell.configure(with: alice, loader: loader)
        cell.prepareForReuse()
        cell.configure(with: bob, loader: loader)

        // Alice's slow load finishes after the reuse.
        let aliceAvatar = UIImage(systemName: "a.circle")!
        let bobAvatar = UIImage(systemName: "b.circle")!
        loader.complete(contactID: alice.id, with: aliceAvatar)
        XCTAssertNotIdentical(
            cell.avatarImage, aliceAvatar,
            "A reused cell must drop avatar loads that belong to the previous contact"
        )

        loader.complete(contactID: bob.id, with: bobAvatar)
        XCTAssertIdentical(cell.avatarImage, bobAvatar, "The current contact's avatar must display")
    }

    func testPrepareForReuseClearsPreviousAvatar() {
        let loader = FakeAvatarLoader()
        let cell = ContactCell(style: .default, reuseIdentifier: ContactCell.reuseIdentifier)

        cell.configure(with: alice, loader: loader)
        loader.complete(contactID: alice.id, with: UIImage(systemName: "a.circle")!)
        XCTAssertNotNil(cell.avatarImage)

        cell.prepareForReuse()
        XCTAssertNil(cell.avatarImage, "Reused cells must not briefly show the previous avatar")
    }
}

/// Deterministic stand-in for the avatar pipeline: completions fire only when
/// the test says so, letting tests interleave loads exactly.
@MainActor
private final class FakeAvatarLoader: AvatarLoading {
    private var pending: [(contactID: Int, completion: (UIImage?) -> Void)] = []

    func loadAvatar(for contactID: Int, completion: @escaping (UIImage?) -> Void) {
        pending.append((contactID, completion))
    }

    func complete(contactID: Int, with image: UIImage) {
        for entry in pending where entry.contactID == contactID {
            entry.completion(image)
        }
        pending.removeAll { $0.contactID == contactID }
    }
}
