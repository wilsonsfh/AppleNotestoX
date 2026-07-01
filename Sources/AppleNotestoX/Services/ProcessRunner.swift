import Foundation

/// Thread-safe holder so a value read on one queue can be handed back to another.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()
    func set(_ d: Data) { lock.lock(); value = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

/// Runs child processes, draining stdout/stderr concurrently so a full OS pipe
/// buffer (~64 KB) can never deadlock `waitUntilExit()`.
enum ProcessRunner {
    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    static func run(executableURL: URL, arguments: [String]) async throws -> Result {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executableURL
                proc.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do { try proc.run() } catch { cont.resume(throwing: error); return }

                // Drain stdout and stderr concurrently while the child runs. Reading
                // only after waitUntilExit() deadlocks once output exceeds the ~64 KB
                // pipe buffer: the child blocks writing into a full pipe while we block
                // waiting for it to exit.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                proc.waitUntilExit()

                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errBox.get(), encoding: .utf8) ?? ""
                cont.resume(returning: Result(stdout: out, stderr: err, status: proc.terminationStatus))
            }
        }
    }
}
