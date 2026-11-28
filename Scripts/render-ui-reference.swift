// Renders the CORRECT profile card design to
// Fixtures/UIMockFixture/Design/expected-ui.png at iPhone-ish size.
// Maintainer tool: run with `swift Scripts/render-ui-reference.swift`.
import AppKit
import SwiftUI

struct CorrectProfileCard: View {
    var body: some View {
        VStack(spacing: 0) {
            // Simulated navigation bar with the correct title.
            Text("Profile")
                .font(.system(size: 34, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.blue)
                    .clipShape(Circle())

                Text("Ada Lovelace")
                    .font(.headline)

                Text("Enjoys differential equations, looms, and long walks through the Analytical Engine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Follow") {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)

            Spacer()
        }
        .frame(width: 393, height: 700)
        .background(Color(white: 0.98))
    }
}

@MainActor
func render() throws {
    let renderer = ImageRenderer(content: CorrectProfileCard())
    renderer.scale = 2
    guard let cgImage = renderer.cgImage else {
        fatalError("Rendering failed")
    }
    let outputURL = URL(fileURLWithPath: "Fixtures/UIMockFixture/Design/expected-ui.png")
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}

// Top-level script code runs on the main thread.
try MainActor.assumeIsolated {
    try render()
}
