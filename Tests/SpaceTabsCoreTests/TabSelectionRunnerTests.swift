import Foundation
import Testing

@testable import SpaceTabsCore

private actor SelectionLatch {
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        opened = true
        let continuations = waiting
        waiting.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

@Test @MainActor func aBlockedSelectionKeepsTheLastClickInsteadOfDroppingAllFurtherClicks() async {
    let runner = TabSelectionRunner()
    let entered = SelectionLatch()
    let unblock = SelectionLatch()
    var selected: [Int] = []
    var finished: [Int] = []
    runner.submit {
        await entered.open()
        await unblock.wait()
        if !Task.isCancelled { selected.append(1) }
    } onComplete: {
        finished.append(1)
    }
    await entered.wait()
    #expect(runner.isPending)
    runner.submit {
        selected.append(2)
    } onComplete: {
        finished.append(2)
    }
    runner.submit {
        selected.append(3)
    } onComplete: {
        #expect(!runner.isPending)
        finished.append(3)
    }
    #expect(runner.isPending)
    await unblock.open()
    await runner.wait()
    #expect(selected == [3])
    #expect(finished == [3])
    #expect(!runner.isPending)
}

@Test @MainActor func settingsCancellationDoesNotLeaveTheNextSelectionBlocked() async {
    let runner = TabSelectionRunner()
    let entered = SelectionLatch()
    let unblock = SelectionLatch()
    var selected: [Int] = []
    runner.submit {
        await entered.open()
        await unblock.wait()
        if !Task.isCancelled { selected.append(1) }
    }
    await entered.wait()
    runner.cancel()
    #expect(!runner.isPending)
    runner.submit { selected.append(2) }
    await unblock.open()
    await runner.wait()
    #expect(selected == [2])
    #expect(!runner.isPending)
}

@Test @MainActor func completedOrFailedFocusDoesNotPoisonFutureRequests() async {
    let runner = TabSelectionRunner()
    var selected: [Int] = []
    runner.submit {
        do { throw WindowOperationError(message: "AXFrontmost rejected") } catch {}
    }
    await runner.wait()
    #expect(!runner.isPending)
    runner.submit { selected.append(2) }
    await runner.wait()
    #expect(selected == [2])
    #expect(!runner.isPending)
}
