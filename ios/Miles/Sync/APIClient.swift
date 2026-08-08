import Foundation

/// Wire format shared with the web API (camelCase JSON, ISO 8601 dates).
struct DriveDTO: Codable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMiles: Double
    var startLat: Double?
    var startLng: Double?
    var endLat: Double?
    var endLng: Double?
    var startAddress: String
    var endAddress: String
    var category: String
    var purposeNote: String
    var rateCentsPerMile: Double
    var polyline: String
    var source: String
    var updatedAt: Date
    var deletedAt: Date?
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case badResponse(status: Int, body: String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sync isn't set up. Add your server address and sign in under Settings."
        case .unauthorized:
            return "Sign-in expired. Sign in again under Settings → Sync."
        case .badResponse(let status, _):
            return "Server error (HTTP \(status))."
        case .invalidURL:
            return "The server address doesn't look like a valid URL."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIClient.isoFormatter.string(from: date))
        }
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = APIClient.isoFormatter.date(from: string)
                ?? APIClient.isoFormatterNoFraction.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable date: \(string)"
            )
        }
        return d
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func baseURL() throws -> URL {
        let raw = AppSettings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw APIError.notConfigured }
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else {
            throw APIError.invalidURL
        }
        return url
    }

    var isConfigured: Bool {
        (try? baseURL()) != nil && Keychain.get(account: Keychain.apiTokenAccount) != nil
    }

    // MARK: - Auth

    struct LoginResponse: Codable { let token: String }

    /// Signs in and stores the long-lived bearer token in the Keychain.
    func login(email: String, password: String) async throws {
        let url = try baseURL().appendingPathComponent("api/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw APIError.unauthorized }
            throw APIError.badResponse(
                status: status, body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        let body = try decoder.decode(LoginResponse.self, from: data)
        Keychain.set(body.token, account: Keychain.apiTokenAccount)
        AppSettings.accountEmail = email
    }

    func logout() {
        Keychain.delete(account: Keychain.apiTokenAccount)
        AppSettings.syncCursor = nil
        AppSettings.lastSyncAt = nil
    }

    // MARK: - Sync

    struct SyncRequest: Codable {
        let cursor: String?
        let drives: [DriveDTO]
    }

    struct SyncResponse: Codable {
        let serverTime: Date
        let drives: [DriveDTO]
    }

    func sync(cursor: String?, drives: [DriveDTO]) async throws -> SyncResponse {
        let url = try baseURL().appendingPathComponent("api/sync")
        guard let token = Keychain.get(account: Keychain.apiTokenAccount) else {
            throw APIError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(SyncRequest(cursor: cursor, drives: drives))
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw APIError.unauthorized }
            throw APIError.badResponse(
                status: status, body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try decoder.decode(SyncResponse.self, from: data)
    }
}
