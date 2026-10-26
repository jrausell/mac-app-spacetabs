import Testing

@testable import SpaceTabsCore

@Test func savedWindowsAreNotReportedMissingWithoutPermission() {
    let status = WindowDiscoveryStatus(trusted: false, searching: false, completed: false)
    #expect(status == .permissionRequired)
    #expect(!status.canReportMatches)
}

@Test func permissionGrantDoesNotImplyWindowsWereAlreadySearched() {
    let status = WindowDiscoveryStatus(trusted: true, searching: false, completed: false)
    #expect(status == .waiting)
    #expect(!status.canReportMatches)
}

@Test func inFlightSearchDoesNotReportZeroMatchesFromPreviousState() {
    let status = WindowDiscoveryStatus(trusted: true, searching: true, completed: true)
    #expect(status == .searching)
    #expect(!status.canReportMatches)
}

@Test func restorationIsOnlyEvaluatedAfterAuthorizedDiscovery() {
    let ready = WindowDiscoveryStatus(trusted: true, searching: false, completed: true)
    #expect(ready == .ready && ready.canReportMatches)
    let revoked = WindowDiscoveryStatus(trusted: false, searching: false, completed: true)
    #expect(revoked == .permissionRequired && !revoked.canReportMatches)
}
