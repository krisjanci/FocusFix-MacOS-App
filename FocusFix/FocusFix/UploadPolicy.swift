// MARK: - FF: QUOTAS
// Client-side sharing eligibility and size limits. The server enforces its own limits; these are not an account-wide billing cap.

import Foundation

// Shared rules for the queue. The server independently enforces the same limits.
nonisolated enum UploadPolicy {
    static let dailySeconds = 180 * 60
    static let maximumZIPBytes = 25 * 1024 * 1024
    static let maximumRawBytes = 100 * 1024 * 1024
    static let dailyZIPBytes = 50 * 1024 * 1024
    static let dailySessions = 30
    static let files = ["events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv",
                        "survey_prompts.csv", "session.json"]

    // Accept a finite session duration within the limit and round it up to whole seconds.
    static func seconds(_ duration: Double) -> Int? {
        guard duration.isFinite, duration > 0, duration <= Double(dailySeconds) else { return nil }
        return Int(ceil(duration))
    }

    // Accept only a plain HTTPS service origin, not embedded credentials, query strings or an endpoint path.
    static func endpoint(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }

    // Allow only finished sessions belonging to this participant and the current sharing consent.
    static func eligible(metadata: [String: Any], participant: String, consent: String?) -> Bool {
        guard let consent, metadata["participant_id"] as? String == participant,
              metadata["sharing_consent_id"] as? String == consent,
              let status = metadata["status"] as? String,
              ["user_stop", "app_quit", "sleep_or_inactive_session", "permission_lost"].contains(status),
              let duration = metadata["duration_seconds"] as? Double,
              seconds(duration) != nil,
              let id = metadata["session_id"] as? String, UUID(uuidString: id) != nil else { return false }
        return true
    }
}

nonisolated struct UploadItem: Codable, Identifiable {
    let id: String
    let participantID: String
    let consentID: String
    let durationSeconds: Int
    var state = "waiting"
    var message = "Waiting to upload"
    var attempts = 0
    var retryAfter = Date.distantPast
    var sha256: String?
    var bytes: Int?
    var uploadedAt: Date?
}

nonisolated struct SharingSettings: Codable {
    var consentID: String?
    var consentedAt: Date?
    var serviceURL: String?
    var items: [UploadItem] = []
}

nonisolated struct UploadReceipt: Decodable {
    let session_id: String
    let sha256: String
    let stored: Bool
}

nonisolated enum SharingError: LocalizedError {
    case message(String)
    // Turn a sharing error into the plain message shown to the user.
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
