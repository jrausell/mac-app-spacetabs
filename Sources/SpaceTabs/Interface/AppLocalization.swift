import Foundation
import Observation
import SpaceTabsCore

/// An observation dependency for views, without rebuilding their local UI state.
@MainActor @Observable final class AppLocalization {
    static let shared = AppLocalization()
    private(set) var language = L10n.language
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .spaceTabsLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.language = L10n.language }
        }
    }
}
