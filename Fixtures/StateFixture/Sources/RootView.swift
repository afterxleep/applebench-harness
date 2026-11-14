import SwiftUI

struct RootView: View {
    @StateObject private var model = CountersModel()

    var body: some View {
        NavigationStack {
            CounterView(model: model)
        }
    }
}

struct CounterView: View {
    @ObservedObject var model: CountersModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(model.value)")
                .font(.largeTitle)
            Button("Increment") {
                model.increment()
            }
            .accessibilityIdentifier("increment")
            NavigationLink("Detail") {
                DetailView(model: model)
            }
            .accessibilityIdentifier("goDetail")
        }
    }
}

struct DetailView: View {
    @ObservedObject var model: CountersModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(model.value)")
                .font(.largeTitle)
            Button("+5") {
                for _ in 0..<5 { model.increment() }
            }
            .accessibilityIdentifier("plusFive")
        }
        .navigationTitle("Detail")
    }
}
