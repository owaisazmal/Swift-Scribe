import SwiftUI

/// Whether the owl plays at launch: never under tests, and only for the first scene of the process.
enum LaunchAnimation {
    @MainActor private static var claimed = false

    static func isEnabled(arguments: [String], underTest: Bool, firstScene: Bool) -> Bool {
        firstScene && !underTest && !arguments.contains("-storageRoot") && !arguments.contains("-skipLaunchAnimation")
    }

    /// True once per process; a second window starts with the library as it is.
    @MainActor static var isEnabled: Bool {
        let first = !claimed
        claimed = true
        return isEnabled(arguments: LaunchOptions.arguments, underTest: NSClassFromString("XCTestCase") != nil, firstScene: first)
    }
}

/// The owl on its moon over the paper while the app starts; once it has played and the app is ready it hands over to the library.
struct LaunchOverlay: View {
    let isReady: Bool
    /// The library should start fading in; `onFinished` follows once the tile has gone.
    let onHandOver: () -> Void
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose = Pose()
    @State private var tileOpacity = 0.0
    @State private var tileScale: CGFloat = 1
    @State private var ready = false
    @State private var holding = false
    @State private var handingOver = false

    static let minimumDuration = 1.45
    static let handOverDuration = 0.35

    private struct Pose {
        var moonSwing = -14.0
        var owlScale: CGFloat = 0.6
        var owlDrop: CGFloat = -0.05
        var owlOpacity = 0.0
        var blink = 0.0
        var pencilTilt = 0.0
        var sparkle = 0.0
        var twinkle = 0.0

        static let rest = Pose(moonSwing: 0, owlScale: 1, owlDrop: 0, owlOpacity: 1, sparkle: 1, twinkle: 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(min(geometry.size.width, geometry.size.height) * 0.42, 360)
            OwlLunaMark(moonSwing: pose.moonSwing, owlScale: pose.owlScale, owlOffset: CGSize(width: 0, height: pose.owlDrop * side),
                        owlOpacity: pose.owlOpacity, blink: pose.blink, pencilTilt: pose.pencilTilt, sparkle: pose.sparkle, twinkle: pose.twinkle)
                .frame(width: side, height: side)
                .scaleEffect(tileScale)
                .opacity(tileOpacity)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OwlLuna")
        .accessibilityAddTraits(.isImage)
        .onChange(of: isReady, initial: true) { _, isReady in
            ready = isReady
            if ready && holding { handOver() }
        }
        .task { await play() }
    }

    /// Each step waits from the one before, so a busy main thread at start-up delays the owl rather than skipping it ahead.
    private func play() async {
        var elapsed = 0.0
        if reduceMotion {
            pose = .rest
            withAnimation(.easeOut(duration: 0.25)) { tileOpacity = 1 }
        } else {
            tileScale = 0.94
            withAnimation(.easeOut(duration: 0.25)) { tileOpacity = 1; tileScale = 1 }
            let steps: [(Double, () -> Void)] = [
                (0.10, { withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { pose.moonSwing = 0 } }),
                (0.35, {
                    withAnimation(.easeOut(duration: 0.12)) { pose.owlOpacity = 1 }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { pose.owlScale = 1; pose.owlDrop = 0 }
                }),
                (0.50, { withAnimation(.easeOut(duration: 0.25)) { pose.sparkle = 1 } }),
                (0.60, { withAnimation(.easeOut(duration: 0.25)) { pose.twinkle = 1 } }),
                (0.85, { withAnimation(.easeIn(duration: 0.09)) { pose.blink = 1 } }),
                (0.90, {
                    withAnimation(.easeInOut(duration: 0.1)) { pose.pencilTilt = 8 }
                    withAnimation(.easeInOut(duration: 0.15)) { pose.sparkle = 0.4 }
                }),
                (0.95, { withAnimation(.easeOut(duration: 0.11)) { pose.blink = 0 } }),
                (1.00, {
                    withAnimation(.easeInOut(duration: 0.1)) { pose.pencilTilt = -8 }
                    withAnimation(.easeInOut(duration: 0.15)) { pose.twinkle = 0.4 }
                }),
                (1.10, {
                    withAnimation(.easeInOut(duration: 0.1)) { pose.pencilTilt = 8 }
                    withAnimation(.easeOut(duration: 0.2)) { pose.sparkle = 1 }
                }),
                (1.20, {
                    withAnimation(.easeInOut(duration: 0.1)) { pose.pencilTilt = -8 }
                    withAnimation(.easeOut(duration: 0.2)) { pose.twinkle = 1 }
                }),
                (1.30, { withAnimation(Motion.ribbon) { pose.pencilTilt = 0 } }),
            ]
            for (seconds, step) in steps {
                try? await Task.sleep(for: .milliseconds(Int((seconds - elapsed) * 1000)))
                guard !Task.isCancelled else { return }
                elapsed = seconds
                step()
            }
        }
        try? await Task.sleep(for: .milliseconds(Int((Self.minimumDuration - elapsed) * 1000)))
        guard !Task.isCancelled else { return }
        if ready {
            handOver()
        } else {
            holding = true
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pose.sparkle = 0.45 }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.3)) { pose.twinkle = 0.45 }
            }
        }
    }

    private func handOver() {
        guard !handingOver else { return }
        handingOver = true
        onHandOver()
        withAnimation(.easeOut(duration: Self.handOverDuration)) {
            tileOpacity = 0
            pose.sparkle = 1
            pose.twinkle = 1
            if !reduceMotion { tileScale = 0.96 }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(Int(Self.handOverDuration * 1000) + 30))
            onFinished()
        }
    }
}
