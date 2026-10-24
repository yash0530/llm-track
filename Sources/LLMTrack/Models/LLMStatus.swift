import Foundation

public struct AgentProcessInfo: Sendable, Equatable {
    public var isRunning: Bool
    public var pid: Int?
    public var cpuPercent: Double?
    public var command: String?
    public var activeDirectory: String?

    public init(isRunning: Bool = false, pid: Int? = nil, cpuPercent: Double? = nil, command: String? = nil, activeDirectory: String? = nil) {
        self.isRunning = isRunning
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.command = command
        self.activeDirectory = activeDirectory
    }
}

public struct ClaudeStatus: Sendable, Equatable {
    public var process: AgentProcessInfo
    public var model: String
    public var fiveHourUsedPct: Double?
    public var fiveHourRemainingPct: Double?
    public var fiveHourResetsAt: Date?
    public var resetTimeString: String?
    public var sevenDayUsedPct: Double?
    public var sevenDayRemainingPct: Double?
    public var sevenDayResetsAt: Date?
    public var sevenDayResetsInString: String?
    public var remainingDollars: Double?
    public var lastUpdated: Date?

    public var isExhausted: Bool {
        if let rem = fiveHourRemainingPct {
            return rem <= 0.001
        }
        if let used = fiveHourUsedPct {
            return used >= 99.99
        }
        return false
    }

    public var resetsInString: String? {
        if let resetsAt = fiveHourResetsAt {
            return Self.formatRelativeCountdown(resetsAt)
        }
        if let resetStr = resetTimeString, !resetStr.isEmpty {
            return resetStr
        }
        return nil
    }

    public var weeklyResetsInString: String? {
        if let resetsAt = sevenDayResetsAt {
            return Self.formatRelativeCountdown(resetsAt)
        }
        if let resetStr = sevenDayResetsInString, !resetStr.isEmpty {
            return resetStr
        }
        return nil
    }

    public static func formatRelativeCountdown(_ targetDate: Date) -> String {
        let diff = targetDate.timeIntervalSince(Date())
        if diff <= 0 { return "Resetting" }
        let totalMinutes = Int(diff) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(max(1, minutes))m"
        }
    }

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Opus 5.5",
        fiveHourUsedPct: Double? = nil,
        fiveHourRemainingPct: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        resetTimeString: String? = nil,
        sevenDayUsedPct: Double? = nil,
        sevenDayRemainingPct: Double? = nil,
        sevenDayResetsAt: Date? = nil,
        sevenDayResetsInString: String? = nil,
        remainingDollars: Double? = nil,
        lastUpdated: Date? = nil
    ) {
        self.process = process
        self.model = model
        self.fiveHourUsedPct = fiveHourUsedPct
        self.fiveHourRemainingPct = fiveHourRemainingPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.resetTimeString = resetTimeString
        self.sevenDayUsedPct = sevenDayUsedPct
        self.sevenDayRemainingPct = sevenDayRemainingPct
        self.sevenDayResetsAt = sevenDayResetsAt
        self.sevenDayResetsInString = sevenDayResetsInString
        self.remainingDollars = remainingDollars
        self.lastUpdated = lastUpdated
    }
}

public struct AGYStatus: Sendable, Equatable {
    public var process: AgentProcessInfo
    public var model: String
    public var planTier: String
    public var geminiWeeklyRemainingPct: Double
    public var geminiWeeklyResetString: String
    public var geminiFiveHourRemainingPct: Double
    public var geminiFiveHourResetString: String
    public var claudeGptWeeklyRemainingPct: Double
    public var claudeGptFiveHourRemainingPct: Double
    public var activeDirectory: String?
    public var isLanguageServerRunning: Bool

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Gemini 3.8 Flash High",
        planTier: String = "Google AI Pro",
        geminiWeeklyRemainingPct: Double = 88.0,
        geminiWeeklyResetString: String = "Resets in 6d 10h",
        geminiFiveHourRemainingPct: Double = 88.0,
        geminiFiveHourResetString: String = "Resets in 4h 8m",
        claudeGptWeeklyRemainingPct: Double = 100.0,
        claudeGptFiveHourRemainingPct: Double = 100.0,
        activeDirectory: String? = nil,
        isLanguageServerRunning: Bool = false
    ) {
        self.process = process
        self.model = model
        self.planTier = planTier
        self.geminiWeeklyRemainingPct = geminiWeeklyRemainingPct
        self.geminiWeeklyResetString = geminiWeeklyResetString
        self.geminiFiveHourRemainingPct = geminiFiveHourRemainingPct
        self.geminiFiveHourResetString = geminiFiveHourResetString
        self.claudeGptWeeklyRemainingPct = claudeGptWeeklyRemainingPct
        self.claudeGptFiveHourRemainingPct = claudeGptFiveHourRemainingPct
        self.activeDirectory = activeDirectory
        self.isLanguageServerRunning = isLanguageServerRunning
    }
}

public struct KiroStatus: Sendable, Equatable {
    public var process: AgentProcessInfo
    public var model: String
    public var planTier: String
    public var creditsUsed: Double
    public var creditsTotal: Double
    public var creditsRemainingPct: Double
    public var resetsOnString: String
    public var sessionTitle: String?

    public var isExhausted: Bool {
        return creditsRemainingPct <= 0.001 || creditsUsed >= creditsTotal
    }

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Opus 5.5 (Kiro)",
        planTier: String = "KIRO STUDENT",
        creditsUsed: Double = 1000.00,
        creditsTotal: Double = 1000.00,
        creditsRemainingPct: Double = 0.0,
        resetsOnString: String = "Resets on 2026-11-01",
        sessionTitle: String? = nil
    ) {
        self.process = process
        self.model = model
        self.planTier = planTier
        self.creditsUsed = creditsUsed
        self.creditsTotal = creditsTotal
        self.creditsRemainingPct = creditsRemainingPct
        self.resetsOnString = resetsOnString
        self.sessionTitle = sessionTitle
    }
}

public struct QwenStatus: Sendable, Equatable {
    public var isServerRunning: Bool
    public var serverPort: Int
    public var modelName: String
    public var parameterSize: String
    public var arch: String
    public var diskSize: String
    public var device: String

    public init(
        isServerRunning: Bool = false,
        serverPort: Int = 1234,
        modelName: String = "qwen3.8-27b-splash",
        parameterSize: String = "27B",
        arch: String = "qwen3_5",
        diskSize: String = "17.4 GB",
        device: String = "Metal GPU"
    ) {
        self.isServerRunning = isServerRunning
        self.serverPort = serverPort
        self.modelName = modelName
        self.parameterSize = parameterSize
        self.arch = arch
        self.diskSize = diskSize
        self.device = device
    }
}

public struct LLMOverallTelemetry: Sendable, Equatable {
    public var claude: ClaudeStatus
    public var agy: AGYStatus
    public var kiro: KiroStatus
    public var qwen: QwenStatus
    public var lastUpdated: Date

    public var activeRunningCount: Int {
        var count = 0
        if claude.process.isRunning { count += 1 }
        if agy.process.isRunning { count += 1 }
        if kiro.process.isRunning { count += 1 }
        if qwen.isServerRunning { count += 1 }
        return count
    }

    public init(
        claude: ClaudeStatus = ClaudeStatus(),
        agy: AGYStatus = AGYStatus(),
        kiro: KiroStatus = KiroStatus(),
        qwen: QwenStatus = QwenStatus(),
        lastUpdated: Date = Date()
    ) {
        self.claude = claude
        self.agy = agy
        self.kiro = kiro
        self.qwen = qwen
        self.lastUpdated = lastUpdated
    }
}
