import SwiftUI
import PencilKit

extension RecordingEntry {
    /// When the recording began. Entries made before this was kept only know when it ended.
    var startedAt: Date {
        get { extra["startedAt"]?.stringValue.flatMap(ManifestCodec.parseDate) ?? createdAt.addingTimeInterval(-duration) }
        set { extra["startedAt"] = ManifestCodec.encodeDate(newValue) }
    }

    /// The pages written on while it ran, so a replay needn't read every page. Nil on entries made before this was kept.
    var inkedPages: [UUID]? {
        get { extra["pages"]?.arrayValue?.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) } }
        set { extra["pages"] = newValue.map { .array($0.map { .string($0.uuidString) }) } }
    }

    /// The file among the assets that holds what was said, once the recording has been transcribed.
    var transcriptFile: String? {
        get { extra["transcript"]?.stringValue }
        set { extra["transcript"] = newValue.map(JSONValue.string) }
    }
}

/// When each stroke written during a recording was begun, measured from the start of the recording.
/// Nothing is stored for it: PencilKit dates every stroke, and those dates are compared with the recording's.
struct ReplayTimeline: Sendable, Equatable {
    struct Mark: Sendable, Hashable {
        let time: TimeInterval
        let page: UUID
        /// The stroke's place in its page's drawing.
        let stroke: Int
    }

    let recording: UUID
    let duration: TimeInterval
    /// In the order they were written.
    private(set) var marks: [Mark] = []
    private var byPage: [UUID: [Mark]] = [:]

    init(recording: RecordingEntry, drawings: [UUID: PKDrawing]) {
        self.recording = recording.id
        duration = recording.duration
        let start = recording.startedAt
        for (page, drawing) in drawings {
            for (index, stroke) in drawing.strokes.enumerated() {
                let time = stroke.path.creationDate.timeIntervalSince(start)
                guard time >= -0.5, time <= recording.duration + 0.5 else { continue }
                marks.append(Mark(time: min(max(time, 0), recording.duration), page: page, stroke: index))
            }
        }
        marks.sort { ($0.time, $0.stroke) < ($1.time, $1.stroke) }
        byPage = Dictionary(grouping: marks, by: \.page)
    }

    var isEmpty: Bool { marks.isEmpty }

    func hasInk(onPage page: UUID) -> Bool { byPage[page] != nil }

    /// How many of the recording's strokes have been written by `time`.
    func written(by time: TimeInterval) -> Int {
        var low = 0, high = marks.count
        while low < high {
            let middle = (low + high) / 2
            if marks[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The strokes on a page that are still to come at `time`.
    func pending(onPage page: UUID, at time: TimeInterval) -> Set<Int> {
        Set((byPage[page] ?? []).lazy.filter { $0.time > time }.map(\.stroke))
    }

    /// The page being written on at `time`: the one holding the latest stroke, or the first one before any ink.
    func page(at time: TimeInterval) -> UUID? {
        let count = written(by: time)
        return count > 0 ? marks[count - 1].page : marks.first?.page
    }

    func time(ofStroke stroke: Int, onPage page: UUID) -> TimeInterval? {
        byPage[page]?.first { $0.stroke == stroke }?.time
    }
}

enum ReplayInk {
    /// Ink that hasn't been written yet at this point of the replay is shown faintly, so the page's shape stays readable.
    static let faint: CGFloat = 0.16

    static func drawing(_ drawing: PKDrawing, pending: Set<Int>) -> PKDrawing {
        guard !pending.isEmpty else { return drawing }
        var strokes = drawing.strokes
        for index in pending where strokes.indices.contains(index) {
            let stroke = strokes[index]
            var ink = stroke.ink
            ink.color = ink.color.withAlphaComponent(ink.color.cgColor.alpha * faint)
            // A new stroke, not the old one with its ink changed: a canvas keeps what it has drawn for a stroke it knows.
            strokes[index] = PKStroke(ink: ink, path: stroke.path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
        }
        return PKDrawing(strokes: strokes)
    }

    /// The stroke under a point on the page, for jumping to when it was written.
    static func stroke(at point: CGPoint, in drawing: PKDrawing, reach: CGFloat = 14) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, stroke) in drawing.strokes.enumerated() where stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(point) {
            for sample in stroke.path.interpolatedPoints(by: .distance(5)) {
                let location = sample.location.applying(stroke.transform)
                let distance = max(0, hypot(location.x - point.x, location.y - point.y) - max(sample.size.width, sample.size.height) / 2)
                if distance <= reach, distance < best?.distance ?? .infinity { best = (index, distance) }
            }
        }
        return best?.index
    }
}

/// The transport along the bottom while a recording is replayed with its ink.
struct ReplayBar: View {
    let session: EditorSession
    /// Whether the transcript is showing beside the page; nil when there is none to show.
    var transcript: Bool?
    var toggleTranscript: () -> Void = {}
    let done: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scrubbing: Double?

    private var recorder: NotebookRecorder { session.recorder }

    private func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.time(pattern: .minuteSecond))
    }

    var body: some View {
        let duration = max(session.replay?.duration ?? 0, 0.1), time = min(scrubbing ?? recorder.currentTime, duration)
        let total = session.replay?.marks.count ?? 0, written = session.replay?.written(by: time) ?? 0
        HStack(spacing: Space.x2) {
            Button { recorder.isPaused ? recorder.resume() : recorder.pause() } label: {
                Label(recorder.isPaused ? "Play" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityIdentifier("editor.replay.play")
            if !dynamicTypeSize.isAccessibilitySize {
                Text(clock(time)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
            }
            Slider(value: Binding(get: { time }, set: { scrubbing = $0 }), in: 0...duration) { editing in
                if !editing, let scrubbing {
                    session.seekReplay(to: scrubbing)
                    self.scrubbing = nil
                }
            }
            .frame(minWidth: 140, idealWidth: 260, maxWidth: 320)
            .accessibilityLabel(Text("Position"))
            .accessibilityValue(Text("\(clock(time)) of \(clock(duration))"))
            .accessibilityIdentifier("editor.replay.position")
            if !dynamicTypeSize.isAccessibilitySize {
                Text(clock(duration)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.textSecondary)
            }
            if let transcript {
                Button(action: toggleTranscript) {
                    Label("Transcript", systemImage: "quote.bubble").symbolVariant(transcript ? .fill : .none)
                }
                .accessibilityValue(Text(transcript ? "Showing" : "Hidden"))
                .accessibilityIdentifier("editor.replay.transcript")
            }
            Rectangle().fill(Color.hairline).frame(width: 1, height: 24)
            Button("Done", action: done)
                .buttonStyle(.scribe(.primary, compact: true, inBar: true))
                .accessibilityIdentifier("editor.replay.done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Replay"))
        .accessibilityValue(Text(total == 0 ? String(localized: "No ink was written during this recording")
                                            : String(localized: "\(written) of \(total) strokes written")))
        .accessibilityIdentifier("editor.replay.bar")
        .onChange(of: scrubbing) { _, value in if let value { session.showReplay(at: value) } }
    }
}
