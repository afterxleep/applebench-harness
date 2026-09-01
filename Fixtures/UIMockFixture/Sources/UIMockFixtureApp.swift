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

            Text("Enjoys differential equations, looms, and long walks through the Analytical Engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("bio")

            Text("Ada Lovelace")
                .font(.footnote)
                .accessibilityIdentifier("name")
        }
        .padding(24)
        .navigationTitle("profile card")
    }
}
