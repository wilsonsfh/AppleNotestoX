import Foundation

actor NotionService {
    enum NotionError: Error, LocalizedError {
        case missingToken
        case invalidToken
        case http(Int, String)
        case decoding(String)
        case fileUploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingToken: return "Notion integration token is not set."
            case .invalidToken: return "Notion rejected the integration token (401). Re-check the secret."
            case .http(let code, let msg): return "Notion API \(code): \(msg)"
            case .decoding(let msg): return "Failed to decode Notion response: \(msg)"
            case .fileUploadFailed(let msg): return "Notion file upload failed: \(msg)"
            }
        }
    }

    private let session: URLSession
    private let baseURL = URL(string: "https://api.notion.com/v1/")!
    private let apiVersion = "2022-06-28"
    private var token: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setToken(_ t: String?) {
        self.token = t?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Public

    func verifyToken() async throws -> String {
        struct Me: Decodable { let name: String?; let bot: Bot?; struct Bot: Decodable { let workspace_name: String? } }
        let me: Me = try await request("GET", path: "users/me")
        return me.bot?.workspace_name ?? me.name ?? "Notion"
    }

    /// Returns top-level pages shared with the integration (i.e. parent is workspace
    /// or a page outside the integration's view). For the GUI tree this is the seed.
    func searchSharedPages() async throws -> [NotionPage] {
        struct Body: Encodable {
            struct Filter: Encodable { let value = "page"; let property = "object" }
            let filter = Filter()
            let page_size = 100
        }
        let resp: SearchResponse = try await request("POST", path: "search", body: try JSONEncoder().encode(Body()))
        return resp.results.compactMap(Self.pageFromRaw(_:)).filter { $0.parentID == nil }
    }

    /// Lists child pages directly under a given page id.
    func childPages(of pageID: String) async throws -> [NotionPage] {
        var pages: [NotionPage] = []
        var cursor: String? = nil
        repeat {
            var path = "blocks/\(pageID)/children?page_size=100"
            if let c = cursor { path += "&start_cursor=\(c)" }
            let resp: BlocksResponse = try await request("GET", path: path)
            for block in resp.results {
                if block.type == "child_page", let title = block.child_page?.title {
                    pages.append(NotionPage(id: block.id, title: title, parentID: pageID, hasChildren: true))
                }
            }
            cursor = resp.has_more ? resp.next_cursor : nil
        } while cursor != nil
        return pages
    }

    /// Creates a new page under a parent page; returns new page id.
    func createPage(parentID: String, title: String) async throws -> String {
        struct Body: Encodable {
            struct Parent: Encodable { let page_id: String }
            struct Properties: Encodable { let title: TitleProp }
            struct TitleProp: Encodable {
                let title: [RichTextOut]
            }
            let parent: Parent
            let properties: Properties
        }
        let body = Body(
            parent: .init(page_id: parentID),
            properties: .init(title: .init(title: [
                RichTextOut(text: .init(content: title), annotations: .default, type: "text")
            ]))
        )
        struct CreateResponse: Decodable { let id: String }
        let resp: CreateResponse = try await request("POST", path: "pages", body: try JSONEncoder().encode(body))
        return resp.id
    }

    /// Appends blocks to a page in chunks of 100 (Notion's per-request cap).
    func appendBlocks(_ blocks: [NotionBlock], to pageID: String) async throws {
        for chunk in blocks.chunks(of: 100) {
            let payload = AppendPayload(children: chunk.map(NotionBlockEncoder.encode))
            _ = try await rawRequest(
                "PATCH",
                path: "blocks/\(pageID)/children",
                body: try JSONEncoder().encode(payload)
            )
        }
    }

    /// Three-step file upload using `single_part` mode. Returns `file_upload_id`.
    func uploadFile(localURL: URL, mimeType: String) async throws -> String {
        let data = try Data(contentsOf: localURL)
        let filename = localURL.lastPathComponent
        struct CreateBody: Encodable { let mode = "single_part"; let filename: String; let content_type: String }
        struct CreateResp: Decodable { let id: String; let upload_url: String }
        let create: CreateResp = try await request(
            "POST", path: "file_uploads",
            body: try JSONEncoder().encode(CreateBody(filename: filename, content_type: mimeType))
        )
        guard let uploadURL = URL(string: create.upload_url) else {
            throw NotionError.fileUploadFailed("invalid upload_url")
        }
        try await multipartUpload(url: uploadURL, fileData: data, filename: filename, mimeType: mimeType)
        return create.id
    }

    // MARK: - Request plumbing

    private func request<R: Decodable>(_ method: String, path: String, body: Data? = nil) async throws -> R {
        let data = try await rawRequest(method, path: path, body: body)
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw NotionError.decoding("\(error) — body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        }
    }

    private func rawRequest(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let token else { throw NotionError.missingToken }
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        var attempt = 0
        while true {
            attempt += 1
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw NotionError.http(0, "no response")
            }
            if (200..<300).contains(http.statusCode) {
                return data
            }
            if http.statusCode == 401 {
                throw NotionError.invalidToken
            }
            if http.statusCode == 429, attempt < 4 {
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)) ?? pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue
            }
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.http(http.statusCode, msg)
        }
    }

    private func multipartUpload(url: URL, fileData: Data, filename: String, mimeType: String) async throws {
        guard let token else { throw NotionError.missingToken }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.fileUploadFailed(body)
        }
    }

    // MARK: - Decoding helpers

    private struct SearchResponse: Decodable {
        let results: [PageRaw]
    }
    private struct PageRaw: Decodable {
        let id: String
        let parent: ParentRaw?
        let properties: [String: PropertyRaw]?
        let archived: Bool?
    }
    private struct ParentRaw: Decodable {
        let type: String
        let workspace: Bool?
        let page_id: String?
        let database_id: String?
    }
    private struct PropertyRaw: Decodable {
        let type: String
        let title: [RichTextIn]?
    }
    private struct RichTextIn: Decodable {
        let plain_text: String?
    }
    private struct BlocksResponse: Decodable {
        let results: [BlockRaw]
        let has_more: Bool
        let next_cursor: String?
    }
    private struct BlockRaw: Decodable {
        let id: String
        let type: String
        let child_page: ChildPageIn?
    }
    private struct ChildPageIn: Decodable { let title: String }

    private static func pageFromRaw(_ raw: PageRaw) -> NotionPage? {
        if raw.archived == true { return nil }
        let title = (raw.properties ?? [:])
            .values
            .first(where: { $0.type == "title" })?
            .title?
            .compactMap { $0.plain_text }
            .joined() ?? "(untitled)"
        var parentID: String? = nil
        if let parent = raw.parent {
            switch parent.type {
            case "page_id": parentID = parent.page_id
            case "database_id": return nil
            case "workspace": parentID = nil
            default: parentID = nil
            }
        }
        return NotionPage(id: raw.id, title: title, parentID: parentID, hasChildren: true)
    }

    // MARK: - Outgoing block payload

    fileprivate struct AppendPayload: Encodable {
        let children: [NotionBlockEncoder.OutBlock]
    }
}

extension NotionService {
    enum BlockEncoderError: Error { case notReadyForUpload(UUID) }
}

// MARK: - Block & rich-text encoding to Notion's JSON shape

struct RichTextOut: Encodable {
    struct Text: Encodable { let content: String; var link: Link? }
    struct Link: Encodable { let url: String }
    struct Annotations: Encodable {
        var bold: Bool = false
        var italic: Bool = false
        var strikethrough: Bool = false
        var underline: Bool = false
        var code: Bool = false
        var color: String = "default"
        static let `default` = Annotations()
    }
    let text: Text
    let annotations: Annotations
    let type: String
}

extension RichTextOut {
    static func from(_ rt: NotionRichText) -> RichTextOut {
        RichTextOut(
            text: Text(content: rt.content, link: rt.link.map { Link(url: $0.absoluteString) }),
            annotations: Annotations(
                bold: rt.bold, italic: rt.italic,
                strikethrough: rt.strikethrough, underline: rt.underline,
                code: rt.code, color: "default"
            ),
            type: "text"
        )
    }
}

enum NotionBlockEncoder {
    struct OutBlock: Encodable {
        var type: String
        var paragraph: TextPayload?
        var heading_1: TextPayload?
        var heading_2: TextPayload?
        var heading_3: TextPayload?
        var bulleted_list_item: TextPayload?
        var numbered_list_item: TextPayload?
        var to_do: ToDoPayload?
        var quote: TextPayload?
        var code: CodePayload?
        var divider: Empty?
        var image: ImagePayload?
    }
    struct TextPayload: Encodable {
        let rich_text: [RichTextOut]
    }
    struct ToDoPayload: Encodable {
        let rich_text: [RichTextOut]
        let checked: Bool
    }
    struct CodePayload: Encodable {
        let rich_text: [RichTextOut]
        let language: String
    }
    struct ImagePayload: Encodable {
        let type: String   // "file_upload"
        let file_upload: FileUploadRef
    }
    struct FileUploadRef: Encodable { let id: String }
    struct Empty: Encodable {}

    static func encode(_ block: NotionBlock) -> OutBlock {
        switch block {
        case .paragraph(let rts):
            return OutBlock(type: "paragraph", paragraph: .init(rich_text: rts.map(RichTextOut.from)))
        case .heading1(let rts):
            return OutBlock(type: "heading_1", heading_1: .init(rich_text: rts.map(RichTextOut.from)))
        case .heading2(let rts):
            return OutBlock(type: "heading_2", heading_2: .init(rich_text: rts.map(RichTextOut.from)))
        case .heading3(let rts):
            return OutBlock(type: "heading_3", heading_3: .init(rich_text: rts.map(RichTextOut.from)))
        case .bulletedListItem(let rts):
            return OutBlock(type: "bulleted_list_item", bulleted_list_item: .init(rich_text: rts.map(RichTextOut.from)))
        case .numberedListItem(let rts):
            return OutBlock(type: "numbered_list_item", numbered_list_item: .init(rich_text: rts.map(RichTextOut.from)))
        case .toDo(let rts, let checked):
            return OutBlock(type: "to_do", to_do: .init(rich_text: rts.map(RichTextOut.from), checked: checked))
        case .quote(let rts):
            return OutBlock(type: "quote", quote: .init(rich_text: rts.map(RichTextOut.from)))
        case .code(let rts, let language):
            return OutBlock(type: "code", code: .init(rich_text: rts.map(RichTextOut.from), language: language))
        case .divider:
            return OutBlock(type: "divider", divider: Empty())
        case .imageUploaded(let id):
            return OutBlock(type: "image", image: .init(type: "file_upload", file_upload: .init(id: id)))
        case .imagePlaceholder:
            // Should never reach here; coordinator must replace before encoding.
            return OutBlock(type: "paragraph", paragraph: .init(rich_text: [
                RichTextOut.from(NotionRichText(content: "[image not uploaded]"))
            ]))
        case .imageFailed(let msg):
            return OutBlock(type: "paragraph", paragraph: .init(rich_text: [
                RichTextOut.from(NotionRichText(content: "[image failed: \(msg)]"))
            ]))
        }
    }
}

// MARK: - Chunking helper

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
}
