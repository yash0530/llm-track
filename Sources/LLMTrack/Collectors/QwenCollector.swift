import Foundation
import Darwin

public final class QwenCollector: Sendable {
    public init() {}

    public func collect() -> QwenStatus {
        var status = QwenStatus()

        // 1. Check ports used by llm-serve (8089 backend, 8790 proxy) and standard LM Studio (1234)
        let is8089Open = checkPort(8089)
        let is8790Open = checkPort(8790)
        let is1234Open = checkPort(1234)

        // 2. Check pidfiles managed by llm-serve
        let home = FileManager.default.homeDirectoryForCurrentUser
        let serverPidURL = home.appendingPathComponent(".local/state/local-llm/server.pid")
        let proxyPidURL = home.appendingPathComponent(".local/state/local-llm/proxy.pid")
        let hasServerPidRunning = isPidFileRunning(serverPidURL)
        let hasProxyPidRunning = isPidFileRunning(proxyPidURL)

        // 3. Check running processes matching splash, llm-proxy, or Qwen
        let matches = ProcessHelper.findProcesses(matching: [
            "splash serve-native",
            "server.server",
            "Qwen3.8-27B",
            "llm-proxy.mjs"
        ])
        let hasProcessRunning = !matches.isEmpty

        let isRunning = is8089Open || is8790Open || is1234Open || hasServerPidRunning || hasProxyPidRunning || hasProcessRunning
        status.isServerRunning = isRunning
        status.modelName = "Qwen 3.8 27B"
        status.serverPort = is8089Open ? 8089 : (is1234Open ? 1234 : 8790)

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

        var tv = timeval(tv_sec: 0, tv_usec: 120_000) // 120ms timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func isPidFileRunning(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str), pid > 0 else {
            return false
        }
        return kill(pid, 0) == 0
    }

    public static func startServerSync() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "export PATH=\"$HOME/.local/bin:$HOME/.lmstudio/bin:$PATH\"; /Users/yash/.local/bin/llm-serve start >/tmp/llm_serve_start.log 2>&1"]
        try? process.run()
        process.waitUntilExit()
    }

    public static func stopServerSync() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "export PATH=\"$HOME/.local/bin:$HOME/.lmstudio/bin:$PATH\"; /Users/yash/.local/bin/llm-serve stop >/tmp/llm_serve_stop.log 2>&1"]
        try? process.run()
        process.waitUntilExit()
    }

    public static func startServer() {
        startServerSync()
    }

    public static func stopServer() {
        stopServerSync()
    }
}
