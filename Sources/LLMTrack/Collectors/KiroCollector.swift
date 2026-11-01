import Foundation

public final class KiroCollector: @unchecked Sendable {
    private struct KiroDiskCache: Codable {
        let planTier: String
        let creditsUsed: Double
        let creditsTotal: Double
        let creditsRemainingPct: Double
        let resetsOnString: String
        let resetTimestamp: Double?
        let updatedAt: Date
    }

    private struct KiroCredentials {
        var token: String
        var profileArn: String
        var expiresAt: Date?
        var refreshToken: String?
        var key: String
    }

    private struct LiveUsageLimitsResult {
        let planTier: String
        let creditsUsed: Double
        let creditsTotal: Double
        let creditsRemainingPct: Double
        let resetsOnString: String
        let resetsAt: Date?
    }

    private static var lastLiveFetchTime: Date = .distantPast
    private static var cachedStatus: KiroStatus? = nil
    private static let lock = NSLock()

    private static var cacheFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("llm-track", isDirectory: true)
            .appendingPathComponent("kiro_quota_cache.json")
    }

    public init() {}

    public func collect(forceLive: Bool = false) -> KiroStatus {
        var status = KiroStatus()

        // 1. Process matching
        let matches = ProcessHelper.findProcesses(matching: ["kiro-cli", "kiro_cli", "kiro-cli-term", "Kiro.app", "kiro "])
        let validProcesses = matches.filter { m in
            let cmd = m.command.lowercased()
            return !cmd.contains("grep") && !cmd.contains("defunct")
        }

        let cliProcess = validProcesses.first { m in
            let cmd = m.command.lowercased()
            return cmd.contains("kiro-cli") || cmd.contains("kiro_cli") || cmd.contains("@kiro/agent") || cmd.contains("tui.js")
        } ?? validProcesses.first

        if let proc = cliProcess {
            status.process = AgentProcessInfo(
                isRunning: true,
                pid: proc.pid,
                cpuPercent: proc.cpuPercent,
                command: proc.command
            )

            // Parse --model from command if specified
            if let modelRange = proc.command.range(of: "--model ") {
                let after = proc.command[modelRange.upperBound...]
                let modelName = after.components(separatedBy: " ").first ?? ""
                if !modelName.isEmpty {
                    status.model = formatModelName(modelName)
                }
            }
        } else {
            status.process = AgentProcessInfo(isRunning: false)
        }

        // 2. Model from settings or session if not already parsed
        let home = FileManager.default.homeDirectoryForCurrentUser
        if status.model.isEmpty || status.model == "Opus 5.5" {
            let settingsURL = home.appendingPathComponent(".kiro/settings/cli.json")
            if let data = try? Data(contentsOf: settingsURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let defaultModel = json["chat.defaultModel"] as? String {
                status.model = formatModelName(defaultModel)
            }
        }

        // 3. Inspect recent sessions in ~/.kiro/sessions/cli/ for session title
        let sessionsDir = home.appendingPathComponent(".kiro/sessions/cli")
        if let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            let sorted = jsonFiles.sorted { f1, f2 in
                let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

            if let latestSession = sorted.first,
               let data = try? Data(contentsOf: latestSession),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let title = json["title"] as? String, !title.isEmpty {
                    status.sessionTitle = title
                }
                if status.model == "Opus 5.5",
                   let sessionState = json["session_state"] as? [String: Any],
                   let rts = sessionState["rts_model_state"] as? [String: Any],
                   let modelInfo = rts["model_info"] as? [String: Any],
                   let modelName = modelInfo["model_name"] as? String {
                    status.model = formatModelName(modelName)
                }
            }
        }

        // 4. Live telemetry collection with safe throttling & persistent disk cache
        let now = Date()
        var shouldFetch = false

        Self.lock.lock()
        if forceLive {
            if now.timeIntervalSince(Self.lastLiveFetchTime) >= 3.0 {
                shouldFetch = true
                Self.lastLiveFetchTime = now
            }
        } else if now.timeIntervalSince(Self.lastLiveFetchTime) >= 60.0 {
            shouldFetch = true
            Self.lastLiveFetchTime = now
        }
        let inMemCached = Self.cachedStatus
        Self.lock.unlock()

        if shouldFetch, let live = fetchLiveQuota() {
            Self.lock.lock()
            Self.cachedStatus = live
            Self.lock.unlock()

            saveDiskCache(live)
            applyQuota(live, to: &status)
            return status
        }

        // Fallback A: in-memory cache
        if let cached = inMemCached {
            applyQuota(cached, to: &status)
            return status
        }

        // Fallback B: persistent disk cache
        if let diskCache = loadDiskCache() {
            applyDiskCache(diskCache, to: &status)
            return status
        }

        return status
    }

    // MARK: - Live Quota Fetch

    private func fetchLiveQuota() -> KiroStatus? {
        guard var creds = readCredentials() else { return nil }

        // If access token is expired or expiring in < 60s, refresh it
        if let exp = creds.expiresAt, exp.timeIntervalSince(Date()) < 60.0, let refresh = creds.refreshToken {
            if let refreshed = refreshSocialToken(refreshToken: refresh) {
                creds.token = refreshed.accessToken
                creds.expiresAt = refreshed.expiresAt
                if !refreshed.profileArn.isEmpty {
                    creds.profileArn = refreshed.profileArn
                }
                persistRefreshedToken(key: creds.key, accessToken: refreshed.accessToken, expiresAt: refreshed.expiresAt, refreshToken: refreshed.refreshToken)
            }
        }

        guard !creds.token.isEmpty, !creds.profileArn.isEmpty else { return nil }

        var liveResult = performGetUsageLimits(token: creds.token, profileArn: creds.profileArn)

        // If unauthorized/expired, attempt one token refresh and retry
        if liveResult == nil, let refresh = creds.refreshToken {
            if let refreshed = refreshSocialToken(refreshToken: refresh) {
                creds.token = refreshed.accessToken
                creds.expiresAt = refreshed.expiresAt
                if !refreshed.profileArn.isEmpty {
                    creds.profileArn = refreshed.profileArn
                }
                persistRefreshedToken(key: creds.key, accessToken: refreshed.accessToken, expiresAt: refreshed.expiresAt, refreshToken: refreshed.refreshToken)
                liveResult = performGetUsageLimits(token: creds.token, profileArn: creds.profileArn)
            }
        }

        guard let res = liveResult else { return nil }

        var status = KiroStatus()
        status.planTier = res.planTier
        status.creditsUsed = res.creditsUsed
        status.creditsTotal = res.creditsTotal
        status.creditsRemainingPct = res.creditsRemainingPct
        status.resetsOnString = res.resetsOnString
        status.resetsAt = res.resetsAt
        return status
    }

    private func performGetUsageLimits(token: String, profileArn: String) -> LiveUsageLimitsResult? {
        guard let url = URL(string: "https://codewhisperer.us-east-1.amazonaws.com") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-amz-json-1.0", forHTTPHeaderField: "Content-Type")
        req.setValue("AmazonCodeWhispererService.GetUsageLimits", forHTTPHeaderField: "x-amz-target")
        req.timeoutInterval = 4.0
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["profileArn": profileArn])

        let sema = DispatchSemaphore(value: 0)
        var result: LiveUsageLimitsResult? = nil

        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { sema.signal() }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var planTier = "KIRO STUDENT"
            if let subInfo = json["subscriptionInfo"] as? [String: Any],
               let title = subInfo["subscriptionTitle"] as? String, !title.isEmpty {
                planTier = title
            }

            var used: Double = 0.0
            var total: Double = 1000.0
            var resetDate: Date? = nil

            if let breakdowns = json["usageBreakdownList"] as? [[String: Any]] {
                let creditItem = breakdowns.first { ($0["resourceType"] as? String) == "CREDIT" } ?? breakdowns.first
                if let item = creditItem {
                    used = (item["currentUsageWithPrecision"] as? NSNumber)?.doubleValue
                        ?? (item["currentUsage"] as? NSNumber)?.doubleValue
                        ?? 0.0
                    total = (item["usageLimitWithPrecision"] as? NSNumber)?.doubleValue
                        ?? (item["usageLimit"] as? NSNumber)?.doubleValue
                        ?? 1000.0
                    if let nextReset = (item["nextDateReset"] as? NSNumber)?.doubleValue {
                        resetDate = Date(timeIntervalSince1970: nextReset)
                    }
                }
            }

            if resetDate == nil, let nextReset = (json["nextDateReset"] as? NSNumber)?.doubleValue {
                resetDate = Date(timeIntervalSince1970: nextReset)
            }

            let remPct = total > 0 ? max(0.0, min(100.0, ((total - used) / total) * 100.0)) : 0.0

            let resetsOn: String
            if let date = resetDate {
                resetsOn = ClaudeStatus.formatRelativeCountdown(date)
            } else {
                resetsOn = "Resets Dec 1"
            }

            result = LiveUsageLimitsResult(
                planTier: planTier,
                creditsUsed: used,
                creditsTotal: total,
                creditsRemainingPct: remPct,
                resetsOnString: resetsOn,
                resetsAt: resetDate
            )
        }.resume()

        _ = sema.wait(timeout: .now() + 4.5)
        return result
    }

    private func refreshSocialToken(refreshToken: String) -> (accessToken: String, profileArn: String, expiresAt: Date, refreshToken: String)? {
        guard let url = URL(string: "https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5.0
        guard let httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken]) else { return nil }
        req.httpBody = httpBody

        let sema = DispatchSemaphore(value: 0)
        var result: (String, String, Date, String)? = nil

        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { sema.signal() }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["accessToken"] as? String,
                  let profileArn = json["profileArn"] as? String else { return }

            let expiresIn = (json["expiresIn"] as? NSNumber)?.doubleValue ?? 3600.0
            let newExpiresAt = Date().addingTimeInterval(expiresIn)
            let newRefresh = (json["refreshToken"] as? String) ?? refreshToken
            result = (newAccess, profileArn, newExpiresAt, newRefresh)
        }.resume()

        _ = sema.wait(timeout: .now() + 5.5)
        return result
    }

    private func readCredentials() -> KiroCredentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent("Library/Application Support/kiro-cli/data.sqlite3").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-readonly", "-json", dbPath, "SELECT key, value FROM auth_kv WHERE key IN ('kirocli:social:token', 'kirocli:odic:token', 'kirocli:external-idp:token');"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

            for row in rows {
                guard let key = row["key"] as? String,
                      let valStr = row["value"] as? String,
                      let valData = valStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: valData) as? [String: Any],
                      let token = (json["access_token"] as? String) ?? (json["accessToken"] as? String) else {
                    continue
                }

                var profileArn = (json["profile_arn"] as? String) ?? (json["profileArn"] as? String) ?? ""
                let refreshToken = (json["refresh_token"] as? String) ?? (json["refreshToken"] as? String)
                var expiresAt: Date? = nil
                if let expStr = (json["expires_at"] as? String) ?? (json["expiresAt"] as? String) {
                    expiresAt = parseDate(expStr)
                }

                if profileArn.isEmpty {
                    profileArn = readProfileArnFromState(dbPath: dbPath) ?? ""
                }

                return KiroCredentials(token: token, profileArn: profileArn, expiresAt: expiresAt, refreshToken: refreshToken, key: key)
            }
        } catch {
            return nil
        }

        return nil
    }

    private func readProfileArnFromState(dbPath: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-readonly", "-json", dbPath, "SELECT value FROM state WHERE key='api.codewhisperer.profile';"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let valStr = first["value"] as? String,
              let valData = valStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: valData) as? [String: Any],
              let arn = json["arn"] as? String else { return nil }

        return arn
    }

    private func persistRefreshedToken(key: String, accessToken: String, expiresAt: Date, refreshToken: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent("Library/Application Support/kiro-cli/data.sqlite3").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        let iso = ISO8601DateFormatter().string(from: expiresAt)
        let sql = "UPDATE auth_kv SET value = json_set(value, '$.access_token', '\(accessToken)', '$.expires_at', '\(iso)', '$.refresh_token', '\(refreshToken)') WHERE key='\(key)';"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [dbPath, sql]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: - Disk Cache & Helpers

    private func applyQuota(_ source: KiroStatus, to target: inout KiroStatus) {
        target.planTier = source.planTier
        target.creditsUsed = source.creditsUsed
        target.creditsTotal = source.creditsTotal
        target.creditsRemainingPct = source.creditsRemainingPct
        target.resetsAt = source.resetsAt

        if let resetsAt = source.resetsAt {
            target.resetsOnString = ClaudeStatus.formatRelativeCountdown(resetsAt)
        } else {
            target.resetsOnString = source.resetsOnString
        }
    }

    private func applyDiskCache(_ cache: KiroDiskCache, to target: inout KiroStatus) {
        target.planTier = cache.planTier
        target.creditsTotal = cache.creditsTotal

        if let resetTs = cache.resetTimestamp {
            let resetDate = Date(timeIntervalSince1970: resetTs)
            target.resetsAt = resetDate

            if resetDate.timeIntervalSince(Date()) <= 0 {
                // Monthly cycle replenished!
                target.creditsUsed = 0.0
                target.creditsRemainingPct = 100.0
                target.resetsOnString = "Resetting"
            } else {
                target.creditsUsed = cache.creditsUsed
                target.creditsRemainingPct = cache.creditsRemainingPct
                target.resetsOnString = ClaudeStatus.formatRelativeCountdown(resetDate)
            }
        } else {
            target.creditsUsed = cache.creditsUsed
            target.creditsRemainingPct = cache.creditsRemainingPct
            target.resetsOnString = cache.resetsOnString
        }
    }

    private func saveDiskCache(_ status: KiroStatus) {
        let url = Self.cacheFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let record = KiroDiskCache(
            planTier: status.planTier,
            creditsUsed: status.creditsUsed,
            creditsTotal: status.creditsTotal,
            creditsRemainingPct: status.creditsRemainingPct,
            resetsOnString: status.resetsOnString,
            resetTimestamp: status.resetsAt?.timeIntervalSince1970,
            updatedAt: Date()
        )

        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadDiskCache() -> KiroDiskCache? {
        let url = Self.cacheFileURL
        guard let data = try? Data(contentsOf: url),
          let cache = try? JSONDecoder().decode(KiroDiskCache.self, from: data) else {
            return nil
        }
        return cache
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: string) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        if let d = df.date(from: string) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return df.date(from: string)
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("opus") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("sonnet") {
            return "Sonnet 4.6"
        } else if raw.localizedCaseInsensitiveContains("haiku") {
            return "Haiku 5.5"
        } else {
            return raw
        }
    }
}
