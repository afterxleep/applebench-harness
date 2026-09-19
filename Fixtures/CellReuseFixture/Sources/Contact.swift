import Foundation

struct Contact: Hashable {
    let id: Int
    let name: String
}

enum ContactDirectory {
    static let all: [Contact] = (1...200).map {
        Contact(id: $0, name: "Contact \($0)")
    }
}
