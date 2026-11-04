import Foundation

extension Duration {
    /// Converts a timeline value to fractional seconds for the probe UI.
    var probeSeconds: Double {
        let value = components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
