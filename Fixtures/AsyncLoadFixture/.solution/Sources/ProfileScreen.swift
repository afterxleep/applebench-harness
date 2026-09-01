import SwiftUI

struct ProfileScreen: View {
    @State private var loader = ProfileLoader()

    var body: some View {
        VStack(spacing: 12) {
            if let profile = loader.profile {
                Text(profile.name)
                    .font(.title2)
                    .accessibilityIdentifier("name")

                Text(profile.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("role")

                Text("\(profile.followers) followers")
                    .font(.footnote)
                    .accessibilityIdentifier("followers")
            } else {
                ProgressView()
                    .accessibilityIdentifier("loading")
            }
        }
        .padding()
        .navigationTitle("Profile")
        .task {
            await loader.load()
        }
    }
}
