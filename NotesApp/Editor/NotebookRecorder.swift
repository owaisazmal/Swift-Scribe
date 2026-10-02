import AVFoundation
import Observation

/// Records and plays audio attached to a notebook. Files go into the package's `assets/`; entries into the manifest.
@MainActor
@Observable
final class NotebookRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var playingID: UUID?
    private(set) var playbackProgress: Double = 0
    /// How far into the recording playback is, and whether it is waiting there.
    private(set) var currentTime: TimeInterval = 0
    private(set) var isPaused = false
    var errorMessage: String?
    /// Called as playback moves, about ten times a second, and when it is moved by hand.
    @ObservationIgnored var onPlaybackTime: ((TimeInterval) -> Void)?
    @ObservationIgnored private var holdsAtEnd = false
    @ObservationIgnored private var recordingSince: Date?
    @ObservationIgnored private var inkedPages: Set<UUID> = []

    @ObservationIgnored private let document: NotebookDocument
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var currentFile: String?
    @ObservationIgnored private var timer: Timer?
    /// How far each transcription under way has got, by recording.
    private(set) var transcribing: [UUID: Double] = [:]
    @ObservationIgnored var transcriber: any SpeechTranscribing = Transcription.transcriber
    /// Called once a transcript has been written or removed, so search can pick it up.
    @ObservationIgnored var onTranscriptChange: (() -> Void)?
    @ObservationIgnored private var transcriptTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var transcripts: [String: Transcript] = [:]

    init(document: NotebookDocument) {
        self.document = document
        super.init()
        document.recorder = self
    }

    var recordings: [RecordingEntry] { document.manifest.recordings }
    var isReadOnly: Bool { document.isReadOnly }

    /// A page was written on. While recording, the entry remembers which, so a replay knows where to look.
    func noteInk(onPage pageID: UUID) {
        if isRecording { inkedPages.insert(pageID) }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !document.isReadOnly else { return }
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                errorMessage = String(localized: "Microphone access is off. Turn it on in Settings › Privacy & Security › Microphone.")
                return
            }
            do {
                stopPlayback()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                try FileManager.default.createDirectory(at: document.package.assetsDirectory, withIntermediateDirectories: true)
                let file = "\(UUID().uuidString).m4a"
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                let recorder = try AVAudioRecorder(url: document.package.assetURL(file), settings: settings)
                guard recorder.record() else { throw ImportError.unreadable }
                self.recorder = recorder
                currentFile = file
                recordingSince = .now
                inkedPages = []
                isRecording = true
                elapsed = 0
                startTimer()
            } catch {
                errorMessage = String(localized: "Recording couldn't start: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording() {
        guard let recorder, let currentFile else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.currentFile = nil
        isRecording = false
        stopTimer()
        var entry = RecordingEntry(id: UUID(), file: currentFile, createdAt: .now, duration: duration)
        entry.startedAt = recordingSince ?? Date.now.addingTimeInterval(-duration)
        entry.inkedPages = Array(inkedPages)
        recordingSince = nil
        document.addRecording(entry)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Playback would switch the shared audio session away from recording, so it waits until recording stops.
    func togglePlayback(_ recording: RecordingEntry) {
        if playingID == recording.id { return stopPlayback() }
        start(recording)
    }

    @discardableResult
    private func start(_ recording: RecordingEntry) -> Bool {
        guard !isRecording else { return false }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: document.package.assetURL(recording.file))
            player.delegate = self
            player.play()
            self.player = player
            playingID = recording.id
            startTimer()
            return true
        } catch {
            errorMessage = String(localized: "This recording couldn't be played.")
            return false
        }
    }

    /// Plays a recording from its start and stays on it when it ends, for replaying it with its ink.
    func beginReplay(_ recording: RecordingEntry) -> Bool {
        guard start(recording) else { return false }
        holdsAtEnd = true
        return true
    }

    func pause() {
        guard let player, !isPaused else { return }
        player.pause()
        isPaused = true
        report(player.currentTime)
    }

    func resume() {
        guard let player, isPaused else { return }
        if currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.play()
        isPaused = false
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let target = min(max(time, 0), player.duration)
        player.currentTime = min(target, max(player.duration - 0.01, 0))
        report(target)
    }

    private func report(_ time: TimeInterval) {
        currentTime = time
        if let player, player.duration > 0 { playbackProgress = time / player.duration }
        onPlaybackTime?(time)
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
        playbackProgress = 0
        currentTime = 0
        isPaused = false
        holdsAtEnd = false
        if !isRecording { stopTimer() }
    }

    fileprivate func playbackFinished() {
        guard holdsAtEnd, let player else { return stopPlayback() }
        isPaused = true
        report(player.duration)
    }

    /// Removes the entry; the audio file is cleaned up with the package's other unreferenced assets.
    func delete(_ recording: RecordingEntry) {
        if playingID == recording.id { stopPlayback() }
        cancelTranscription(recording.id)
        document.removeRecording(recording.id)
        guard recording.transcriptFile != nil else { return }
        let package = document.package, id = recording.id
        Task { [weak self] in
            await package.removeTranscriptText(id)
            self?.onTranscriptChange?()
        }
    }

    func shutdown() {
        stopRecording()
        stopPlayback()
        for id in Array(transcriptTasks.keys) { cancelTranscription(id) }
    }

    // MARK: Transcripts

    func transcript(for recording: RecordingEntry) -> Transcript? {
        guard let file = recording.transcriptFile else { return nil }
        if let held = transcripts[file] { return held }
        let read = document.package.readTranscript(file)
        transcripts[file] = read
        return read
    }

    /// Writes down what was said, on the device. The result replaces any transcript the recording already has.
    func transcribe(_ recording: RecordingEntry, locale: Locale) {
        guard !document.isReadOnly, transcriptTasks[recording.id] == nil else { return }
        let id = recording.id, url = document.package.assetURL(recording.file), transcriber = transcriber
        transcribing[id] = 0
        transcriptTasks[id] = Task { [weak self] in
            do {
                let transcript = try await transcriber.transcribe(url, locale: locale) { fraction in
                    Task { @MainActor in
                        guard let self, let current = self.transcribing[id] else { return }
                        self.transcribing[id] = max(current, fraction)
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                let file = try await self.document.package.writeTranscript(transcript, recordingID: id)
                self.transcripts[file] = transcript
                self.document.setTranscript(file, forRecording: id)
                self.onTranscriptChange?()
            } catch is CancellationError {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.transcribing[id] = nil
            self?.transcriptTasks[id] = nil
        }
    }

    func cancelTranscription(_ id: UUID) {
        transcriptTasks[id]?.cancel()
        transcriptTasks[id] = nil
        transcribing[id] = nil
    }

    func removeTranscript(_ recording: RecordingEntry) {
        guard !document.isReadOnly, recording.transcriptFile != nil else { return }
        document.setTranscript(nil, forRecording: recording.id)
        let package = document.package, id = recording.id
        Task { [weak self] in
            await package.removeTranscriptText(id)
            self?.onTranscriptChange?()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: player == nil ? 0.25 : 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let recorder { elapsed = recorder.currentTime }
        if let player, player.isPlaying { report(player.currentTime) }
    }
}

extension NotebookRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playbackFinished() }
    }
}
