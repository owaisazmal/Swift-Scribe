import SwiftUI

/// The Home Screen icons, drawn by Scripts/AppIcon. Cobalt is the primary icon; the rest are alternates.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case cobalt, tomato, moss, oxblood, mustard, print

    var id: String { rawValue }

    var iconName: String? { self == .cobalt ? nil : "AppIcon-\(rawValue.capitalized)" }

    var previewName: String { "IconPreview-\(rawValue.capitalized)" }

    var displayName: String {
        switch self {
        case .cobalt: String(localized: "Cobalt")
        case .tomato: String(localized: "Tomato")
        case .moss: String(localized: "Moss")
        case .oxblood: String(localized: "Oxblood")
        case .mustard: String(localized: "Mustard")
        case .print: String(localized: "Print")
        }
    }

    var accessibilityName: String {
        self == .print ? String(localized: "Print icon") : String(localized: "\(displayName) cloth icon")
    }

    init(iconName: String?) {
        self = Self.allCases.first { $0.iconName == iconName } ?? .cobalt
    }
}

/// Tiles that wrap to the width on offer; at accessibility sizes they simply take more rows.
struct AppIconPicker: View {
    @State private var current = AppIconChoice(iconName: UIApplication.shared.alternateIconName)

    var body: some View {
        FlowLayout(spacing: Space.x3) {
            ForEach(AppIconChoice.allCases) { choice in
                Button { select(choice) } label: {
                    AppIconTile(choice: choice, isSelected: choice == current)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(choice.accessibilityName)
                .accessibilityAddTraits(choice == current ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("appIcon.\(choice.rawValue)")
            }
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task {
            try? await UIApplication.shared.setAlternateIconName(choice.iconName)
            current = AppIconChoice(iconName: UIApplication.shared.alternateIconName)
        }
    }
}

private struct AppIconTile: View {
    let choice: AppIconChoice
    let isSelected: Bool

    private let shape = RoundedRectangle(cornerRadius: 13.5, style: .continuous)

    var body: some View {
        VStack(spacing: Space.x1) {
            Image(choice.previewName)
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.hairline) }
                .overlay { if isSelected { IconStitching() } }
                .padding(Space.x2)
            Text(choice.displayName)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .contentShape(Rectangle())
    }
}

/// The library's stitched selection, following the icon's rounded corners.
private struct IconStitching: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.mustard, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .padding(-5)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(Color.onMustard)
                    .frame(width: 24, height: 24)
                    .background(Color.mustard, in: Circle())
                    .offset(x: 8, y: 8)
            }
            .accessibilityHidden(true)
    }
}
