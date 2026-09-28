import SwiftUI

struct NewNotebookSheet: View {
    let onCreate: (String, PaperTemplate, PaperColor, PageSize) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Untitled Notebook", text: $title)
                        .font(.title3)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                }
                Section("Paper") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(PaperTemplate.allCases) { option in
                                Button { template = option } label: {
                                    TemplatePreview(template: option, color: color, isSelected: template == option)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Picker("Color", selection: $color) {
                        ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Size", selection: $size) {
                        ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                    }
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create) }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        dismiss()
        onCreate(trimmed.isEmpty ? "Untitled Notebook" : trimmed, template, color, size)
    }
}

struct TemplatePreview: View {
    let template: PaperTemplate
    let color: PaperColor
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: Self.render(template, color))
                .resizable()
                .frame(width: 72, height: 93)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-4)
                }
            Text(template.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .padding(4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    static func render(_ template: PaperTemplate, _ color: PaperColor) -> UIImage {
        let size = CGSize(width: 144, height: 186)
        return UIGraphicsImageRenderer(size: size).image { context in
            PaperRenderer.uiColor(color).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            PaperRenderer.drawTemplate(template, color: color, in: context.cgContext, size: size)
        }
    }
}
