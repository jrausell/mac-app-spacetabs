import AppKit
import SpaceTabsCore
import UniformTypeIdentifiers

let spaceTabsPasteboard = NSPasteboard.PasteboardType("dev.spacetabs.tab")

@MainActor enum TabDropReceiver {
    static func accept(_ providers: [NSItemProvider], model: AppModel, zone: Zone, before: UUID? = nil) -> Bool {
        guard
            let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(spaceTabsPasteboard.rawValue) }
            )
        else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: spaceTabsPasteboard.rawValue) { data, _ in
            guard let data, data.count <= 64, let value = String(data: data, encoding: .utf8),
                let id = UUID(uuidString: value)
            else { return }
            Task { @MainActor in model.reorderTab(id, to: zone, before: before) }
        }
        return true
    }
}
