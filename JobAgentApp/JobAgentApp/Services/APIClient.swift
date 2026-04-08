import Foundation

enum APIError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case notFound
    case offline

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .serverError(let code, let msg): return "Server \(code): \(msg)"
        case .notFound: return "Not found"
        case .offline: return "Backend server not running. Start it with: python3 api/server.py"
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let base = "http://127.0.0.1:8000"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    // MARK: - Generic fetch

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw APIError.serverError(0, "Invalid URL")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.serverError(0, "No HTTP response")
            }
            if http.statusCode == 404 { throw APIError.notFound }
            if http.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(http.statusCode, msg)
            }
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let e as APIError {
            throw e
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
                                              || urlError.code == .networkConnectionLost {
            throw APIError.offline
        } catch let e as DecodingError {
            throw APIError.decodingError(e)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw APIError.serverError(0, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.serverError(0, "No HTTP response")
            }
            if http.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(http.statusCode, msg)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as APIError { throw e
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost {
            throw APIError.offline
        } catch let e as DecodingError { throw APIError.decodingError(e)
        } catch { throw APIError.networkError(error) }
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw APIError.serverError(0, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.serverError(0, "No HTTP response")
            }
            if http.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(http.statusCode, msg)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as APIError { throw e
        } catch let e as DecodingError { throw APIError.decodingError(e)
        } catch { throw APIError.networkError(error) }
    }

    // MARK: - API methods

    func stats() async throws -> AppStats {
        try await fetch("/stats")
    }

    func jobs(status: String? = nil, minScore: Float? = nil) async throws -> [JobSummary] {
        var path = "/jobs?"
        if let s = status, s != "all" { path += "status=\(s)&" }
        if let m = minScore { path += "min_score=\(m)&" }
        return try await fetch(path)
    }

    func jobDetail(_ id: Int) async throws -> JobDetail {
        try await fetch("/jobs/\(id)")
    }

    func application(for jobId: Int) async throws -> ApplicationInfo? {
        try? await fetch("/jobs/\(jobId)/application")
    }

    func atsScore(for jobId: Int) async throws -> ATSScoreDetail? {
        try? await fetch("/jobs/\(jobId)/ats")
    }

    func updateStatus(jobId: Int, status: String) async throws {
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await patch("/jobs/\(jobId)/status", body: ["status": status])
    }

    func runPipeline() async throws {
        struct Resp: Decodable { let ok: Bool; let message: String }
        let _: Resp = try await post("/pipeline/run")
    }

    func pipelineStatus() async throws -> PipelineLog {
        try await fetch("/pipeline/status")
    }

    func profile() async throws -> UserProfile {
        try await fetch("/profile")
    }

    func updateProfile(_ profile: UserProfile) async throws {
        struct Resp: Decodable { let ok: Bool }
        var body: [String: Any] = [:]
        if let v = profile.name { body["name"] = v }
        if let v = profile.email { body["email"] = v }
        if let v = profile.phone { body["phone"] = v }
        if let v = profile.linkedin { body["linkedin"] = v }
        if let v = profile.github { body["github"] = v }
        if let v = profile.skills { body["skills"] = v }
        let _: Resp = try await patch("/profile", body: body)
    }

    func health() async -> Bool {
        struct H: Decodable { let status: String }
        guard let h: H = try? await fetch("/health") else { return false }
        return h.status == "ok"
    }
}
