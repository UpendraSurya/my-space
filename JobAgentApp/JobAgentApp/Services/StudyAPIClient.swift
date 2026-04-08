import Foundation

actor StudyAPIClient {
    static let shared = StudyAPIClient()
    private let base = "http://127.0.0.1:8000"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // chat can be slow
        session = URLSession(configuration: config)
    }

    // MARK: - Notes

    func listNotes() async throws -> [StudyNote] {
        return try await get("/study/notes")
    }

    func getNote(_ noteId: String) async throws -> StudyNoteContent {
        let encoded = noteId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? noteId
        return try await get("/study/notes/\(encoded)")
    }

    func reindex() async throws -> [String: Int] {
        return try await post("/study/reindex", body: EmptyBody())
    }

    // MARK: - Search

    func search(query: String, k: Int = 8) async throws -> StudySearchResponse {
        struct Body: Encodable { let query: String; let k: Int }
        return try await post("/study/search", body: Body(query: query, k: k))
    }

    // MARK: - Chat

    func chat(query: String, history: [StudyChatMessage]) async throws -> StudyChatResponse {
        let histItems = history.map {
            StudyChatRequest.StudyChatHistoryItem(role: $0.role, content: $0.content)
        }
        let body = StudyChatRequest(query: query, history: histItems)
        return try await post("/study/chat", body: body)
    }

    // MARK: - Upload

    func uploadFile(fileURL: URL, title: String, topic: String) async throws -> StudyUploadResponse {
        guard let url = URL(string: base + "/study/upload") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL.pathExtension)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        for (name, value) in [("title", title), ("topic", topic)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(StudyUploadResponse.self, from: data)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf":  return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt":  return "text/plain"
        case "md":   return "text/markdown"
        default:     return "application/octet-stream"
        }
    }

    private struct EmptyBody: Encodable {}
}
