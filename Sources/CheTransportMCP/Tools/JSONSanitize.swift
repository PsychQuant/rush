// Sources/CheTransportMCP/Tools/JSONSanitize.swift
import Foundation

/// Rewrites every `Double` in a JSON-serialisable structure to its shortest
/// round-trippable decimal form, so `JSONSerialization` emits `25.04` instead
/// of `25.039999999999999`.
///
/// ## Why this exists
///
/// `JSONSerialization` formats `Double` with up to 17 significant digits — enough
/// to round-trip *any* `Double`, but visually noisy for values with no exact binary
/// representation (`25.04`, `88.5`, fares, …). Rounding the value does **not** help:
/// `25.04` has no exact IEEE-754 representation, so `(25.04 * 1e6).rounded() / 1e6`
/// lands back on the identical bit pattern and serialises to the same noisy string.
///
/// The noise lives in the *formatter*, not the value. Swift's `Double.description`
/// already produces the **shortest** string that round-trips; wrapping that string in
/// `NSDecimalNumber` lets `JSONSerialization` emit the clean form while preserving the
/// exact numeric value.
///
/// ## Guarantees
///
/// - **Value-preserving**: the emitted JSON number parses back to a `Double`
///   numerically equal to the input — bit-identical for every finite value
///   except `-0.0`, which renders as `0` (its sign is dropped, but `JSONSerialization`
///   already loses the sign of `-0.0` on round-trip regardless of this code).
/// - **Type-safe**: `Int` stored as `Int` and `Bool` stored as `Bool` are left
///   untouched — `case let d as Double` does not match native `Int`/`Bool` held in
///   `[String: Any]` (confirmed via `NSNumber.objCType`: `Bool` stays `c`, `Int` `q`).
/// - **Non-finite pass-through**: `inf`/`nan` are returned unchanged, so
///   `JSONSerialization` rejects them exactly as it does today (no behaviour change).
/// - **Extreme-magnitude pass-through**: values beyond `NSDecimalNumber`'s exponent
///   range fall back to the raw `Double` (still round-trips, just with the old
///   17-digit form). Such magnitudes never occur in transport data.
///
/// The only observable difference for normal values is that integer-valued doubles
/// render as `25` rather than `25.0` — an identical JSON number that round-trips to `25.0`.
enum JSONSanitize {
    /// Recursively returns `value` with every `Double` replaced by a
    /// shortest-round-trippable `NSDecimalNumber`. Dictionaries and arrays are
    /// walked so nested coordinates (e.g. `{"positions":[{"lat":…}]}`) are covered.
    static func clean(_ value: Any) -> Any {
        switch value {
        case let d as Double:
            guard d.isFinite else { return d }
            // NSDecimalNumber(string:) returns .notANumber for magnitudes beyond
            // Decimal's ±128 exponent ceiling (e.g. 1e300); fall back to the raw
            // Double so those still serialize and round-trip.
            let decimal = NSDecimalNumber(string: d.description)
            return decimal == NSDecimalNumber.notANumber ? d : decimal
        case let dict as [String: Any]:
            return dict.mapValues(clean)
        case let array as [Any]:
            return array.map(clean)
        default:
            return value
        }
    }
}
