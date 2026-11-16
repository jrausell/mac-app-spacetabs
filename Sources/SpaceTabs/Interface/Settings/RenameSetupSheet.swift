import SpaceTabsCore
import SwiftUI

struct RenameSetupSheet: View {
    private let localization = AppLocalization.shared
    let title: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(title: String, name: String, save: @escaping (String) -> Void) {
        self.title = title
        self.save = save
        _name = State(initialValue: name)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(L10n.tr("Name"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            Text(L10n.tr("Use a name between 1 and \(PreferenceLimits.profileNameCharacters) characters."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.tr("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Save")) {
                    save(trimmedName)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || trimmedName.count > PreferenceLimits.profileNameCharacters)
            }
        }.padding(24).frame(width: 380).onAppear { nameFocused = true }
    }
}
