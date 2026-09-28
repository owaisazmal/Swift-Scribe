import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.drawingInput) private var drawingInput: DrawingInput = .system
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter

    private let repository = URL(string: "https://github.com/owaisazmal/Swift-Scribe")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Draw With", selection: $drawingInput) {
                        ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("\"System Setting\" follows Settings > Apple Pencil > Only Draw with Apple Pencil.")
                }

                Section("New Notebooks") {
                    Picker("Template", selection: $template) {
                        ForEach(PaperTemplate.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Paper Color", selection: $color) {
                        ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Page Size", selection: $size) {
                        ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Link(destination: repository) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: repository.appendingPathComponent("issues")) {
                        Label("Report a Problem or Request a Feature", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Swift Scribe is free and open source. No ads, no subscriptions, no tracking — your notes stay on your device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
