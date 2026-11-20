// Ported (heavily trimmed) from CodexBar by Peter Steinberger, MIT License:
// https://github.com/steipete/CodexBar — Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift
// See NOTICE. Only the endpoint, headers and response model were kept.
import Foundation
import Observation

struct UsageWindow: Equatable { var pct: Double; var resetsAt: Date? }

struct Usage: Equatable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?

    private struct Raw: Decodable {
        struct Win: Decodable {
            let utilization: Double?
            let resetsAt: String?
            enum CodingKeys: String, CodingKey { case utilization; case resetsAt = "resets_at" }
        }
        let fiveHour: Win?
        let sevenDay: Win?
        enum CodingKeys: String, CodingKey { case fiveHour = "five_hour"; case sevenDay = "seven_day" }
    }

    static func decode(_ data: Data) throws -> Usage {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        func win(_ w: Raw.Win?) -> UsageWindow? {
            guard let p = w?.utilization else { return nil }
            return UsageWindow(pct: p, resetsAt: w?.resetsAt.flatMap(parseDate))
        }
        return Usage(fiveHour: win(raw.fiveHour), weekly: win(raw.sevenDay))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct UsageHTTPError: Error { let code: Int; let retryAfter: TimeInterval? }

@MainActor @Observable
final class UsageFetcher {
    private(set) var usage: Usage?
    /// Last good usage; "—" only until the first success ever. A 429/timeout keeps the old numbers,
    /// and they survive relaunches (the auto-rebuild relaunches the app on every commit).
    var displayUsage: Usage? { usage }
    /// Logged-in Claude account, from ~/.claude.json.
    private(set) var email: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nextAllowed = Date.distantPast
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private let defaults: UserDefaults
    private static let cacheKey = "lastUsageJSON"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usage = defaults.data(forKey: Self.cacheKey).flatMap { try? Usage.decode($0) }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Throttled: panel clicks call this, and hammering the endpoint gets 429s.
    /// After a failure, waits out Retry-After or an exponential backoff before trying again.
    func refresh() {
        guard Date() >= nextAllowed else { return }
        nextAllowed = Date().addingTimeInterval(60)
        Task {
            email = await Task.detached { Self.readEmail() }.value
            do {
                let data = try await Self.fetch()
                apply(try Usage.decode(data))
                defaults.set(data, forKey: Self.cacheKey)
                failures = 0
            } catch {
                failures += 1
                let wait = Self.backoff(failures: failures, retryAfter: (error as? UsageHTTPError)?.retryAfter)
                NSLog("Perch: usage fetch failed: \(error); next try in \(Int(wait))s")
                apply(nil)
                nextAllowed = Date().addingTimeInterval(wait)
                try? await Task.sleep(for: .seconds(wait))
                refresh()
            }
        }
    }

    /// 2m, 4m, 8m, capped at 15m; a server Retry-After wins when it is longer.
    nonisolated static func backoff(failures: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let exp = min(60 * pow(2, Double(min(failures, 10))), 900)
        return max(exp, retryAfter ?? 0)
    }

    func apply(_ result: Usage?) {
        if let result { usage = result }
    }

    nonisolated static func readEmail() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (obj["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
    }

    nonisolated static func fetch() async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") // required by the endpoint (per CodexBar)
        req.setValue("claude-cli/2.1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            throw UsageHTTPError(code: http?.statusCode ?? 0,
                                 retryAfter: (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init))
        }
        return data
    }

    /// Claude Code's OAuth token from the login keychain. Never logged.
    nonisolated static func token() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tok = (obj["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
        else { throw URLError(.userAuthenticationRequired) }
        return tok
    }
}
