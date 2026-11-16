import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func desktopMenuBridgeRejectsLateAndReplayCommandsWithoutDispatchingWindowWork() throws {
    var token = UUID()
    var context = UUID()
    var ready = true
    var received: [DesktopMenuAction] = []
    let bridge = DesktopMenuBridge(
        url: nil,
        snapshot: { currentToken, currentContext in
            token = currentToken
            context = currentContext
            return DesktopMenuSnapshot(
                token: currentToken, context: currentContext, managerPID: 123, launchDate: nil,
                language: .english, ready: ready, workspaces: [], profiles: [])
        }, perform: { received.append($0.action) })
    bridge.start()
    let now = Date(timeIntervalSince1970: 1000)
    var request = DesktopMenuRequest(
        token: token, context: context, created: now, displayID: "display", action: .restore)
    let url = try #require(request.url())
    #expect(bridge.receive(url, now: now))
    #expect(!bridge.receive(url, now: now))
    #expect(received == [.restore])
    bridge.invalidateContext()
    request.nonce = UUID()
    #expect(!bridge.receive(try #require(request.url()), now: now))
    request.context = context
    ready = false
    #expect(!bridge.receive(try #require(request.url()), now: now))
    ready = true
    #expect(bridge.receive(try #require(request.url()), now: now))
    bridge.stop()
    request.nonce = UUID()
    #expect(!bridge.receive(try #require(request.url()), now: now))
    #expect(received == [.restore, .restore])
}

@MainActor @Test func desktopCloudStatusReachesSettingsWithoutTreatingUnknownAsLocal() throws {
    let manager = AppModel()
    manager.desktopMenuCloudManaged = true
    let snapshot = SettingsState(manager)
    let data = try JSONEncoder().encode(snapshot)
    let helper = AppModel()
    try JSONDecoder().decode(SettingsState.self, from: data).apply(to: helper)
    #expect(helper.desktopMenuCloudManaged == true)
    manager.desktopMenuCloudManaged = false
    SettingsState(manager).apply(to: helper)
    #expect(helper.desktopMenuCloudManaged == false)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "desktopMenuCloudManaged")
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    try JSONDecoder().decode(SettingsState.self, from: legacyData).apply(to: helper)
    #expect(helper.desktopMenuCloudManaged == nil)
}
