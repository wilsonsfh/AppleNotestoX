import Foundation

actor GroqService {
    enum GroqError: Error, LocalizedError {
        case missingKey
        case invalidKey
        case http(Int, String)
        case decoding(String)
        case malformedSections(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "API key is not set."
            case .invalidKey: return "The API key was rejected (401). Re-check the key."
            case .http(let code, let msg): return "LLM API \(code): \(msg)"
            case .decoding(let msg): return "Failed to decode LLM response: \(msg)"
            case .malformedSections(let msg): return "LLM did not return valid section JSON: \(msg)"
            }
        }
    }

    private let session: URLSession
    private var baseURL: URL
    private var model: String
    private var apiKey: String?

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.groq.com/openai/v1/")!,
        model: String = "llama-3.3-70b-versatile"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
    }

    /// Repoints this service at a different OpenAI-compatible chat-completions
    /// endpoint/model, e.g. switching between Groq and a GLM gateway. Callers
    /// must set the matching API key via `setAPIKey` after reconfiguring.
    func configure(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    func setAPIKey(_ key: String?) {
        self.apiKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// - Parameter existingHeaders: Section headers already chosen for earlier
    ///   batches of the same merge run (see `MergeBatching`). When non-empty,
    ///   the model is asked to reuse one of these verbatim whenever a note
    ///   fits, so batches merge cleanly instead of producing near-duplicate
    ///   headers like "Work" and "Work Notes".
    func categorize(notes: [MergeSourceNote], existingHeaders: [String] = []) async throws -> [MergeSection] {
        guard let apiKey, !apiKey.isEmpty else { throw GroqError.missingKey }

        let userContent = notes.map { "### \($0.title) (id: \($0.noteID))\n\($0.plainText)" }.joined(separator: "\n\n")
        var systemPrompt = """
        You group short personal notes into topic categories. Read all the notes below \
        and invent whatever section headers best group their content — do not use a fixed \
        list. Respond with strict JSON only, matching this shape exactly, no prose, no \
        markdown fences:
        {"sections":[{"header":"string","body":"string","source_note_ids":["string"]}]}
        Every note id you were given must appear in at least one section's source_note_ids.
        """
        if !existingHeaders.isEmpty {
            let headerList = existingHeaders.map { "\"\($0)\"" }.joined(separator: ", ")
            systemPrompt += """
            \nThese section headers are already in use by other batches of notes from this \
            same run — reuse one of them verbatim (exact spelling) whenever a note's content \
            fits: [\(headerList)]. Only invent a new header when nothing existing fits.
            """
        }

        let firstAttempt = try await complete(system: systemPrompt, user: userContent)
        if let sections = Self.parseSections(from: firstAttempt) {
            return sections
        }

        let retryPrompt = systemPrompt + "\nYour previous response was not valid JSON matching that shape. Return ONLY the JSON object, nothing else."
        let secondAttempt = try await complete(system: retryPrompt, user: userContent)
        guard let sections = Self.parseSections(from: secondAttempt) else {
            throw GroqError.malformedSections(secondAttempt)
        }
        return sections
    }

    private func complete(system: String, user: String) async throws -> String {
        guard let apiKey else { throw GroqError.missingKey }
        struct Message: Encodable { let role: String; let content: String }
        struct ResponseFormat: Encodable { let type = "json_object" }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let response_format = ResponseFormat()
            let temperature = 0.2
        }
        let body = Body(model: model, messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: user)
        ])

        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        // Large batches (many selected notes) can take well over the
        // default 60s URLSession timeout to categorize; give the request
        // room before giving up.
        req.timeoutInterval = Self.requestTimeoutSeconds

        var attempt = 0
        while true {
            attempt += 1
            let (data, resp): (Data, URLResponse)
            do {
                (data, resp) = try await session.data(for: req)
            } catch let urlError as URLError where urlError.code == .timedOut {
                throw Self.timeoutError(afterSeconds: req.timeoutInterval)
            }
            guard let http = resp as? HTTPURLResponse else { throw GroqError.http(0, "no response") }
            if (200..<300).contains(http.statusCode) {
                struct ChatResponse: Decodable {
                    struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
                    let choices: [Choice]
                }
                do {
                    let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                    guard let content = decoded.choices.first?.message.content else {
                        throw GroqError.decoding("no choices in response")
                    }
                    return content
                } catch let err as GroqError {
                    throw err
                } catch {
                    throw GroqError.decoding("\(error)")
                }
            }
            if http.statusCode == 401 { throw GroqError.invalidKey }
            if http.statusCode == 429, attempt < 4 {
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)) ?? pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue
            }
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GroqError.http(http.statusCode, msg)
        }
    }

    static let requestTimeoutSeconds: TimeInterval = 180

    static func timeoutError(afterSeconds seconds: TimeInterval) -> GroqError {
        .http(0, "Request timed out after \(Int(seconds))s — try selecting fewer notes at once, or switch providers in Settings.")
    }

    private static func parseSections(from jsonContent: String) -> [MergeSection]? {
        struct Wrapper: Decodable { let sections: [MergeSection] }
        guard let data = jsonContent.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data),
              !wrapper.sections.isEmpty else {
            return nil
        }
        return wrapper.sections
    }
}
