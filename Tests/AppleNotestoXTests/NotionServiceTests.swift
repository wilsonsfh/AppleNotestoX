import XCTest
@testable import AppleNotestoX

final class NotionServiceTests: XCTestCase {

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

    func test_verifyToken_sendsAuthAndVersion() async throws {
        let session = makeSession()
        let notion = NotionService(session: session)
        await notion.setToken("secret_xyz")

        MockURLProtocol.handler = { req in
            let body = #"{"object":"user","name":"Wilson","bot":{"workspace_name":"Wilson's WS"}}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        let ws = try await notion.verifyToken()
        XCTAssertEqual(ws, "Wilson's WS")

        let req = MockURLProtocol.captured.last!
        XCTAssertEqual(req.url?.path, "/v1/users/me")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret_xyz")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "Notion-Version"))
    }

    func test_unauthorized_throwsInvalidToken() async {
        let session = makeSession()
        let notion = NotionService(session: session)
        await notion.setToken("bad")
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"message":"invalid"}"#.utf8))
        }
        do {
            _ = try await notion.verifyToken()
            XCTFail("expected throw")
        } catch let err as NotionService.NotionError {
            if case .invalidToken = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_createPage_payloadShape() async throws {
        let session = makeSession()
        let notion = NotionService(session: session)
        await notion.setToken("k")
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"id":"new-page-id"}"#.utf8))
        }
        let id = try await notion.createPage(parentID: "PARENT", title: "Hello")
        XCTAssertEqual(id, "new-page-id")

        let req = MockURLProtocol.captured.last!
        XCTAssertEqual(req.url?.path, "/v1/pages")
        XCTAssertEqual(req.httpMethod, "POST")
        let body = MockURLProtocol.bodyData(from: req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let parent = json["parent"] as? [String: Any]
        XCTAssertEqual(parent?["page_id"] as? String, "PARENT")
        let props = json["properties"] as? [String: Any]
        let titleProp = props?["title"] as? [String: Any]
        let titleArr = titleProp?["title"] as? [[String: Any]]
        let firstText = titleArr?.first?["text"] as? [String: Any]
        XCTAssertEqual(firstText?["content"] as? String, "Hello")
    }

    func test_appendBlocks_chunksAt100() async throws {
        let session = makeSession()
        let notion = NotionService(session: session)
        await notion.setToken("k")
        var requestCount = 0
        MockURLProtocol.handler = { req in
            requestCount += 1
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"results":[]}"#.utf8))
        }
        let blocks: [NotionBlock] = (0..<150).map { _ in .paragraph([NotionRichText(content: "x")]) }
        try await notion.appendBlocks(blocks, to: "PAGE")
        XCTAssertEqual(requestCount, 2)

        let firstReq = MockURLProtocol.captured.first!
        XCTAssertEqual(firstReq.httpMethod, "PATCH")
        XCTAssertEqual(firstReq.url?.path, "/v1/blocks/PAGE/children")
        let body = MockURLProtocol.bodyData(from: firstReq)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let children = json["children"] as? [[String: Any]]
        XCTAssertEqual(children?.count, 100)
    }

    func test_imageBlock_encodingShape() throws {
        let block = NotionBlock.imageUploaded(fileUploadID: "FU-123")
        let out = NotionBlockEncoder.encode(block)
        let data = try JSONEncoder().encode(out)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "image")
        let image = json["image"] as? [String: Any]
        XCTAssertEqual(image?["type"] as? String, "file_upload")
        let fu = image?["file_upload"] as? [String: Any]
        XCTAssertEqual(fu?["id"] as? String, "FU-123")
    }

    func test_paragraph_encodesRichText() throws {
        let block = NotionBlock.paragraph([
            NotionRichText(content: "hi", bold: true),
            NotionRichText(content: " world")
        ])
        let out = NotionBlockEncoder.encode(block)
        let data = try JSONEncoder().encode(out)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "paragraph")
        let para = json["paragraph"] as? [String: Any]
        let rt = para?["rich_text"] as? [[String: Any]]
        XCTAssertEqual(rt?.count, 2)
        let first = rt?.first
        XCTAssertEqual(first?["type"] as? String, "text")
        let text = first?["text"] as? [String: Any]
        XCTAssertEqual(text?["content"] as? String, "hi")
        let ann = first?["annotations"] as? [String: Any]
        XCTAssertEqual(ann?["bold"] as? Bool, true)
    }
}

// MARK: - URL mock

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    // Accessed only from URLProtocol callbacks during serial test runs; the class is
    // already `@unchecked Sendable`, so opt out of Swift 6 global-state checking here.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var captured: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured.append(self.request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "mock", code: 1))
            return
        }
        let (resp, data) = handler(self.request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        if let stream = request.httpBodyStream {
            var data = Data()
            stream.open()
            defer { stream.close() }
            let bufSize = 4096
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            return data
        }
        return Data()
    }
}
