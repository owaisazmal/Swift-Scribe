import SwiftUI

/// A chapter of Settings: a Fraunces heading, its rows on one Surface card ruled with Hairlines, and a note beneath.
struct SettingsSection<Content: View>: View {
    let title: Text
    var note: LocalizedStringKey?
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle.plate

    init(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: Text(title), note: note, content: content)
    }

    init(title: Text, note: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            title
                .displayFont(22, relativeTo: .title3)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id { Rectangle().fill(Color.hairline).frame(height: 1) }
                        row
                    }
                }
            }
            .background(Color.surface)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.hairline).allowsHitTesting(false) }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.x1)
            }
        }
    }
}

extension View {
    /// The inset and least height every row of a Settings card shares.
    func settingsRow() -> some View {
        padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

/// A name and what it is set to, with nothing to press.
struct SettingsValueRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: Space.x3) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).foregroundStyle(Color.textSecondary).multilineTextAlignment(.trailing)
        }
        .settingsRow()
        .accessibilityElement(children: .combine)
    }
}

/// One of a few values, picked from a menu and shown on a small square well.
struct SettingsChoiceRow<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    let value: String
    @Binding var selection: Value
    @ViewBuilder var options: Options
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let chip = RoundedRectangle.plate

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                                         : AnyLayout(HStackLayout(spacing: Space.x3))
        layout {
            Text(title).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            OwlLunaMenu(Text(title)) {
                OwlLunaPicker(selection: $selection) { options }
            } label: {
                HStack(spacing: Space.x2) {
                    Text(value).multilineTextAlignment(.leading)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Color.textSecondary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Space.x3)
                .padding(.vertical, Space.x1)
                .frame(minHeight: 34)
                .background(Color.well, in: chip)
                .overlay { chip.strokeBorder(Color.hairline) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, chip)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
        }
        .settingsRow()
    }
}

/// A row that does something: its mark on a square tile, its name, and a spinner while it works.
struct SettingsActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole?
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Space.x3) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 0)
                if isBusy { ProgressView() }
            }
        }
        .buttonStyle(.settingsRow)
    }
}

/// A row that leaves the app for a web page.
struct SettingsLinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: Space.x3) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 0)
                SettingsRowGlyph(systemName: "arrow.up.right")
            }
        }
        .buttonStyle(.settingsRow)
    }
}

/// The small mark at a row's trailing end that says where a press leads.
struct SettingsRowGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .accessibilityHidden(true)
    }
}

struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(TileLabelStyle(tint: configuration.role == .destructive ? .tomato : .accentColor, isEnabled: isEnabled))
                .foregroundStyle(isEnabled ? Color.ink : Color.textSecondary)
                .settingsRow()
                .background { if configuration.isPressed { Color.well } }
                .contentShape(Rectangle())
                .hoverEffect(.highlight)
        }
    }

    private struct TileLabelStyle: LabelStyle {
        let tint: Color
        let isEnabled: Bool

        private let tile = RoundedRectangle.plate

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: Space.x3) {
                configuration.icon
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEnabled ? tint : Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.well, in: tile)
                    .overlay { tile.strokeBorder(Color.hairline) }
                    .accessibilityHidden(true)
                configuration.title
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension ButtonStyle where Self == SettingsRowButtonStyle {
    static var settingsRow: SettingsRowButtonStyle { SettingsRowButtonStyle() }
}
