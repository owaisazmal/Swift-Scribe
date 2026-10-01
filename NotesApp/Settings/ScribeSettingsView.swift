import SwiftUI

struct ScribeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(AppModel.self) private var app
    @Environment(WritingActivity.self) private var activity
    @AppStorage(SettingsKey.drawingInput) private var drawingInput: DrawingInput = .system
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter
    @AppStorage(SettingsKey.dailyJournalID) private var journalID = ""
    @AppStorage(SettingsKey.showsOnThisDay) private var showsOnThisDay = true
    @State private var backupSize: String?
    @State private var confirmingBackupDelete = false
    @State private var backupError: String?
    @State private var confirmingHistoryClear = false

    private let repository = URL(string: "https://github.com/owaisazmal/Swift-Scribe")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Draw With", selection: $drawingInput) {
                        ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    SettingsNote("Input")
                } footer: {
                    SettingsNote("“System Setting” follows Settings › Apple Pencil › Only Draw with Apple Pencil.")
                }

                Section {
                    Picker("Template", selection: $template) {
                        ForEach(PaperFamily.allCases) { family in
                            Section(family.displayName) {
                                ForEach(family.templates) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                    Picker("Paper Colour", selection: $color) {
                        ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Page Size", selection: $size) {
                        ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    SettingsNote("New Notebooks")
                }

                if UIApplication.shared.supportsAlternateIcons {
                    Section {
                        AppIconPicker()
                    } header: {
                        SettingsNote("App Icon")
                    }
                }

                Section {
                    let journal = journalID.isEmpty ? nil : store.dailyJournal
                    LabeledContent("Journal", value: journal?.title ?? String(localized: "None"))
                    Toggle("Show On This Day", isOn: $showsOnThisDay)
                    if journal != nil {
                        Button("Stop Using Daily Journal") { journalID = "" }
                    }
                } header: {
                    SettingsNote("Daily Journal")
                } footer: {
                    SettingsNote("Touch and hold a notebook, then choose Use as Daily Journal. Press ⌘T in the library to open today's page.")
                }

                Section {
                    Toggle("Keep Writing History", isOn: Bindable(activity).isEnabled)
                    Button("Clear Writing History…", role: .destructive) { confirmingHistoryClear = true }
                        .disabled(!activity.hasHistory)
                        .confirmationDialog("Clear your writing history?", isPresented: $confirmingHistoryClear, titleVisibility: .visible) {
                            Button("Clear Writing History", role: .destructive) { Task { await activity.clear() } }
                        } message: {
                            Text("The week strip and calendar start afresh. Your notebooks and pages aren't affected.")
                        }
                } header: {
                    SettingsNote("Writing History")
                } footer: {
                    SettingsNote("Swift Scribe keeps a list of the days you wrote and which pages, on this device only. It's never shared.")
                }

                if let problem = app.migrationProblem {
                    Section {
                        Text(problem)
                    } header: {
                        SettingsNote("Moving to the New Format")
                    } footer: {
                        SettingsNote("Your original notebooks are untouched. Swift Scribe tries again each time it opens.")
                    }
                }

                if let backupSize {
                    Section {
                        LabeledContent("Previous-format backup", value: backupSize)
                        Button("Delete Backup…", role: .destructive) { confirmingBackupDelete = true }
                    } footer: {
                        SettingsNote("Your notebooks were moved to the new format. The original files are kept in Backups/v1 inside the app's storage.")
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    Link(destination: repository) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: repository.appendingPathComponent("issues")) {
                        Label("Report a Problem or Request a Feature", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    SettingsNote("About")
                } footer: {
                    SettingsNote("Swift Scribe is free and open source. No ads, no subscriptions, no tracking — your notes stay on your device.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await refreshBackupSize() }
            .confirmationDialog("Delete the previous-format backup?", isPresented: $confirmingBackupDelete, titleVisibility: .visible) {
                Button("Delete Backup", role: .destructive) { Task { await deleteBackup() } }
            } message: {
                Text("This removes the copy of your notebooks in the old format. The notebooks in your library aren't affected. This can't be undone.")
            }
            .alert("The backup couldn't be deleted", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupError ?? "")
            }
        }
        .presentationSizing(.page)
    }

    private var backupDirectory: URL { store.root.backups.appending(path: "v1", directoryHint: .isDirectory) }

    private func refreshBackupSize() async {
        let backup = backupDirectory
        backupSize = await Task.detached { Self.size(of: backup) }.value
    }

    private func deleteBackup() async {
        let backup = backupDirectory
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            do { try FileManager.default.removeItem(at: backup) } catch { return error.localizedDescription }
            return nil
        }.value
        backupError = failure
        await refreshBackupSize()
    }

    nonisolated static func size(of directory: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total = 0
        for case let url as URL in enumerator { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total > 0 ? total.formatted(.byteCount(style: .file)) : nil
    }
}

/// Section headers and footers in the text token: the system grey doesn't reach 4.5:1 on the surface colour.
private struct SettingsNote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).foregroundStyle(Color.textSecondary) }
}

struct AcknowledgementsView: View {
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let use: String
        let license: String
    }

    private var entries: [Entry] {
        [("Fraunces", "Library headings, cloth labels and empty states", "OFL-Fraunces"),
         ("Bricolage Grotesque", "Print cover titles", "OFL-BricolageGrotesque")].map { name, use, file in
            let url = Bundle.main.url(forResource: file, withExtension: "txt")
            return Entry(id: file, name: name, use: use, license: url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section {
                    Text(entry.use).foregroundStyle(Color.textSecondary)
                    DisclosureGroup("SIL Open Font License 1.1") {
                        Text(entry.license).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                } header: {
                    Text(entry.name).displayFont(20, relativeTo: .title3).textCase(nil).foregroundStyle(Color.ink)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Acknowledgements")
    }
}
