import SwiftUI

struct OwlLunaSettingsView: View {
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
    @AppStorage(SettingsKey.snapsHighlighter) private var snapsHighlighter = true
    @AppStorage(SettingsKey.scribbleErases) private var scribbleErases = true
    @AppStorage(SettingsKey.circleSelects) private var circleSelects = true
    @AppStorage(SettingsKey.pencilDoubleTap) private var pencilDoubleTap: PencilAction = .system
    @AppStorage(SettingsKey.pencilSqueeze) private var pencilSqueeze: PencilAction = .system
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

    private let repository = URL(string: "https://github.com/owaisazmal/OwlLuna")!
    private let author = URL(string: "https://github.com/owaisazmal")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x8) {
                    inputSection
                    pencilSection
                    paperSection
                    if UIApplication.shared.supportsAlternateIcons {
                        SettingsSection("App Icon") { AppIconPicker().settingsRow() }
                    }
                    journalSection
                    historySection
                    searchSection
                    syncSection
                    backupSection
                    aboutSection
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.x5)
                .padding(.top, Space.x4)
                .padding(.bottom, Space.x10)
            }
            .toggleStyle(.owlLuna)
            .foregroundStyle(Color.ink)
            .background(Color.paper)
            .navigationTitle("Settings")
            .barGround(.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.buttonStyle(.owlLuna(.primary, inBar: true))
                }
                .boardBackground()
            }
        }
        .tint(Color.accentColor)
        .presentationSizing(.page)
        .sheet(item: $sharedBackup) { file in ShareSheet(items: [file.url]) }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.owlLunaBackup, .legacyBackup, .appleArchive]) { result in
            if case .success(let url) = result { restore(url) }
        }
        .alert("Backup", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
    }

    private var inputSection: some View {
        SettingsSection("Input", note: "“System Setting” follows Settings › Apple Pencil › Only Draw with Apple Pencil.") {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Draw With")
                OwlLunaSegmentedPicker("Draw With", selection: $drawingInput, options: DrawingInput.allCases) { Text($0.displayName) }
            }
            .padding(.vertical, Space.x2)
            .settingsRow()
        }
    }

    private var pencilSection: some View {
        SettingsSection("Apple Pencil", note: "Draw a line, circle, rectangle or triangle and hold still before lifting to straighten it, or draw a loop round ink and hold still to select it. Scribble back and forth over ink with a pen to erase it; Undo brings it back. A highlighter drawn along a line of a PDF's text is laid straight over that line. For Double-Tap and Squeeze, “System Setting” follows Settings › Apple Pencil.") {
            Toggle("Straighten Shapes", isOn: $snapsShapes).settingsRow()
            Toggle("Snap Highlighter to PDF Text", isOn: $snapsHighlighter).settingsRow()
            Toggle("Circle and Hold to Select", isOn: $circleSelects)
                .accessibilityIdentifier("settings.pencil.circle")
                .settingsRow()
            Toggle("Scribble to Erase", isOn: $scribbleErases)
                .accessibilityIdentifier("settings.pencil.scribble")
                .settingsRow()
            SettingsChoiceRow(title: "Double-Tap", value: pencilDoubleTap.displayName, selection: $pencilDoubleTap) {
                ForEach(PencilAction.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("settings.pencil.doubleTap")
            SettingsChoiceRow(title: "Squeeze", value: pencilSqueeze.displayName, selection: $pencilSqueeze) {
                ForEach(PencilAction.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("settings.pencil.squeeze")
        }
    }

    private var paperSection: some View {
        SettingsSection("New Notebooks") {
            SettingsChoiceRow(title: "Template", value: template.displayName, selection: $template) {
                ForEach(PaperFamily.allCases) { family in
                    Section(family.displayName) {
                        ForEach(family.templates) { Text($0.displayName).tag($0) }
                    }
                }
            }
            SettingsChoiceRow(title: "Paper Colour", value: color.displayName, selection: $color) {
                ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
            }
            SettingsChoiceRow(title: "Page Size", value: size.displayName, selection: $size) {
                ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var journalSection: some View {
        let journal = journalID.isEmpty ? nil : store.dailyJournal
        return SettingsSection("Daily Journal", note: "Touch and hold a notebook, then choose Use as Daily Journal. Press ⌘T in the library to open today's page. With Print Today's Events on, each new day's page starts with that day's events from your calendar, as text you can move or delete. They are read on this iPad.") {
            SettingsValueRow(title: "Journal", value: journal?.title ?? String(localized: "None"))
            Toggle("Show On This Day", isOn: $showsOnThisDay).settingsRow()
            Toggle("Print Today's Events", isOn: Binding(get: { printsAgenda }, set: setPrintsAgenda))
                .accessibilityIdentifier("settings.journal.agenda")
                .settingsRow()
            if journal != nil {
                SettingsActionRow(title: "Stop Using Daily Journal", systemImage: "calendar.badge.minus") { journalID = "" }
            }
        }
        .alert("Calendar", isPresented: Binding(get: { agendaMessage != nil }, set: { if !$0 { agendaMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(agendaMessage ?? "")
        }
    }

    private var historySection: some View {
        SettingsSection("Writing History", note: "OwlLuna keeps a list of the days you wrote and which pages, on this device only. It's never shared.") {
            Toggle("Keep Writing History", isOn: Bindable(activity).isEnabled).settingsRow()
            SettingsActionRow(title: "Clear Writing History…", systemImage: "trash", role: .destructive) { confirmingHistoryClear = true }
                .disabled(!activity.hasHistory)
                .confirmationDialog("Clear your writing history?", isPresented: $confirmingHistoryClear, titleVisibility: .visible) {
                    Button("Clear Writing History", role: .destructive) { Task { await activity.clear() } }
                } message: {
                    Text("The week strip and calendar start afresh. Your notebooks and pages aren't affected.")
                }
        }
    }

    private var searchSection: some View {
        SettingsSection("Search", note: "Notebooks can be found from the Home Screen by their title or by the words in them. That index is kept by iPadOS on this iPad. Locked notebooks are never in it.") {
            Toggle("Find Notebooks in Spotlight", isOn: $showsInSpotlight)
                .accessibilityIdentifier("settings.spotlight")
                .settingsRow()
                .onChange(of: showsInSpotlight) { _, _ in
                    if let app { app.spotlight.schedule(app.library, after: .zero) }
                }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if let sync = app?.sync {
            SettingsSection("iCloud", note: "Each notebook is copied whole to your private iCloud storage and from there to your other iPads. A notebook open here syncs when you close it. If one was changed on two devices before they could sync, the newer version is kept and the older is saved beside it as a conflicted copy. Writing history stays on this device.") {
                Toggle("Sync with iCloud", isOn: Bindable(sync).isEnabled)
                    .disabled(sync.availability != .available)
                    .accessibilityIdentifier("settings.sync.toggle")
                    .settingsRow()
                if case .unavailable(let reason) = sync.availability {
                    Text(reason).font(.subheadline).foregroundStyle(Color.textSecondary).settingsRow()
                } else if sync.isEnabled {
                    SettingsActionRow(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath", isBusy: sync.isSyncing) {
                        Task { await sync.syncNow() }
                    }
                    .disabled(sync.isSyncing)
                    .accessibilityIdentifier("settings.sync.now")
                    if let error = sync.lastError {
                        Text(error).font(.subheadline).foregroundStyle(Color.tomato).settingsRow()
                    } else if let date = sync.lastSynced {
                        Text("\(sync.lastReport?.summary ?? ""). Last synced \(date.formatted(date: .omitted, time: .shortened)).")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("settings.sync.status")
                            .settingsRow()
                    }
                }
            }
        }
    }

    private var backupSection: some View {
        SettingsSection("Backup", note: "A backup is one file holding every notebook, folder and sticker. Restoring adds what is missing and never replaces a notebook: one that differs from the backup comes back beside yours as a copy.") {
            SettingsActionRow(title: "Back Up Library…", systemImage: "externaldrive", isBusy: backupWork == .backingUp, action: backUp)
                .accessibilityIdentifier("settings.backup.create")
            if let lastBackup {
                SettingsActionRow(title: "Share the Backup Again", systemImage: "square.and.arrow.up") { sharedBackup = SharedFile(url: lastBackup) }
                    .accessibilityIdentifier("settings.backup.share")
            }
            SettingsActionRow(title: "Restore from a Backup…", systemImage: "arrow.counterclockwise", isBusy: backupWork == .restoring) {
                choosingBackup = true
            }
            .accessibilityIdentifier("settings.backup.restore")
        }
        .disabled(backupWork != nil)
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            Colophon(author: author)
            SettingsLinkRow(title: "Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", destination: repository)
            SettingsLinkRow(title: "Report a Problem or Request a Feature", systemImage: "exclamationmark.bubble",
                            destination: repository.appendingPathComponent("issues"))
            SettingsLinkRow(title: "MIT License", systemImage: "doc.text", destination: repository.appendingPathComponent("blob/main/LICENSE"))
            NavigationLink {
                AcknowledgementsView()
            } label: {
                HStack(spacing: Space.x3) {
                    Label("Acknowledgements", systemImage: "text.book.closed")
                    Spacer(minLength: 0)
                    SettingsRowGlyph(systemName: "chevron.forward")
                }
            }
            .buttonStyle(.settingsRow)
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
                await AppModel.shared.flashcards.loadNewNotebooks()
                backupMessage = summary.message
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }
}

/// The book's last page: the mark, the name, what it costs and who made it.
private struct Colophon: View {
    let author: URL

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }

    var body: some View {
        VStack(spacing: Space.x3) {
            OwlLunaMark()
                .frame(width: 72, height: 72)
                .accessibilityLabel("OwlLuna")
                .accessibilityAddTraits(.isImage)
            VStack(spacing: Space.x1) {
                Text(verbatim: "OwlLuna").displayFont(28, relativeTo: .title)
                Text(verbatim: "\(String(localized: "Version")) \(version)").metaStyle()
            }
            .accessibilityElement(children: .combine)
            Text("OwlLuna is free and open source. No ads, no subscriptions, no tracking. Your notes stay on your device.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: author) {
                HStack(spacing: Space.x1) {
                    Text("Built by \(Text(verbatim: "Owais Khan").fontWeight(.semibold).foregroundStyle(Color.accentColor))")
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .hoverEffect(.highlight)
            .accessibilityIdentifier("settings.about.author")
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.x5)
        .padding(.top, Space.x6)
        .padding(.bottom, Space.x3)
    }
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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x8) {
                ForEach(entries) { entry in
                    SettingsSection(title: Text(verbatim: entry.name)) {
                        Text(entry.use).foregroundStyle(Color.textSecondary).settingsRow()
                        DisclosureGroup("SIL Open Font License 1.1") {
                            Text(entry.license)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Space.x2)
                        }
                        .settingsRow()
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.x5)
            .padding(.top, Space.x4)
            .padding(.bottom, Space.x10)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationTitle("Acknowledgements")
        .barGround(.paper)
    }
}
