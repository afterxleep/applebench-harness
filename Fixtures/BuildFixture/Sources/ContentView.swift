import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.largeTitle)
            Text("BuildFixture")
                .font(.title2)
        }
        .padding()
        .onAppear {
            Analytics.shared.track("content_appeared")
        }
    }
}
