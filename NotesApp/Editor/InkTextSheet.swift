import SwiftUI
import PencilKit
import Translation

/// Reads the selected handwriting and shows it as text that can be corrected, translated, copied, or typed onto the
/// page in its place.
struct InkTextSheet: View {
    let ink: [PKDrawing]
    let replace: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var text = ""
    @State private var phase = Phase.reading
    @State private var copied = false
    @State private var languages: [Locale.Language] = []
    /// What the handwriting read as, while a translation of it is showing.
    @State private var original: String?
    @State private var target: Locale.Language?
    @State private var configuration: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var failure: String?

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
                            .disabled(isTranslating)
                            .accessibilityLabel(Text("Handwriting as text"))
                            .accessibilityIdentifier("inktext.editor")
                        if isTranslating || target != nil { translationNote }
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
                        .disabled(isTranslating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fixedSize(horizontal: false, vertical: true)
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
                if phase == .ready, !languages.isEmpty {
                    ToolbarItem(placement: .primaryAction) { translateMenu }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            let pieces = ink
            let found = await Task.detached(priority: .userInitiated) { InkText.recognize(pieces) }.value
            guard let found else { return phase = .failed }
            text = found
            phase = found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nothing : .ready
            if phase == .ready { languages = await InkTranslation.languages() }
        }
        .translationTask(configuration) { @Sendable session in
            guard let source = await pendingSource() else { return }
            do {
                await finishTranslation(.success(try await InkTranslation.translate(source, with: session)))
            } catch {
                await finishTranslation(.failure(error))
            }
        }
        .alert("Couldn't Translate", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var translateMenu: some View {
        Menu {
            if original != nil {
                Button(action: showOriginal) { Label("Show Original", systemImage: "arrow.uturn.backward") }
                Divider()
            }
            ForEach(languages, id: \.minimalIdentifier) { language in
                Button { translate(into: language) } label: {
                    if language.minimalIdentifier == target?.minimalIdentifier {
                        Label(InkTranslation.name(of: language), systemImage: "checkmark")
                    } else {
                        Text(InkTranslation.name(of: language))
                    }
                }
            }
        } label: {
            Label("Translate", systemImage: "translate")
        }
        .disabled(isTranslating || (original ?? text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("inktext.translate")
    }

    /// Says what the text now is, and offers the way back to what the handwriting read as.
    private var translationNote: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2)) : AnyLayout(HStackLayout(spacing: Space.x3))) {
            if isTranslating {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(Color.textSecondary)
            } else if let target {
                Text("Translated into \(InkTranslation.name(of: target)) on this iPad.")
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Show Original", action: showOriginal)
                    .accessibilityIdentifier("inktext.original")
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, Space.x4)
    }

    private func translate(into language: Locale.Language) {
        if original == nil { original = text }
        copied = false
        #if DEBUG
        if InkTranslation.isScripted {
            text = InkTranslation.scripted(original ?? text, into: language)
            target = language
            return
        }
        #endif
        isTranslating = true
        target = language
        if configuration?.target?.minimalIdentifier == language.minimalIdentifier {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: language)
        }
    }

    private func pendingSource() -> String? {
        isTranslating ? original : nil
    }

    private func finishTranslation(_ result: Result<String, any Error>) {
        guard isTranslating, let source = original else { return }
        isTranslating = false
        switch result {
        case .success(let translated):
            text = translated
            AccessibilityNotification.Announcement(String(localized: "Translated")).post()
        case .failure(let error):
            text = source
            original = nil
            target = nil
            if !(error is CancellationError) { failure = error.localizedDescription }
        }
    }

    private func showOriginal() {
        guard let original else { return }
        text = original
        self.original = nil
        target = nil
        copied = false
    }
}
