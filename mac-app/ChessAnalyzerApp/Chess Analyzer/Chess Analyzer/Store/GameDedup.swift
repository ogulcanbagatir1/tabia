import Foundation

/// Duplicate-detection keys for merging games from multiple sources (the hosted reference base +
/// the user's own imports + optional TWIC fetches) without double-counting. Mirrors the intent of
/// the offline `chess-db-builder`'s move-hash: two games with the same move sequence are the same
/// game. Light SAN canonicalization (strip check/mate/NAG glyphs, normalize castling) makes the key
/// stable across sources that spell SAN differently ("Nf3+" vs "Nf3", "0-0" vs "O-O").
enum GameDedup {

    /// Canonical, whitespace-joined move string used for hashing.
    static func normalizedMoves(_ sans: [String]) -> String {
        var out = ""
        out.reserveCapacity(sans.count * 4)
        for (i, san) in sans.enumerated() {
            if i > 0 { out.append(" ") }
            out.append(canonicalSAN(san))
        }
        return out
    }

    /// Strip trailing check/mate/annotation glyphs and normalize castling to a single spelling.
    static func canonicalSAN(_ san: String) -> String {
        var t = Substring(san)
        while let last = t.last, last == "+" || last == "#" || last == "!" || last == "?" {
            t = t.dropLast()
        }
        var s = String(t)
        if s.contains("0") {
            s = s.replacingOccurrences(of: "0-0-0", with: "O-O-O")
                 .replacingOccurrences(of: "0-0", with: "O-O")
        }
        return s
    }

    /// Stable 64-bit hash (FNV-1a) of the canonical move sequence. Collision probability over a few
    /// million games is ~1e-6 — negligible for dedup.
    static func gameHash(_ sans: [String]) -> Int64 {
        fnv1a64(normalizedMoves(sans))
    }

    static func fnv1a64(_ s: String) -> Int64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return Int64(bitPattern: h)
    }
}
