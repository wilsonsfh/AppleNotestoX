import Foundation

/// A parsed snapshot of `review/study-data.js` (`window.STUDY_DATA = {…};`).
struct StudyData: Sendable, Equatable {
    let conceptCount: Int
    let cardCount: Int
    let edgeCount: Int
    let generatedAt: String?
    let topConcepts: [String]   // titles, ranked by edge degree (desc)

    private struct Raw: Decodable {
        struct Concept: Decodable { let id: String; let title: String }
        struct Edge: Decodable { let source: String; let target: String }
        struct AnyCard: Decodable {}   // count only
        let generatedAt: String?
        let concepts: [Concept]
        let cards: [AnyCard]
        let edges: [Edge]
    }

    /// Strips the `window.STUDY_DATA = ` wrapper and decodes the JSON object.
    static func parse(_ js: String, topN: Int = 6) -> StudyData? {
        guard let start = js.firstIndex(of: "{"),
              let end = js.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(js[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }

        var degree: [String: Int] = [:]
        for e in raw.edges {
            degree[e.source, default: 0] += 1
            degree[e.target, default: 0] += 1
        }
        let top = raw.concepts
            .sorted { (degree[$0.id] ?? 0, $1.title) > (degree[$1.id] ?? 0, $0.title) }
            .prefix(topN)
            .map(\.title)

        return StudyData(
            conceptCount: raw.concepts.count,
            cardCount: raw.cards.count,
            edgeCount: raw.edges.count,
            generatedAt: raw.generatedAt,
            topConcepts: Array(top)
        )
    }
}
