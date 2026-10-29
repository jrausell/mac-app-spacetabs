import Foundation
import SpaceTabsCore
import Testing

private let chord: UInt32 = 4096 | 2048 | 256

@Test func modifierTapFiresOnceAfterCompleteReleaseInDifferentOrders() {
    for sequence: [UInt32] in [
        [4096, 6144, chord, 2304, 256, 0],
        [256, 2304, chord, 6144, 4096, 0],
    ] {
        var state = ModifierTapState()
        let results = sequence.compactMap { state.update(modifiers: $0, targets: [chord]) }
        #expect(results == [chord])
        #expect(state.update(modifiers: 0, targets: [chord]) == nil)
    }
}

@Test func interruptedOrExtendedModifierChordsNeverFireAndNextCleanTapWorks() {
    for interruption: UInt32 in [chord, chord | 512] {
        var state = ModifierTapState()
        #expect(state.update(modifiers: chord, targets: [chord]) == nil)
        #expect(state.update(modifiers: interruption, targets: [chord], interrupted: interruption == chord) == nil)
        #expect(state.update(modifiers: chord, targets: [chord]) == nil)
        #expect(state.update(modifiers: 0, targets: [chord]) == nil)
        #expect(state.update(modifiers: chord, targets: [chord]) == nil)
        #expect(state.update(modifiers: 0, targets: [chord]) == chord)
    }
}

@Test func incompleteChordsAndModifiersPressedBeforeMonitoringDoNotFire() {
    var state = ModifierTapState()
    #expect(state.update(modifiers: 4096, targets: [chord]) == nil)
    #expect(state.update(modifiers: 0, targets: [chord]) == nil)
    state.cancel()
    #expect(state.update(modifiers: chord, targets: [chord]) == nil)
    #expect(state.update(modifiers: 0, targets: [chord]) == nil)
    #expect(state.update(modifiers: chord | 512, targets: [chord]) == nil)
    #expect(state.update(modifiers: chord, targets: [chord]) == nil)
    #expect(state.update(modifiers: 0, targets: [chord]) == nil)
}

@Test func modifierOnlyBindingsRoundTripAndRejectSingleModifiersOrUnknownKeys() throws {
    let binding = ShortcutBinding(key: ShortcutBinding.modifiersOnlyKey, modifiers: chord)
    #expect(binding.isValid)
    #expect(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding)) == binding)
    #expect(!ShortcutBinding(key: ShortcutBinding.modifiersOnlyKey, modifiers: 256).isValid)
    #expect(!ShortcutBinding(key: 128, modifiers: chord).isValid)
    #expect(!ShortcutBinding(key: ShortcutBinding.modifiersOnlyKey, modifiers: chord | 1).isValid)
}

@Test func longerConfiguredModifierChordWinsOverItsPrefix() {
    var state = ModifierTapState()
    let shorter: UInt32 = 4096 | 256
    #expect(state.update(modifiers: shorter, targets: [shorter, chord]) == nil)
    #expect(state.update(modifiers: chord, targets: [shorter, chord]) == nil)
    #expect(state.update(modifiers: shorter, targets: [shorter, chord]) == nil)
    #expect(state.update(modifiers: 0, targets: [shorter, chord]) == chord)
}
