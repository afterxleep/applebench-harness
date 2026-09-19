import UIKit

@MainActor
protocol AvatarLoading {
    func loadAvatar(for contactID: Int, completion: @escaping (UIImage?) -> Void)
}

/// Generates avatar images asynchronously, simulating a slow network fetch.
/// Completion order is not guaranteed to match request order.
@MainActor
final class AvatarLoader: AvatarLoading {
    func loadAvatar(for contactID: Int, completion: @escaping (UIImage?) -> Void) {
        // Simulated variable latency: earlier requests can finish after
        // later ones, exactly like a real image pipeline.
        let delay = Double((contactID * 37) % 100) / 100.0 + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion(Self.renderAvatar(for: contactID))
        }
    }

    private static func renderAvatar(for contactID: Int) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let hue = CGFloat((contactID * 47) % 360) / 360.0
            UIColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
