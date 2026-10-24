import Foundation
import Darwin

public final class QwenCollector: Sendable {
    public init() {}

    public func collect() -> QwenStatus {
        var status = QwenStatus()

        // 1. Check if port 1234 is responding using quick socket probe
        let isPortOpen = checkPort(1234)
        status.isServerRunning = isPortOpen

        // 2. Static configuration discovered for user's installed model
        status.modelName = "qwen3.8-27b-splash"
        status.parameterSize = "27B"
        status.arch = "qwen3_5"
        status.diskSize = "17.4 GB"
        status.device = "Metal GPU"
        status.serverPort = 1234

        return status
    }

    private func checkPort(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        var tv = timeval(tv_sec: 0, tv_usec: 150_000) // 150ms timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    public static func startServer() {
        let process = Process()
        let lmsPath = "/Users/yash/.lmstudio/bin/lms"
        if FileManager.default.fileExists(atPath: lmsPath) {
            process.executableURL = URL(fileURLWithPath: lmsPath)
            process.arguments = ["server", "start"]
            try? process.run()
        }
    }

    public static func stopServer() {
        let process = Process()
        let lmsPath = "/Users/yash/.lmstudio/bin/lms"
        if FileManager.default.fileExists(atPath: lmsPath) {
            process.executableURL = URL(fileURLWithPath: lmsPath)
            process.arguments = ["server", "stop"]
            try? process.run()
        }
    }
}
