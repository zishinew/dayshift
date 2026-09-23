import Foundation
import Observation
import Security

struct CloudConfiguration {
    let url: URL
    let publishableKey: String

    static var bundled: CloudConfiguration? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "DayshiftSupabaseURL") as? String,
              let url = URL(string: urlString),
              url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "DayshiftSupabasePublishableKey") as? String,
              !key.isEmpty else { return nil }
        return CloudConfiguration(url: url, publishableKey: key)
    }
}

struct CloudUser: Codable {
    let id: UUID
    let email: String?
}

struct CloudSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: CloudUser

    init(payload: AuthPayload) throws {
        guard let accessToken = payload.accessToken,
              let refreshToken = payload.refreshToken,
              let expiresIn = payload.expiresIn,
              let user = payload.user else { throw CloudError("sign-in did not return a session") }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        self.user = user
    }
}

struct AuthPayload: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: CloudUser?
}

struct CloudError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct CloudAPI {
    let configuration: CloudConfiguration
    var session: URLSession = .shared

    func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        accessToken: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: configuration.url) else { throw CloudError("invalid server URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError("no server response") }
        guard (200..<300).contains(response.statusCode) else {
            let details = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = details?["msg"] as? String
                ?? details?["error_description"] as? String
                ?? details?["message"] as? String
                ?? details?["error"] as? String
                ?? "server returned \(response.statusCode)"
            throw CloudError(message.lowercased())
        }
        return data
    }
}

private enum SessionKeychain {
    private static let service = "com.zishine.dayshift.cloud-session"
    private static let account = "current"

    static func load() -> CloudSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSession.self, from: data)
    }

    static func save(_ session: CloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CloudError("could not save your sign-in securely")
            }
        } else if status != errSecSuccess {
            throw CloudError("could not save your sign-in securely")
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@Observable
final class CloudAccount {
    private(set) var session: CloudSession?
    private(set) var isWorking = false
    var message: String?

    @ObservationIgnored private let configuration: CloudConfiguration?
    @ObservationIgnored private var refreshTask: Task<CloudSession, Error>?

    var isConfigured: Bool { configuration != nil }
    var userID: UUID? { session?.user.id }
    var email: String? { session?.user.email }

    init(configuration: CloudConfiguration? = .bundled) {
        self.configuration = configuration
        session = SessionKeychain.load()
    }

    func signIn(email: String, password: String) async {
        await authenticate(path: "/auth/v1/token?grant_type=password", email: email, password: password)
    }

    func signUp(email: String, password: String) async {
        await authenticate(path: "/auth/v1/signup", email: email, password: password)
    }

    private func authenticate(path: String, email: String, password: String) async {
        guard let configuration else { message = "cloud sync is not configured"; return }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            message = "enter your email and password"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password])
            let response = try await CloudAPI(configuration: configuration).request(path, method: "POST", body: body)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(AuthPayload.self, from: response)
            if payload.accessToken == nil {
                message = "check your email to confirm your account, then sign in"
                return
            }
            let newSession = try CloudSession(payload: payload)
            try SessionKeychain.save(newSession)
            session = newSession
            message = nil
        } catch {
            message = error.localizedDescription.lowercased()
        }
    }

    func accessToken() async throws -> String {
        guard let session else { throw CloudError("sign in to sync") }
        if session.expiresAt > Date().addingTimeInterval(60) { return session.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let configuration else { throw CloudError("cloud sync is not configured") }
        let task = Task<CloudSession, Error> {
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
            let response = try await CloudAPI(configuration: configuration).request(
                "/auth/v1/token?grant_type=refresh_token", method: "POST", body: body
            )
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try CloudSession(payload: decoder.decode(AuthPayload.self, from: response))
        }
        refreshTask = task
        defer { refreshTask = nil }
        let refreshed = try await task.value
        guard self.session?.refreshToken == session.refreshToken else {
            throw CloudError("signed out")
        }
        try SessionKeychain.save(refreshed)
        self.session = refreshed
        return refreshed.accessToken
    }

    func signOut() async {
        let token = session?.accessToken
        SessionKeychain.clear()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        message = nil
        if let configuration, let token {
            _ = try? await CloudAPI(configuration: configuration).request(
                "/auth/v1/logout", method: "POST", accessToken: token
            )
        }
    }
}
