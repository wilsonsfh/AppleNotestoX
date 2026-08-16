import XCTest
@testable import AppleNotestoX

final class GroqServiceTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.handler = nil
        MockURLProtocol.captured = []
    }

    func test_categorize_missingKey_throws() async {
        let groq = GroqService(session: makeSession())
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .missingKey = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_categorize_sendsAuthAndModel_parsesJSONContent() async throws {
        let session = makeSession()
        let groq = GroqService(session: session, model: "llama-3.3-70b-versatile")
        await groq.setAPIKey("gsk_test")

        let content = #"{"sections":[{"header":"Work","body":"Body text","source_note_ids":["A"]}]}"#
        MockURLProtocol.handler = { req in
            let payload = #"{"choices":[{"message":{"content":\#(Self.jsonStringLiteral(content))}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }

        let sections = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")])
        XCTAssertEqual(sections, [MergeSection(header: "Work", bodyText: "Body text", sourceNoteIDs: ["A"])])

        let req = MockURLProtocol.captured.last!
        XCTAssertEqual(req.url?.path, "/openai/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer gsk_test")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(from: req)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "llama-3.3-70b-versatile")
    }

    func test_configure_repointsBaseURLAndModel_forSubsequentRequests() async throws {
        let session = makeSession()
        let groq = GroqService(session: session, model: "llama-3.3-70b-versatile")
        await groq.setAPIKey("test-key")
        await groq.configure(baseURL: URL(string: "https://tbtk.asia/v1/")!, model: "glm-5.2")

        let content = #"{"sections":[{"header":"Work","body":"Body text","source_note_ids":["A"]}]}"#
        MockURLProtocol.handler = { req in
            let payload = #"{"choices":[{"message":{"content":\#(Self.jsonStringLiteral(content))}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }

        _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")])

        let req = MockURLProtocol.captured.last!
        XCTAssertEqual(req.url?.absoluteString, "https://tbtk.asia/v1/chat/completions")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(from: req)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "glm-5.2")
    }

    func test_categorize_withExistingHeaders_includesThemInSystemPrompt() async throws {
        let session = makeSession()
        let groq = GroqService(session: session)
        await groq.setAPIKey("gsk_test")

        let content = #"{"sections":[{"header":"Work","body":"Body","source_note_ids":["A"]}]}"#
        MockURLProtocol.handler = { req in
            let payload = #"{"choices":[{"message":{"content":\#(Self.jsonStringLiteral(content))}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }

        _ = try await groq.categorize(
            notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")],
            existingHeaders: ["Work", "Health"]
        )

        let req = MockURLProtocol.captured.last!
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(from: req)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let systemContent = try XCTUnwrap(messages.first { $0["role"] as? String == "system" }?["content"] as? String)
        XCTAssertTrue(systemContent.contains("\"Work\""))
        XCTAssertTrue(systemContent.contains("\"Health\""))
    }

    func test_timeoutError_producesActionableMessage() {
        let err = GroqService.timeoutError(afterSeconds: 180)
        guard case .http(let code, let message) = err else {
            XCTFail("expected .http case, got \(err)")
            return
        }
        XCTAssertEqual(code, 0)
        XCTAssertTrue(message.contains("180s"))
        XCTAssertTrue(message.contains("fewer notes"))
    }

    func test_categorize_unauthorized_throwsInvalidKey() async {
        let session = makeSession()
        let groq = GroqService(session: session)
        await groq.setAPIKey("bad")
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"invalid"}"#.utf8))
        }
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "x")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .invalidKey = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_categorize_malformedJSON_retriesOnceThenThrows() async {
        let session = makeSession()
        let groq = GroqService(session: session)
        await groq.setAPIKey("k")
        var callCount = 0
        MockURLProtocol.handler = { req in
            callCount += 1
            let payload = #"{"choices":[{"message":{"content":"not json"}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "x")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .malformedSections = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
        XCTAssertEqual(callCount, 2, "expected exactly one retry after the first malformed response")
    }

    private static func jsonStringLiteral(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(data: data, encoding: .utf8)!
    }
}
