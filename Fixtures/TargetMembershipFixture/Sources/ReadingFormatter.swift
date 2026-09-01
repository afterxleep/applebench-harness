import Foundation

/// Renders sensor readings for display.
enum ReadingFormatter {
    static func format(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        return measurement.formatted(.measurement(width: .abbreviated))
    }
}
