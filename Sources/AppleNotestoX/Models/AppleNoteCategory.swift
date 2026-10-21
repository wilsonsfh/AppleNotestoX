import Foundation

/// A lightweight, local-only routing hint for Apple Notes exports. It keeps
/// raw source material browsable without interpreting it into wiki content.
enum AppleNoteCategory: String, CaseIterable, Sendable {
    case careerAndWork = "career-and-work"
    case technologyAndLearning = "technology-and-learning"
    case personalReflections = "personal-reflections"
    case healthAndWellbeing = "health-and-wellbeing"
    case travelAndFinance = "travel-and-finance"
    case hobbiesAndLifestyle = "hobbies-and-lifestyle"
    case referenceAndLists = "reference-and-lists"

    var directoryName: String { rawValue }

    static func classify(title: String, markdown: String) -> Self {
        // Match whole words only: as raw substrings, "ai" hits "said" and
        // "email", and "work" hits "network". Padding with spaces lets
        // multi-word keywords match the same way.
        let words = (title + "\n" + markdown).lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        let text = " " + words.joined(separator: " ") + " "
        let terms: [(Self, [String])] = [
            (.healthAndWellbeing, ["therapy", "health", "sleep", "skincare", "wellbeing", "mental"]),
            (.travelAndFinance, ["travel", "trip", "flight", "hotel", "expense", "budget", "finance", "resale"]),
            (.hobbiesAndLifestyle, ["guitar", "music", "singing", "dance", "photography", "camera", "cooking", "clothes", "coffee", "keyboard", "dj"]),
            (.careerAndWork, ["career", "interview", "resume", "job", "intern", "work", "cloudflare", "customer engineer", "solutions engineer"]),
            (.technologyAndLearning, ["programming", "coding", "software", "engineering", "ai", "llm", "cloud", "react", "aws", "hft"]),
            (.personalReflections, ["reflection", "myself", "relationship", "feeling", "stress", "confidence", "personal"]),
            (.referenceAndLists, ["list", "account", "subscription", "reference"])
        ]

        let ranked = terms.map { category, keywords in
            (category, keywords.reduce(into: 0) { score, keyword in
                score += text.components(separatedBy: " \(keyword) ").count - 1
            })
        }
        guard let best = ranked.max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return .referenceAndLists
        }
        return best.0
    }
}
