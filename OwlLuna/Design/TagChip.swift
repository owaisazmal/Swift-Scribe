import SwiftUI

/// A tag as a paper label: cream stock, a hairline edge and a punched hole. Like a cover's label it is content, so it stays cream at night.
/// Chosen, it is mustard with a check mark. A long name is cut short so a row of chips never runs off a narrow sheet.
struct TagChip: View {
    let name: String
    var isChosen = false
    /// A glyph after the name saying what a tap does: a cross to take the tag off, a plus to add it.
    var symbol: String?

    var body: some View {
        HStack(spacing: Space.x2) {
            TagHole(color: isChosen ? Color.onMustard : Color.labelInk)
            Text(name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 200)
            if isChosen {
                Image(systemName: "checkmark").font(.caption.weight(.bold))
            } else if let symbol {
                Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(Color.labelInkSecondary)
            }
        }
        .foregroundStyle(isChosen ? Color.onMustard : Color.labelInk)
        .padding(.leading, Space.x2 + 2)
        .padding(.trailing, Space.x3)
        .padding(.vertical, Space.x1)
        .frame(minHeight: 32)
        .background(isChosen ? Color.mustard : Color.labelCream, in: RoundedRectangle.plate)
        .overlay { RoundedRectangle.plate.strokeBorder(Color.hairline, lineWidth: 1) }
    }
}

/// The reinforced hole a label is tied on by.
struct TagHole: View {
    var color = Color.labelInk
    var diameter: CGFloat = 9

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.55), lineWidth: 1.5)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// The small blank label on the thumbnail of a page that carries tags.
struct TagMark: View {
    var body: some View {
        RoundedRectangle.thumb
            .fill(Color.labelCream)
            .overlay { RoundedRectangle.thumb.strokeBorder(Color.labelInk.opacity(0.3), lineWidth: 1) }
            .overlay(alignment: .leading) { TagHole(diameter: 6).padding(.leading, 4) }
            .frame(width: 26, height: 14)
            .accessibilityHidden(true)
    }
}

/// A chip that does something when tapped, in a 44-point target.
struct TagChipButton: View {
    let name: String
    var isChosen = false
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TagChip(name: name, isChosen: isChosen, symbol: symbol)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}
