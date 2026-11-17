import SwiftUI
import UIKit

@main
struct CellReuseFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            ContactsScreen()
                .ignoresSafeArea()
        }
    }
}

struct ContactsScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: ContactsViewController())
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

final class ContactsViewController: UITableViewController {
    private let loader = AvatarLoader()
    private let contacts = ContactDirectory.all

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Contacts"
        tableView.register(ContactCell.self, forCellReuseIdentifier: ContactCell.reuseIdentifier)
        tableView.rowHeight = 56
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ContactCell.reuseIdentifier,
            for: indexPath
        ) as! ContactCell
        cell.configure(with: contacts[indexPath.row], loader: loader)
        return cell
    }
}
