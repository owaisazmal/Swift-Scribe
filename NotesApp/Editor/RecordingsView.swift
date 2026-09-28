import SwiftUI

struct RecordingsView: View {
    let recorder: AudioRecorder

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(recorder.recordings.enumerated()), id: \.element.id) { index, recording in
                    HStack(spacing: 12) {
                        Button { recorder.togglePlayback(recording) } label: {
                            Image(systemName: recorder.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(recorder.playingID == recording.id ? "Stop" : "Play")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recording \(index + 1)").font(.body.weight(.medium))
                            Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if recorder.playingID == recording.id {
                                ProgressView(value: recorder.playbackProgress)
                            }
                        }
                        Spacer()
                        Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { recorder.delete(recording) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if recorder.recordings.isEmpty {
                    ContentUnavailableView("No Recordings", systemImage: "waveform",
                                           description: Text("Tap the microphone to record a lecture or meeting alongside your notes."))
                }
            }
        }
    }
}
