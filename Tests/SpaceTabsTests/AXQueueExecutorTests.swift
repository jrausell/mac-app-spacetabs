import Foundation
import Testing

@testable import SpaceTabs

private actor ProcessQueueProbe {
    nonisolated let executor = AXQueueExecutor(label: "dev.spacetabs.test.\(UUID())")
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var commands: [Int] = []
    func block(started: AsyncStream<Bool>.Continuation, release: DispatchSemaphore) {
        started.yield(!Thread.isMainThread)
        _ = release.wait(timeout: .now() + 2)
        commands.append(0)
    }
    func command(_ value: Int) -> [Int] {
        commands.append(value)
        return commands
    }
}

@Test func blockedAXProcessQueueLeavesAnotherProcessResponsiveAndKeepsItsOwnOrder() async {
    let slow = ProcessQueueProbe()
    let fast = ProcessQueueProbe()
    let release = DispatchSemaphore(value: 0)
    let (events, started) = AsyncStream<Bool>.makeStream()
    let blocked = Task { await slow.block(started: started, release: release) }
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() == true)
    #expect(await fast.command(1) == [1])
    #expect(await fast.command(2) == [1, 2])
    release.signal()
    await blocked.value
    #expect(await slow.command(3) == [0, 3])
    started.finish()
}
