import XCTest
@testable import AppleNotestoX

/// Tests for the low-level process runner behind `AppleNotesService`.
///
/// Regression target: a Notes library's AppleScript listing easily exceeds the
/// OS pipe buffer (~64 KB). If the runner calls `Process.waitUntilExit()` before
/// draining stdout, the child blocks writing into a full pipe while the parent
/// blocks waiting for it to exit — a classic deadlock that froze the app at launch.
final class ProcessRunnerTests: XCTestCase {

    func testRunProcessHandlesLargeStdoutWithoutDeadlock() async throws {
        // ~512 KB — far beyond the ~64 KB pipe buffer that triggers the deadlock.
        let byteCount = 512 * 1024
        let result = try await withTimeout(seconds: 20) {
            try await AppleNotesService.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "yes 0123456789 | head -c \(byteCount)"]
            )
        }
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.utf8.count, byteCount)
    }

    func testRunProcessCapturesStderrAndNonzeroStatus() async throws {
        let result = try await withTimeout(seconds: 10) {
            try await AppleNotesService.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo boom 1>&2; exit 3"]
            )
        }
        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.stderr.contains("boom"), "stderr: \(result.stderr)")
        XCTAssertEqual(result.stdout, "")
    }

    func testRunProcessReturnsStdout() async throws {
        let result = try await withTimeout(seconds: 10) {
            try await AppleNotesService.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["hello"]
            )
        }
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "hello\n")
    }
}

// MARK: - Timeout helper

private struct TimeoutError: Error {}

/// Runs `op`, failing with `TimeoutError` if it does not finish in time.
/// Ensures a deadlocked runner fails the test instead of hanging the whole suite.
private func withTimeout<T: Sendable>(
    seconds: Double,
    _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
