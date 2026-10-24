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
    public var sevenDayUsedPct: Double?
    public var sevenDayRemainingPct: Double?
    public var remainingDollars: Double?
    public var lastUpdated: Date?

    public var resetsInString: String? {
        guard let resetsAt = fiveHourResetsAt else { return nil }
        let diff = resetsAt.timeIntervalSince(Date())
        if diff <= 0 { return "Resetting now" }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Opus 4.5",
        fiveHourUsedPct: Double? = nil,
        fiveHourRemainingPct: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayUsedPct: Double? = nil,
        sevenDayRemainingPct: Double? = nil,
        remainingDollars: Double? = nil,
        lastUpdated: Date? = nil
    ) {
        self.process = process
        self.model = model
        self.fiveHourUsedPct = fiveHourUsedPct
        self.fiveHourRemainingPct = fiveHourRemainingPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUsedPct = sevenDayUsedPct
        self.sevenDayRemainingPct = sevenDayRemainingPct
        self.remainingDollars = remainingDollars
        self.lastUpdated = lastUpdated
    }
}

public struct AGYStatus: Sendable, Equatable {
    public var process: AgentProcessInfo
    public var model: String
    public var account: String?
    public var activeDirectory: String?
    public var contextUsedPct: Double?
    public var contextRemainingPct: Double?
    public var dailyRequestsUsedPct: Double?
    public var dailyRequestsRemainingPct: Double?
    public var isLanguageServerRunning: Bool

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Gemini 3.8 Flash High",
        account: String? = nil,
        activeDirectory: String? = nil,
        contextUsedPct: Double? = nil,
        contextRemainingPct: Double? = nil,
        dailyRequestsUsedPct: Double? = nil,
        dailyRequestsRemainingPct: Double? = nil,
        isLanguageServerRunning: Bool = false
    ) {
        self.process = process
        self.model = model
        self.account = account
        self.activeDirectory = activeDirectory
        self.contextUsedPct = contextUsedPct
        self.contextRemainingPct = contextRemainingPct
        self.dailyRequestsUsedPct = dailyRequestsUsedPct
        self.dailyRequestsRemainingPct = dailyRequestsRemainingPct
        self.isLanguageServerRunning = isLanguageServerRunning
    }
}

public struct KiroStatus: Sendable, Equatable {
    public var process: AgentProcessInfo
    public var model: String
    public var account: String?
    public var contextUsedPct: Double?
    public var contextRemainingPct: Double?
    public var sessionTitle: String?

    public init(
        process: AgentProcessInfo = AgentProcessInfo(),
        model: String = "Opus 5.5",
        account: String? = nil,
        contextUsedPct: Double? = nil,
        contextRemainingPct: Double? = nil,
        sessionTitle: String? = nil
    ) {
        self.process = process
        self.model = model
        self.account = account
        self.contextUsedPct = contextUsedPct
        self.contextRemainingPct = contextRemainingPct
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
