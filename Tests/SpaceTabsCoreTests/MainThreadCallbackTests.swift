import Foundation
import Testing

@testable import SpaceTabsCore

private func isMainThreadForCallbackTest() -> Bool { Thread.isMainThread }

@MainActor @Test func finderStyleCallbackAlreadyOnMainReturnsWithoutRedispatching() {
    let onMain = MainThreadCallback.call { Thread.isMainThread }
    #expect(onMain)
}

@MainActor @Test func finderStyleWorkerCallbackBuildsItsResultOnMainWithoutAnIsolationTrap() async {
    let result = await Task.detached {
        let arrivedOnWorker = !isMainThreadForCallbackTest()
        let ranOnMain = MainThreadCallback.call { Thread.isMainThread }
        return (arrivedOnWorker, ranOnMain)
    }.value
    #expect(result.0)
    #expect(result.1)
}
