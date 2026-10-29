import Foundation
import Testing

@testable import SpaceTabsCore

private func logDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsLogs-\(UUID())")
}

private func records(_ url: URL) throws -> [[String: Any]] {
    try Data(contentsOf: url).split(separator: 0x0A).map {
        try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
    }
}

@Test func diagnosticHistoryRotatesPrivateFilesAndSurvivesANewLogger() throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(directory: directory, name: "test", maximumBytes: 4096)
    for index in 0..<30 {
        log.record("test.error", details: ["index": String(index), "message": String(repeating: "x", count: 250)])
    }
    log.flush()
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == [
            "test-previous.jsonl", "test.jsonl",
        ])
    for name in ["test.jsonl", "test-previous.jsonl"] {
        let url = directory.appendingPathComponent(name)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.size] as? NSNumber)?.intValue ?? 99999 <= 4096)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try !records(url).isEmpty)
    }
    let second = DiagnosticLog(directory: directory, name: "test", maximumBytes: 4096)
    second.failure(
        NSError(domain: "SyntheticAX", code: -25204), operation: "place", file: "Test.swift", function: "place()",
        line: 42)
    second.flush()
    let last = try #require(records(second.url).last)
    #expect(last["event"] as? String == "operation.error")
    #expect(last["source"] as? String == "Test.swift:42 place()")
    let details = try #require(last["details"] as? [String: String])
    #expect(details["errorDomain"] == "SyntheticAX")
    #expect(details["errorCode"] == "-25204")
}

@Test func diagnosticLoggerRejectsSymlinksAndDoesNotAlterTheirTargets() throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target")
    try LocalConfigurationFile.write(Data("keep me".utf8), to: target)
    let log = DiagnosticLog(directory: directory, name: "test")
    try FileManager.default.createSymbolicLink(at: log.url, withDestinationURL: target)
    log.record("test.error")
    log.flush()
    #expect(try Data(contentsOf: target) == Data("keep me".utf8))
}

@Test func diagnosticSessionReportsUncleanEndWithoutClaimingACrash() throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(directory: directory, name: "test")
    log.start()
    log.record("test.failure")
    log.flush()
    let next = DiagnosticLog(directory: directory, name: "test")
    next.start()
    next.record("session.end")
    next.flush()
    let third = DiagnosticLog(directory: directory, name: "test")
    third.start()
    third.flush()
    let warnings = try records(log.url).filter { $0["event"] as? String == "session.previous-not-closed" }
    #expect(warnings.count == 1)
    let details = try #require(warnings.first?["details"] as? [String: String])
    #expect(details["lastEvent"] == "test.failure")
}

@Test func diagnosticOperationCompletesOnceAndRetainsItsSource() throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(directory: directory, name: "test")
    let operation = DiagnosticOperation("focus", log: log, file: "Selection.swift", function: "select()", line: 12)
    operation.reportSlowIfNeeded()
    operation.reportSlowIfNeeded()
    operation.finish()
    operation.finish()
    operation.reportSlowIfNeeded()
    log.flush()
    let entries = try records(log.url)
    #expect(entries.map { $0["event"] as? String } == ["operation.begin", "operation.slow", "operation.end"])
    #expect(entries.allSatisfy { $0["source"] as? String == "Selection.swift:12 select()" })
    let begin = try #require(entries.first?["details"] as? [String: String])
    let end = try #require(entries.last?["details"] as? [String: String])
    #expect(begin["id"] == end["id"])
    #expect(Double(end["seconds"] ?? "") != nil)
}

@Test func responsivenessReportsOnceRecoversAndDoesNotFloodMainQueue() {
    var state = ResponsivenessState()
    #expect(state.tick(at: 0).sendHeartbeat)
    for time in [1.0, 2.0] {
        let tick = state.tick(at: time)
        #expect(!tick.sendHeartbeat && tick.event == nil)
    }
    #expect(state.tick(at: 3).event == .stalled)
    #expect(state.tick(at: 4).event == nil)
    #expect(state.acknowledge(at: 4.5) == .recovered(4.5))
    #expect(state.tick(at: 5).sendHeartbeat)
    #expect(state.acknowledge(at: 5.1) == nil)
}

@Test func responsivenessResetsAfterSleepOrMonitorSchedulingGaps() {
    var state = ResponsivenessState()
    #expect(state.tick(at: 0).sendHeartbeat)
    let resumed = state.tick(at: 100)
    #expect(resumed.sendHeartbeat && resumed.event == nil)
    #expect(state.acknowledge(at: 100.1) == nil)
    #expect(state.tick(at: 101).sendHeartbeat)
}

@Test func diagnosticCopyReadsBothProcessesWithoutLiveManagerRequests() async throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = DiagnosticLog(directory: directory, name: "manager")
    let settings = DiagnosticLog(directory: directory, name: "settings")
    let window = UUID()
    manager.failure(WindowOperationError(message: "Synthetic rejection", windowID: window), operation: "resize")
    settings.record("settings.connection-error")
    manager.flush()
    settings.flush()
    let history = await settings.history()
    #expect(history.contains("manager.jsonl"))
    #expect(history.contains("settings.jsonl"))
    #expect(history.contains("Synthetic rejection"))
    #expect(history.contains(window.uuidString))
    #expect(history.contains("settings.connection-error"))
}

@Test func disabledDiagnosticLoggerDoesNotCreateUserFiles() {
    let directory = logDirectory()
    let log = DiagnosticLog(directory: directory, name: "test", enabled: false)
    log.record("ignored")
    log.flush()
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func cleanShutdownFollowsConcurrentRecordsAndRejectsLateCallbacks() throws {
    let directory = logDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(directory: directory, name: "test")
    DispatchQueue.concurrentPerform(iterations: 32) { index in
        log.record("test.concurrent", details: ["index": String(index)])
    }
    log.record("session.end")
    log.record("late.callback")
    log.flush()
    let entries = try records(log.url)
    #expect(entries.count == 33)
    #expect(entries.last?["event"] as? String == "session.end")
}
