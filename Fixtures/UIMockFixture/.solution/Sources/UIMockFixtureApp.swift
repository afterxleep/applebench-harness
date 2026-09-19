import SwiftUI

@main
struct UIMockFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ProfileCardView()
            }
        }
    }
}

/// The profile card screen. Design reference: Design/expected-ui.png.
struct ProfileCardView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .frame(width: 96, height: 96)
                .foregroundStyle(.gray)
                .accessibilityIdentifier("avatar")

            Text("Ada Lovelace")
                .font(.title2)
                .accessibilityIdentifier("name")

            Text("Enjoys differential equations, looms, and long walks through the Analytical Engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("bio")

            Button("Follow") {}
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("follow")
        }
        .padding(24)
        .navigationTitle("Profile")
    }
}
