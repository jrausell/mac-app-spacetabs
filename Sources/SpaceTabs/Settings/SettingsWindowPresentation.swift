import Foundation

/// Closing Settings is different from covering, hiding, or minimizing it.
@MainActor final class SettingsWindowPresentation {
    private(set) var isOpen = false
    private let present: () -> Void
    init(present: @escaping () -> Void) { self.present = present }
    func show() {
        isOpen = true
        present()
    }
    func showIfOpen() {
        guard isOpen else { return }
        present()
    }
    func closed() { isOpen = false }
}
