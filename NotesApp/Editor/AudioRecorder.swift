import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRecorder: NSObject {
    private(set) var recordings: [Recording]
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var playingID: UUID?
    private(set) var playbackProgress: Double = 0
    var errorMessage: String?

    @ObservationIgnored private let notebook: Notebook
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var currentFile: String?
    @ObservationIgnored private var timer: Timer?

    init(notebook: Notebook) {
        self.notebook = notebook
        self.recordings = notebook.recordings
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                errorMessage = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone."
                return
            }
            do {
                stopPlayback()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                let file = "\(UUID().uuidString).m4a"
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                let recorder = try AVAudioRecorder(url: NotebookStore.assetURL(file, notebook: notebook.id), settings: settings)
                guard recorder.record() else { throw ImportError.unreadable }
                self.recorder = recorder
                currentFile = file
                isRecording = true
                elapsed = 0
                startTimer()
            } catch {
                errorMessage = "Recording couldn't start: \(error.localizedDescription)"
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
        let recording = Recording(fileName: currentFile, createdAt: .now, duration: duration)
        recordings.append(recording)
        notebook.recordings = recordings
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlayback(_ recording: Recording) {
        if playingID == recording.id {
            stopPlayback()
            return
        }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: NotebookStore.assetURL(recording.fileName, notebook: notebook.id))
            player.delegate = self
            player.play()
            self.player = player
            playingID = recording.id
            startTimer()
        } catch {
            errorMessage = "This recording couldn't be played."
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
        playbackProgress = 0
        if !isRecording { stopTimer() }
    }

    func delete(_ recording: Recording) {
        if playingID == recording.id { stopPlayback() }
        try? FileManager.default.removeItem(at: NotebookStore.assetURL(recording.fileName, notebook: notebook.id))
        recordings.removeAll { $0.id == recording.id }
        notebook.recordings = recordings
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

extension AudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlayback() }
    }
}
