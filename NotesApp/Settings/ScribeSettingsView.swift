import SwiftUI

struct ScribeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(WritingActivity.self) private var activity
    @Environment(AppModel.self) private var app: AppModel?
    @AppStorage(SettingsKey.drawingInput) private var drawingInput: DrawingInput = .system
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter
    @AppStorage(SettingsKey.dailyJournalID) private var journalID = ""
    @AppStorage(SettingsKey.showsOnThisDay) private var showsOnThisDay = true
    @AppStorage(SettingsKey.snapsShapes) private var snapsShapes = true
    @AppStorage(SettingsKey.journalAgenda) private var printsAgenda = false
    @AppStorage(SettingsKey.spotlight) private var showsInSpotlight = true
    @State private var agendaMessage: String?
    @State private var confirmingHistoryClear = false
    @State private var backupWork: BackupWork?
    @State private var lastBackup: URL?
    @State private var sharedBackup: SharedFile?
    @State private var choosingBackup = false
    @State private var backupMessage: String?

    private enum BackupWork { case backingUp, restoring }

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private let repository = URL(string: "https://github.com/owaisazmal/Swift-Scribe")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Draw With", selection: $drawingInput) {
                        ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Straighten Shapes", isOn: $snapsShapes)
                } header: {
                    SettingsNote("Input")
                } footer: {
                    SettingsNote("“System Setting” follows Settings › Apple Pencil › Only Draw with Apple Pencil. With Straighten Shapes on, draw a line, circle, rectangle or triangle and hold still for a moment before lifting; Undo brings your own stroke back.")
                }
                .listRowBackground(Color.surface)

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
                .listRowBackground(Color.surface)

                if UIApplication.shared.supportsAlternateIcons {
                    Section {
                        AppIconPicker()
                    } header: {
                        SettingsNote("App Icon")
                    }
                    .listRowBackground(Color.surface)
                }

                Section {
                    let journal = journalID.isEmpty ? nil : store.dailyJournal
                    LabeledContent("Journal", value: journal?.title ?? String(localized: "None"))
                    Toggle("Show On This Day", isOn: $showsOnThisDay)
                    Toggle("Print Today's Events", isOn: Binding(get: { printsAgenda }, set: setPrintsAgenda))
                        .accessibilityIdentifier("settings.journal.agenda")
                    if journal != nil {
                        Button("Stop Using Daily Journal") { journalID = "" }
                    }
                } header: {
                    SettingsNote("Daily Journal")
                } footer: {
                    SettingsNote("Touch and hold a notebook, then choose Use as Daily Journal. Press ⌘T in the library to open today's page. With Print Today's Events on, each new day's page starts with that day's events from your calendar, as text you can move or delete. They are read on this iPad.")
                }
                .listRowBackground(Color.surface)
                .alert("Calendar", isPresented: Binding(get: { agendaMessage != nil }, set: { if !$0 { agendaMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(agendaMessage ?? "")
                }

                Section {
                    Toggle("Keep Writing History", isOn: Bindable(activity).isEnabled)
                    Button("Clear Writing History…") { confirmingHistoryClear = true }
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
                .listRowBackground(Color.surface)

                Section {
                    Toggle("Find Notebooks in Spotlight", isOn: $showsInSpotlight)
                        .accessibilityIdentifier("settings.spotlight")
                        .onChange(of: showsInSpotlight) { _, _ in
                            if let app { app.spotlight.schedule(app.library, after: .zero) }
                        }
                } header: {
                    SettingsNote("Search")
                } footer: {
                    SettingsNote("Notebooks can be found from the Home Screen by their title or by the words in them. That index is kept by iPadOS on this iPad. Locked notebooks are never in it.")
                }
                .listRowBackground(Color.surface)

                if let sync = app?.sync {
                    Section {
                        Toggle("Sync with iCloud", isOn: Bindable(sync).isEnabled)
                            .disabled(sync.availability != .available)
                            .accessibilityIdentifier("settings.sync.toggle")
                        if case .unavailable(let reason) = sync.availability {
                            Text(reason).font(.subheadline).foregroundStyle(Color.textSecondary)
                        } else if sync.isEnabled {
                            Button { Task { await sync.syncNow() } } label: {
                                HStack {
                                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                    Spacer()
                                    if sync.isSyncing { ProgressView() }
                                }
                            }
                            .disabled(sync.isSyncing)
                            .accessibilityIdentifier("settings.sync.now")
                            if let error = sync.lastError {
                                Text(error).font(.subheadline).foregroundStyle(Color.tomato)
                            } else if let date = sync.lastSynced {
                                Text("\(sync.lastReport?.summary ?? ""). Last synced \(date.formatted(date: .omitted, time: .shortened)).")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .accessibilityIdentifier("settings.sync.status")
                            }
                        }
                    } header: {
                        SettingsNote("iCloud")
                    } footer: {
                        SettingsNote("Each notebook is copied whole to your private iCloud storage and from there to your other iPads. A notebook open here syncs when you close it. If one was changed on two devices before they could sync, the newer version is kept and the older is saved beside it as a conflicted copy. Writing history stays on this device.")
                    }
                    .listRowBackground(Color.surface)
                }

                Section {
                    Button(action: backUp) {
                        HStack {
                            Label("Back Up Library…", systemImage: "externaldrive")
                            Spacer()
                            if backupWork == .backingUp { ProgressView() }
                        }
                    }
                    .accessibilityIdentifier("settings.backup.create")
                    if let lastBackup {
                        Button { sharedBackup = SharedFile(url: lastBackup) } label: { Label("Share the Backup Again", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("settings.backup.share")
                    }
                    Button { choosingBackup = true } label: {
                        HStack {
                            Label("Restore from a Backup…", systemImage: "arrow.counterclockwise")
                            Spacer()
                            if backupWork == .restoring { ProgressView() }
                        }
                    }
                    .accessibilityIdentifier("settings.backup.restore")
                } header: {
                    SettingsNote("Backup")
                } footer: {
                    SettingsNote("A backup is one file holding every notebook, folder and sticker. Restoring adds what is missing and never replaces a notebook: one that differs from the backup comes back beside yours as a copy.")
                }
                .listRowBackground(Color.surface)
                .disabled(backupWork != nil)

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
                    SettingsNote("Swift Scribe is free and open source. No ads, no subscriptions, no tracking. Your notes stay on your device.")
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.buttonStyle(.scribe(.primary, inBar: true))
                }
                .boardBackground()
            }
        }
        .tint(Color.accentColor)
        .presentationSizing(.page)
        .sheet(item: $sharedBackup) { file in ShareSheet(items: [file.url]) }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.scribeBackup, .appleArchive]) { result in
            if case .success(let url) = result { restore(url) }
        }
        .alert("Backup", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
    }

    /// Turning it on asks for the calendar there and then, so a new day's page never has to.
    private func setPrintsAgenda(_ on: Bool) {
        printsAgenda = on
        guard on else { return }
        Task {
            do {
                _ = try await Agenda.calendar.events(on: .now, calendar: .current)
            } catch {
                printsAgenda = false
                agendaMessage = error.localizedDescription
            }
        }
    }

    private func backUp() {
        backupWork = .backingUp
        Task {
            defer { backupWork = nil }
            do {
                let url = try await store.makeBackup()
                lastBackup = url
                sharedBackup = SharedFile(url: url)
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ url: URL) {
        backupWork = .restoring
        Task {
            defer { backupWork = nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try await store.restoreBackup(from: url)
                await activity.load()
                backupMessage = summary.message
            } catch {
                backupMessage = error.localizedDescription
            }
        }
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
        [("Fraunces", String(localized: "Library headings, cloth labels and empty states"), "OFL-Fraunces"),
         ("Bricolage Grotesque", String(localized: "Print cover titles"), "OFL-BricolageGrotesque")].map { name, use, file in
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
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("Acknowledgements")
    }
}
