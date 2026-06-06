// Sources/Rush/TDXDecode.swift
import Foundation

/// Decoding helpers for TDX list responses, which arrive in two shapes:
///   - **bare array** — most v2 endpoints (Bus, Bike, Air, Rail metro):  `[ {…}, {…} ]`
///   - **wrapped object** — v2 Road/Traffic and v1 Parking:  `{ …metadata…, "<Dataset>": [ {…} ] }`
///
/// Tools should not have to know which shape a given endpoint uses, so `list`
/// accepts either. The wrapper's data array is found key-agnostically (TDX
/// wrappers carry scalar metadata plus exactly one data array), which keeps the
/// helper robust to per-dataset key names (`LiveTraffics`, `News`, `CarParks`…).
enum TDXDecode {
    /// Decode `[T]` from a TDX body, tolerating both the bare-array and the
    /// wrapped-object shapes. Returns `[]` when neither yields a decodable list,
    /// preserving the project's "empty ≠ error" invariant for production tools.
    /// (Contract tests assert the strict shape separately.)
    static func list<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let decoder = JSONDecoder()
        if let bare = try? decoder.decode([T].self, from: data) { return bare }
        return unwrappedArray(T.self, from: data, decoder: decoder) ?? []
    }

    /// Extract and decode the single array field from a wrapped TDX object.
    /// Returns `nil` if the body is not a wrapped object or no array field
    /// decodes into `[T]`.
    static func unwrappedArray<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [T]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for value in obj.values {
            guard let arr = value as? [Any],
                  let arrData = try? JSONSerialization.data(withJSONObject: arr) else { continue }
            if let decoded = try? decoder.decode([T].self, from: arrData) { return decoded }
        }
        return nil
    }
}
