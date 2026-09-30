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
    var errorMessage: String?

    @ObservationIgnored private let document: NotebookDocument
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var currentFile: String?
    @ObservationIgnored private var timer: Timer?

    init(document: NotebookDocument) {
        self.document = document
        super.init()
        document.recorder = self
    }

    var recordings: [RecordingEntry] { document.manifest.recordings }
    var isReadOnly: Bool { document.isReadOnly }

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
        document.addRecording(RecordingEntry(id: UUID(), file: currentFile, createdAt: .now, duration: duration))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Playback would switch the shared audio session away from recording, so it waits until recording stops.
    func togglePlayback(_ recording: RecordingEntry) {
        if playingID == recording.id { return stopPlayback() }
        guard !isRecording else { return }
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
        } catch {
            errorMessage = String(localized: "This recording couldn't be played.")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
        playbackProgress = 0
        if !isRecording { stopTimer() }
    }

    /// Removes the entry; the audio file is cleaned up with the package's other unreferenced assets.
    func delete(_ recording: RecordingEntry) {
        if playingID == recording.id { stopPlayback() }
        document.removeRecording(recording.id)
    }

    func shutdown() {
        stopRecording()
        stopPlayback()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let recorder { elapsed = recorder.currentTime }
        if let player, player.duration > 0 { playbackProgress = player.currentTime / player.duration }
    }
}

extension NotebookRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlayback() }
    }
}
