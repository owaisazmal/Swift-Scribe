import SwiftUI

/// The main points of a notebook and practice questions about it, written by the model on this iPad.
struct StudyGuideSheet: View {
    let session: EditorSession
    @Environment(FlashcardLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scope: StudyScope
    @State private var tab = Tab.summary
    @State private var summary = Phase<[String]>.idle
    @State private var quiz = Phase<[QuizItem]>.idle
    @State private var shown: Set<UUID> = []
    @State private var copied = false
    @State private var savedCards = false
    @State private var summaryRun: UUID?
    @State private var quizRun: UUID?
    private let status = StudyGuide.status

    enum Tab: Hashable { case summary, quiz }

    enum Phase<Value: Equatable>: Equatable {
        case idle
        case working(Double)
        case done(Value)
        case failed(String)
    }

    init(session: EditorSession, request: StudyGuideRequest) {
        self.session = session
        _scope = State(initialValue: request.scope)
    }

    private var document: NotebookDocument { session.document }
    private var currentPage: NotebookPage? { document.pages.indices.contains(session.currentPage) ? document.pages[session.currentPage] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if status == .ready {
                    VStack(spacing: 0) {
                        OwlLunaSegmentedPicker("Study Guide", selection: $tab, options: [Tab.summary, .quiz]) { tab in
                            Text(tab == .summary ? "Summary" : "Practice Questions")
                        }
                        .padding(.horizontal, Space.x4)
                        .padding(.vertical, Space.x3)
                        .accessibilityIdentifier("guide.tabs")
                        switch tab {
                        case .summary: summaryPage
                        case .quiz: quizPage
                        }
                    }
                } else {
                    unavailable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Study Guide")
            .barGround(.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.owlLuna(.secondary, inBar: true))
                        .accessibilityIdentifier("guide.done")
                }
                .boardBackground()
                if status == .ready {
                    ToolbarItem(placement: .primaryAction) { scopeMenu }
                        .boardBackground()
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.surface)
        .onAppear(perform: write)
        .onChange(of: tab) { write() }
        .onChange(of: scope) {
            summary = .idle
            quiz = .idle
            summaryRun = nil
            quizRun = nil
            shown = []
            copied = false
            savedCards = false
            write()
        }
    }

    // MARK: What to read

    private var scopeMenu: some View {
        OwlLunaMenu(Text("Write From")) {
            OwlLunaPicker(selection: $scope) {
                Text("Whole Notebook").tag(StudyScope.notebook)
                if let page = currentPage { Text("Page \(session.currentPage + 1)").tag(StudyScope.page(page.id)) }
                ForEach(Array(session.recorder.recordings.enumerated()), id: \.element.id) { index, recording in
                    if recording.transcriptFile != nil { Text("Recording \(index + 1)").tag(StudyScope.recording(recording.id)) }
                }
            }
        } label: {
            HStack(spacing: Space.x1) {
                Text(scopeName)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
        }
        .buttonStyle(.owlLuna(.secondary, inBar: true))
        .accessibilityLabel(Text("Write from: \(scopeName)"))
        .accessibilityIdentifier("guide.scope")
    }

    private var scopeName: String {
        switch scope {
        case .notebook: String(localized: "Whole Notebook")
        case .page(let id): String(localized: "Page \((document.index(of: id) ?? 0) + 1)")
        case .recording(let id): String(localized: "Recording \((session.recorder.recordings.firstIndex { $0.id == id } ?? 0) + 1)")
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryPage: some View {
        switch summary {
        case .idle, .working: working(summary, "Reading your notes…")
        case .failed(let message): failed(message)
        case .done(let points):
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x4) {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("\(document.title) · \(scopeName)").metaStyle(.footnote)
                        Text("Key Points")
                            .displayFont(28, relativeTo: .title)
                            .foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: Space.x3) {
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
                                Text(index + 1, format: .number)
                                    .font(.footnote.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(minWidth: 18, alignment: .trailing)
                                    .accessibilityHidden(true)
                                Text(point)
                                    .font(.body)
                                    .foregroundStyle(Color.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityIdentifier("guide.point.\(index + 1)")
                        }
                    }
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    onDeviceNote
                }
                .padding(Space.x5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .leaf()
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x4)
            }
            .safeAreaInset(edge: .bottom) {
                actions {
                    Button {
                        UIPasteboard.general.string = StudyGuide.listed(points)
                        copied = true
                        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.owlLuna)
                        .accessibilityIdentifier("guide.copy")
                    againButton
                    Button {
                        session.addStudyNotes(points)
                        dismiss()
                    } label: { Label("Add to Page", systemImage: "character.textbox") }
                        .buttonStyle(.owlLuna(.primary))
                        .disabled(document.isReadOnly)
                        .accessibilityIdentifier("guide.add")
                }
            }
        }
    }

    // MARK: Questions

    @ViewBuilder
    private var quizPage: some View {
        switch quiz {
        case .idle, .working: working(quiz, "Writing questions from your notes…")
        case .failed(let message): failed(message)
        case .done(let items):
            ScrollView {
                VStack(spacing: Space.x3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        QuestionCard(number: index + 1, item: item, isShown: shown.contains(item.id)) {
                            if shown.remove(item.id) == nil { shown.insert(item.id) }
                        } remove: {
                            quiz = .done(items.filter { $0.id != item.id })
                        }
                    }
                    onDeviceNote
                        .padding(.top, Space.x1)
                        .padding(.horizontal, Space.x1)
                }
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x4)
            }
            .safeAreaInset(edge: .bottom) {
                actions {
                    againButton
                    Button { saveCards(items) } label: {
                        Label(savedCards ? String(localized: "Saved to Flashcards") : String(localized: "Save \(items.count) as Flashcards"),
                              systemImage: savedCards ? "checkmark" : "rectangle.on.rectangle.angled")
                    }
                    .buttonStyle(.owlLuna(.primary))
                    .disabled(savedCards || items.isEmpty || !library.canChange(document.id))
                    .accessibilityIdentifier("guide.save")
                }
            }
        }
    }

    private func saveCards(_ items: [QuizItem]) {
        let page: UUID? = if case .page(let id) = scope { id } else { nil }
        let cards = items.map { Flashcard(front: CardSide(text: $0.question), back: CardSide(text: $0.answer), pageID: page) }
        guard library.add(cards, to: document.id) else { return }
        savedCards = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AccessibilityNotification.Announcement(String(localized: "\(cards.count) flashcards made")).post()
    }

    // MARK: Pieces

    private var againButton: some View {
        Button {
            copied = false
            savedCards = false
            shown = []
            retry()
        } label: { Label("Write It Again", systemImage: "arrow.clockwise") }
            .buttonStyle(.owlLuna)
            .accessibilityIdentifier("guide.again")
    }

    private func retry() {
        if tab == .summary { summary = .idle } else { quiz = .idle }
        write()
    }

    private var onDeviceNote: some View {
        Label {
            Text("Written on this iPad from what your notes say. Nothing was sent anywhere. Check it against your notes: it can be wrong.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.ipad").accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.x3)) : AnyLayout(HStackLayout(spacing: Space.x3))
        return layout { content() }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x3)
            .frame(maxWidth: .infinity)
            .background(Color.surface)
            .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func working<Value>(_ phase: Phase<Value>, _ title: LocalizedStringKey) -> some View {
        let done: Double = if case .working(let value) = phase { value } else { 0 }
        return VStack(spacing: Space.x4) {
            CardStackIllustration(width: 96)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.ink)
            ProgressView(value: done)
                .tint(Color.primaryCloth)
                .frame(width: 180)
                .accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("guide.working")
    }

    private func failed(_ message: String) -> some View {
        ScrollView {
            EmptyPlate("Couldn't Write This", systemImage: "text.badge.xmark", message: Text(message)) {
                Button("Try Again", action: retry)
                    .buttonStyle(.owlLuna)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("guide.failed")
    }

    private var unavailable: some View {
        ScrollView {
            EmptyPlate("Not on This iPad Yet", systemImage: "lock.ipad", message: Text(unavailableReason))
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("guide.unavailable")
    }

    private var unavailableReason: String {
        switch status {
        case .ready: ""
        case .needsUpdate: String(localized: "Study guides are written by Apple Intelligence on the iPad itself, which needs iPadOS 26 or later. Your notes never leave it.")
        case .notEligible: String(localized: "Study guides are written by Apple Intelligence on the iPad itself, and this iPad doesn't have it. OwlLuna never sends your notes anywhere to be read.")
        case .turnedOff: String(localized: "Study guides are written by Apple Intelligence on the iPad itself. Turn it on in Settings, under Apple Intelligence and Siri, and come back. Your notes never leave the iPad.")
        case .preparing: String(localized: "Apple Intelligence is still getting ready on this iPad. Try again in a little while.")
        }
    }

    // MARK: Writing

    /// Starts writing what the showing tab lacks. The work outlives a redraw of the sheet; a newer request replaces it.
    private func write() {
        guard status == .ready, let model = StudyGuide.model() else { return }
        let scope = scope, document = document, token = UUID()
        switch tab {
        case .summary:
            guard summary == .idle else { return }
            summary = .working(0)
            summaryRun = token
            Task {
                do {
                    let text = await StudyGuide.text(for: scope, in: document)
                    let points = try await StudyGuide.summary(of: text, using: model) { value in
                        if summaryRun == token { summary = .working(value) }
                    }
                    guard summaryRun == token else { return }
                    summary = .done(points)
                    AccessibilityNotification.Announcement(String(localized: "Summary ready")).post()
                } catch {
                    if summaryRun == token { summary = .failed(error.localizedDescription) }
                }
            }
        case .quiz:
            guard quiz == .idle else { return }
            quiz = .working(0)
            quizRun = token
            Task {
                do {
                    let text = await StudyGuide.text(for: scope, in: document)
                    let items = try await StudyGuide.quiz(of: text, using: model) { value in
                        if quizRun == token { quiz = .working(value) }
                    }
                    guard quizRun == token else { return }
                    quiz = .done(items)
                    AccessibilityNotification.Announcement(String(localized: "Questions ready")).post()
                } catch {
                    if quizRun == token { quiz = .failed(error.localizedDescription) }
                }
            }
        }
    }
}

/// One practice question as a small index card: the answer stays face down until it is asked for.
private struct QuestionCard: View {
    let number: Int
    let item: QuizItem
    let isShown: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Question \(number)")
                    .font(.footnote.weight(.bold).smallCaps())
                    .tracking(0.8)
                    .foregroundStyle(Color.labelInk)
                Spacer()
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.labelInkSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Leave Out Question \(number)"))
            }
            .padding(.leading, Space.x4)
            .frame(height: 36)
            VStack(alignment: .leading, spacing: Space.x3) {
                Text(item.question)
                    .displayTextFont(19, relativeTo: .title3)
                    .foregroundStyle(Color.labelInk)
                    .fixedSize(horizontal: false, vertical: true)
                if isShown {
                    Text(item.answer)
                        .font(.body)
                        .foregroundStyle(Color.labelInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Space.x3)
                        .overlay(alignment: .leading) { Rectangle().fill(CardStock.headRule.opacity(0.75)).frame(width: 2) }
                        .transition(.opacity)
                        .accessibilityIdentifier("guide.answer.\(number)")
                }
                Button(action: toggle) {
                    Text(isShown ? "Hide Answer" : "Show Answer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelInk)
                        .underline()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guide.show.\(number)")
            }
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { CardPaper(head: 36, ruling: 0) }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isShown)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide.question.\(number)")
    }
}

private extension View {
    /// A sheet of paper lying on the surface: the summary is written on one.
    func leaf() -> some View {
        let shape = RoundedRectangle.plate
        return background { shape.fill(Color.paper).overlay { shape.strokeBorder(Color.hairline, lineWidth: 1) } }
    }
}

extension EditorSession {
    /// Types a summary's points onto the current page as a text box, which can then be moved, restyled or deleted.
    func addStudyNotes(_ points: [String]) {
        guard !document.isReadOnly, document.pages.indices.contains(currentPage), !points.isEmpty else { return }
        let page = document.pages[currentPage]
        var box = TextBox(string: StudyGuide.listed(points))
        box.fontSize = 13
        let width = min(max(box.naturalWidth(limit: page.sheetSize.width * 0.7), 200), page.sheetSize.width * 0.7)
        addItem(.text(box), size: CGSize(width: width, height: box.height(width: width)), actionName: String(localized: "Add Summary"))
    }
}
