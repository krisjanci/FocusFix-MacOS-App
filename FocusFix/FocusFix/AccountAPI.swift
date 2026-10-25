// MARK: - FF: ACCOUNTS
// Public client configuration only. Administrator keys must never enter the app.
import Foundation

nonisolated struct AccountConfiguration: Equatable {
    let origin: URL
    let publicKey: String
    let researchSharingEnabled: Bool
    let studyInformationURL: URL?

    init?(url: String, publicKey: String, researchSharingEnabled: Bool = false, studyURL: String = "") {
        guard let origin = URL(string: url), origin.scheme == "https", origin.host != nil,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/",
              !publicKey.isEmpty, !publicKey.hasPrefix("sb_secret_") else { return nil }
        // Reject legacy JWT administrator keys as well as modern secret keys.
        let parts = publicKey.split(separator: ".")
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                  let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  claims["role"] as? String == "anon" else { return nil }
        } else if !publicKey.hasPrefix("sb_publishable_") { return nil }
        self.origin = origin
        self.publicKey = publicKey
        let study = URL(string: studyURL)
        self.studyInformationURL = study.flatMap { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil ? $0 : nil }
        self.researchSharingEnabled = researchSharingEnabled && studyInformationURL != nil
    }

    static var bundled: AccountConfiguration? {
        let info = Bundle.main.infoDictionary ?? [:]
        return AccountConfiguration(url: info["FocusFixAccountURL"] as? String ?? "",
            publicKey: info["FocusFixAccountPublicKey"] as? String ?? "",
            researchSharingEnabled: info["FocusFixResearchSharingEnabled"] as? Bool ?? false,
            studyURL: info["FocusFixStudyInformationURL"] as? String ?? "")
    }
}

nonisolated struct AccountUser: Codable, Equatable { let id: UUID; let email: String? }
nonisolated struct AccountSession: Codable, Equatable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
    let expires_in: Double?
    let user: AccountUser
    var expiresAt: Date { Date(timeIntervalSince1970: expires_at ?? 0) }

    func withExpiry(now: Date = Date()) -> AccountSession {
        AccountSession(access_token: access_token, refresh_token: refresh_token,
            expires_at: expires_at ?? now.timeIntervalSince1970 + (expires_in ?? 3600),
            expires_in: expires_in, user: user)
    }
}
nonisolated struct ResearchEnrollment: Codable {
    let user_id: UUID
    let enabled: Bool
    let consent_version: String
}
nonisolated struct AccountProfileRow: Codable {
    let user_id: UUID
    let profile: UserProfile
}
nonisolated struct AccountFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class AccountNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

nonisolated struct AccountAPI {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    let configuration: AccountConfiguration
    let transport: Transport

    init(configuration: AccountConfiguration, transport: @escaping Transport = AccountAPI.send) {
        self.configuration = configuration
        self.transport = transport
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: AccountNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountFailure(message: "The account service did not respond.") }
        return (data, http)
    }

    func request(path: String, method: String = "POST", body: Data? = nil, token: String? = nil,
                 query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(url: configuration.origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            // Do not surface raw server responses: they may echo identifiers or request contents.
            let message: String
            switch response.statusCode {
            case 400, 401, 403: message = "The request was not accepted. Check your sign-in details, email confirmation, or account access."
            case 413: message = "This file exceeds the receiving service's limit. Export the ZIP locally instead."
            case 402, 429: message = "The free service limit was reached. Try later; your local data is kept."
            default: message = "The account service is unavailable (\(response.statusCode)). Your local data is kept."
            }
            throw AccountFailure(message: message)
        }
        return data
    }

    func signUp(email: String, password: String) async throws -> AccountSession? {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await request(path: "auth/v1/signup", body: body)
        return (try? JSONDecoder().decode(AccountSession.self, from: data))?.withExpiry()
    }
    func signIn(email: String, password: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await request(path: "auth/v1/token", body: body,
            query: [URLQueryItem(name: "grant_type", value: "password")])
        return try JSONDecoder().decode(AccountSession.self, from: data).withExpiry()
    }
    func refresh(_ token: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": token])
        let data = try await request(path: "auth/v1/token", body: body,
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        return try JSONDecoder().decode(AccountSession.self, from: data).withExpiry()
    }
    func resetPassword(email: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        _ = try await request(path: "auth/v1/recover", body: body)
    }
    func verify(email: String, code: String, recovery: Bool) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "token": code,
            "type": recovery ? "recovery" : "signup"])
        let data = try await request(path: "auth/v1/verify", body: body)
        return try JSONDecoder().decode(AccountSession.self, from: data).withExpiry()
    }
    func changePassword(_ password: String, session: AccountSession) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["password": password])
        _ = try await request(path: "auth/v1/user", method: "PUT", body: body, token: session.access_token)
    }
    func profile(session: AccountSession) async throws -> UserProfile? {
        let data = try await request(path: "rest/v1/account_profiles", method: "GET", token: session.access_token,
            query: [URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
                    URLQueryItem(name: "select", value: "user_id,profile")])
        return try JSONDecoder().decode([AccountProfileRow].self, from: data).first?.profile.validated()
    }
    func saveProfile(_ profile: UserProfile, session: AccountSession) async throws {
        let row = AccountProfileRow(user_id: session.user.id, profile: try profile.validated())
        _ = try await request(path: "rest/v1/account_profiles", body: JSONEncoder().encode(row), token: session.access_token,
            query: [URLQueryItem(name: "on_conflict", value: "user_id")],
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }
    func researchEnrollment(session: AccountSession) async throws -> ResearchEnrollment? {
        let data = try await request(path: "rest/v1/research_enrollments", method: "GET", token: session.access_token,
            query: [URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
                    URLQueryItem(name: "select", value: "user_id,enabled,consent_version")])
        return try JSONDecoder().decode([ResearchEnrollment].self, from: data).first
    }
    func requestResearch(session: AccountSession) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["user_id": session.user.id.uuidString.lowercased()])
        _ = try await request(path: "rest/v1/research_interest", body: body, token: session.access_token,
            query: [URLQueryItem(name: "on_conflict", value: "user_id")],
            headers: ["Prefer": "resolution=ignore-duplicates,return=minimal"])
    }
    func researchArchiveReceived(_ id: UUID, session: AccountSession) async throws -> Bool {
        let data = try await request(path: "rest/v1/research_upload_receipts", method: "GET", token: session.access_token,
            query: [URLQueryItem(name: "archive_id", value: "eq.\(id.uuidString.lowercased())"),
                    URLQueryItem(name: "select", value: "archive_id")])
        let rows = try JSONDecoder().decode([[String: String]].self, from: data)
        return rows.contains { $0["archive_id"]?.lowercased() == id.uuidString.lowercased() }
    }
    func confirmResearchArchive(_ id: UUID, objectName: String, session: AccountSession) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["p_archive_id": id.uuidString.lowercased(), "p_object_name": objectName])
        _ = try await request(path: "rest/v1/rpc/confirm_research_upload", body: body, token: session.access_token)
    }
    func signOut(session: AccountSession) async throws {
        _ = try await request(path: "auth/v1/logout", token: session.access_token,
            query: [URLQueryItem(name: "scope", value: "local")])
    }
    func deleteAccount(session: AccountSession) async throws {
        _ = try await request(path: "functions/v1/delete-account", body: Data("{}".utf8), token: session.access_token)
    }
}
