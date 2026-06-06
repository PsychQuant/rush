// Sources/Rush/Tools/InterchangeRegistry.swift
import Foundation

/// Curated table of known TRA ↔ Taipei-Metro (TRTC) interchange stations.
///
/// Cross-system station identity is **hardcoded here, not geo-matched** — the
/// design scopes the all-Taiwan station-identity problem down to this small set
/// of real interchanges. Station IDs were probed from live TDX (TRA `Station` +
/// `Metro/Station/TRTC`); `walkMin` are concourse-transfer estimates.
enum InterchangeRegistry {

    /// One interchange: a TRA station co-located with one or more TRTC stations
    /// (台北車站 maps to two metro nodes — BL12 on 板南線 and R10 on 淡水信義線).
    struct Interchange {
        let name: String
        let traStationID: String
        let trtcStationIDs: [String]
        let walkMin: Int
    }

    static let entries: [Interchange] = [
        Interchange(name: "台北車站", traStationID: "1000", trtcStationIDs: ["BL12", "R10"], walkMin: 5),
        Interchange(name: "板橋",     traStationID: "1020", trtcStationIDs: ["BL07"],         walkMin: 4),
        Interchange(name: "南港",     traStationID: "0980", trtcStationIDs: ["BL22"],         walkMin: 4),
        Interchange(name: "松山",     traStationID: "0990", trtcStationIDs: ["G19"],          walkMin: 3),
    ]

    /// The interchange whose TRA side is this station id, if any.
    static func byTRA(_ id: String) -> Interchange? {
        entries.first { $0.traStationID == id }
    }

    /// The interchange whose TRTC set contains this metro station id, if any.
    static func byTRTC(_ id: String) -> Interchange? {
        entries.first { $0.trtcStationIDs.contains(id) }
    }
}
