import SwiftUI
import UIKit

struct BadgeView: View {
    private var badge: UIImage? { UIImage(named: "loom-badge") }

    var body: some View {
        VStack(spacing: 16) {
            if let badge {
                Image(uiImage: badge)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityIdentifier("badge")
            } else {
                Color.clear
                    .frame(width: 96, height: 96)
            }

            Text(badge == nil ? "Badge missing" : "Badge loaded")
                .accessibilityIdentifier("badge-status")
        }
        .padding()
        .navigationTitle("Certification")
    }
}
