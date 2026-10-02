import SwiftUI
import PencilKit

/// Reads the selected handwriting and shows it as text that can be corrected, copied, or typed onto the page in its place.
struct InkTextSheet: View {
    let ink: [PKDrawing]
    let replace: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var text = ""
    @State private var phase = Phase.reading
    @State private var copied = false

    private enum Phase { case reading, ready, nothing, failed }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    ProgressView { Text("Reading your handwriting…").foregroundStyle(Color.ink) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    VStack(spacing: 0) {
                        TextEditor(text: $text)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .scrollContentBackground(.hidden)
                            .padding(Space.x3)
                            .accessibilityLabel(Text("Handwriting as text"))
                            .accessibilityIdentifier("inktext.editor")
                        Divider()
                        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.x3)) : AnyLayout(HStackLayout(spacing: Space.x3))) {
                            Button {
                                UIPasteboard.general.string = text
                                copied = true
                                AccessibilityNotification.Announcement(String(localized: "Copied")).post()
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("inktext.copy")
                            Button {
                                replace(text)
                                dismiss()
                            } label: {
                                Label("Replace Handwriting", systemImage: "character.textbox")
                            }
                            .prominentButton()
                            .accessibilityIdentifier("inktext.replace")
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(Space.x4)
                    }
                case .nothing, .failed:
                    ScrollView {
                        ContentUnavailableView {
                            Label(phase == .nothing ? "No Words Found" : "Couldn't Read the Ink", systemImage: "text.viewfinder").foregroundStyle(Color.ink)
                        } description: {
                            Text(phase == .nothing ? "Nothing in the selected ink could be read as writing. Try selecting whole words or lines."
                                                   : "The handwriting recogniser didn't answer. Try again in a moment.")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("inktext.empty")
                }
            }
            .background(Color.surface)
            .navigationTitle("Handwriting as Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            let pieces = ink
            let found = await Task.detached(priority: .userInitiated) { InkText.recognize(pieces) }.value
            guard let found else { return phase = .failed }
            text = found
            phase = found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nothing : .ready
        }
    }
}
