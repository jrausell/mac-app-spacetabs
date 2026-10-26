import Foundation
import Testing

@testable import SpaceTabsCore

private actor WorkProbe {
    var active = 0
    var maximum = 0
    var completed: [Int] = []
    var slowStarted = false
    private var releaseSlow: CheckedContinuation<Void, Never>?
    func run(_ id: Int) async -> Int {
        active += 1
        maximum = max(maximum, active)
        if id == 0 {
            slowStarted = true
            await withCheckedContinuation { releaseSlow = $0 }
        } else {
            await Task.yield()
        }
        active -= 1
        completed.append(id)
        return id
    }
    func release() {
        releaseSlow?.resume()
        releaseSlow = nil
    }
}

@Test func slowAppDiscoveryDoesNotPreventOtherWorkAndConcurrencyIsBounded() async {
    let probe = WorkProbe()
    let task = Task { await BoundedWorkPool.map(Array(0..<12), limit: 3) { await probe.run($0) } }
    for _ in 0..<100 {
        if await probe.completed.count == 11 { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(await probe.slowStarted)
    #expect(await probe.completed.count == 11)
    #expect(await probe.maximum <= 3)
    await probe.release()
    #expect(await task.value.sorted() == Array(0..<12))
}

@Test func emptyAndCancelledDiscoveryNeverStartWork() async {
    let probe = WorkProbe()
    #expect(await BoundedWorkPool.map([Int](), limit: 3) { await probe.run($0) }.isEmpty)
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return await BoundedWorkPool.map([1, 2, 3], limit: 3) { await probe.run($0) }
    }
    task.cancel()
    #expect(await task.value.isEmpty)
    #expect(await probe.completed.isEmpty)
}
