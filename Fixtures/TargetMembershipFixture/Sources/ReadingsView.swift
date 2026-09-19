import SwiftUI

struct ReadingsView: View {
    private let readings: [Double] = [18.5, 21.0, 24.25]

    var body: some View {
        List(readings, id: \.self) { reading in
            Text(ReadingFormatter.format(reading))
        }
        .navigationTitle("Readings")
    }
}
