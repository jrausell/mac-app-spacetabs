import Foundation

public struct TabManager: Codable, Equatable, Sendable {
    public private(set) var windows: [Zone: [UUID]] = [.a: [], .b: [], .c: []]
    public private(set) var selected: [Zone: UUID] = [:]
    public init() {}

    public func zone(of id: UUID) -> Zone? { Zone.allCases.first { windows[$0, default: []].contains(id) } }

    public mutating func assign(_ id: UUID, to zone: Zone, selecting: Bool = true) {
        let previousSelection = selected[zone]
        remove(id)
        windows[zone, default: []].append(id)
        selected[zone] =
            selecting ? id : (previousSelection.flatMap { windows[zone, default: []].contains($0) ? $0 : nil } ?? id)
    }

    @discardableResult public mutating func select(_ id: UUID, in zone: Zone) -> Bool {
        guard windows[zone, default: []].contains(id) else { return false }
        selected[zone] = id
        return true
    }

    public mutating func remove(_ id: UUID) {
        for zone in Zone.allCases {
            let previous = windows[zone, default: []]
            guard let index = previous.firstIndex(of: id) else { continue }
            windows[zone]?.remove(at: index)
            if selected[zone] == id {
                let remaining = windows[zone, default: []]
                selected[zone] = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
            }
        }
    }

    /// Preserve A's selection when folding the lower left group into A.
    public mutating func adapt(to template: LayoutTemplate) {
        guard template == .twoColumns else { return }
        let selection = selected[.a] ?? selected[.c]
        for id in windows[.c, default: []] { assign(id, to: .a) }
        if let selection { select(selection, in: .a) }
    }

    public mutating func reorder(_ id: UUID, in zone: Zone, before other: UUID?) {
        guard var list = windows[zone], list.contains(id), other != id else { return }
        list.removeAll { $0 == id }
        if let other, let index = list.firstIndex(of: other) { list.insert(id, at: index) } else { list.append(id) }
        windows[zone] = list
    }

    public func adjacent(in zone: Zone, offset: Int) -> UUID? {
        let list = windows[zone, default: []]
        guard !list.isEmpty else { return nil }
        let index = selected[zone].flatMap { list.firstIndex(of: $0) } ?? 0
        return list[((index + offset) % list.count + list.count) % list.count]
    }
}
