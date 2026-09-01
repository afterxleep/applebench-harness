import SwiftUI

/// The library screen. The subtitle under the navigation title was added in
/// the last sprint to show how many items are loaded.
struct LibraryView: View {
    private let items = ["Notes", "Drafts", "Archive"]

    var body: some View {
        List(items, id: \.self) { item in
            Text(item)
        }
        .navigationTitle("Library")
        .toolbar {
            // The subtitle placement only exists on iOS 26 and newer; on
            // older systems the screen simply shows the title alone.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .subtitle) {
                    Text("\(items.count) collections")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") {}
            }
        }
    }
}
