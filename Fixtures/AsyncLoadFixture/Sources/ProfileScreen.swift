import SwiftUI

struct ProfileScreen: View {
    @State private var loader = ProfileLoader()

    var body: some View {
        VStack(spacing: 12) {
            Text(loader.profile!.name)
                .font(.title2)
                .accessibilityIdentifier("name")

            Text(loader.profile!.role)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("role")

            Text("\(loader.profile!.followers) followers")
                .font(.footnote)
                .accessibilityIdentifier("followers")
        }
        .padding()
        .navigationTitle("Profile")
        .task {
            await loader.load()
        }
    }
}
