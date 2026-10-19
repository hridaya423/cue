import SwiftUI

/// The striped `cue` wordmark from the launch film: Geist Bold cut into 9 rows of capsules
/// (launch/cue-ad/assets/film19/parts/2-mark.js). The stripes draw in left to right like a
/// selection, lean with the pointer, and a light sweep crosses them (`Wordmark.metal`). One clock drives it all.
struct Wordmark: View {
    var height: CGFloat
    /// -1…1: where the pointer is across the window. Rows shear a few points toward it.
    var lean: CGFloat = 0
    /// Sweep every few seconds (welcome) or once per `replay` change (first smart paste).
    var loops = false
    var replay = 0

    @State private var start = Date()
    @State private var animating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let draw = 0.7
    private static let sweepAt = 0.8
    private static let travel = 1.4
    private static let period = 6.0

    private struct Run { let row: Int; let from: CGFloat; let to: CGFloat }
    private static let aspect: CGFloat = 2.8295
    private static let rows = 9
    private static let runs: [Run] = [
        .init(row: 0, from: 0.0857, to: 0.2597), .init(row: 0, from: 0.3481, to: 0.4431),
        .init(row: 0, from: 0.5529, to: 0.6479), .init(row: 0, from: 0.7470, to: 0.9197),
        .init(row: 1, from: 0.0375, to: 0.3066), .init(row: 1, from: 0.3481, to: 0.4431),
        .init(row: 1, from: 0.5529, to: 0.6479), .init(row: 1, from: 0.7028, to: 0.9639),
        .init(row: 2, from: 0.0147, to: 0.1191), .init(row: 2, from: 0.2222, to: 0.3280),
        .init(row: 2, from: 0.3481, to: 0.4431), .init(row: 2, from: 0.5529, to: 0.6479),
        .init(row: 2, from: 0.6801, to: 0.7791), .init(row: 2, from: 0.8902, to: 0.9853),
        .init(row: 3, from: 0.0027, to: 0.1004), .init(row: 3, from: 0.3481, to: 0.4431),
        .init(row: 3, from: 0.5529, to: 0.6479), .init(row: 3, from: 0.6680, to: 0.7644),
        .init(row: 3, from: 0.9023, to: 0.9960),
        .init(row: 4, from: 0.0000, to: 0.0964), .init(row: 4, from: 0.3481, to: 0.4431),
        .init(row: 4, from: 0.5529, to: 0.6479), .init(row: 4, from: 0.6653, to: 1.0000),
        .init(row: 5, from: 0.0027, to: 0.1004), .init(row: 5, from: 0.2383, to: 0.3079),
        .init(row: 5, from: 0.3481, to: 0.4431), .init(row: 5, from: 0.5515, to: 0.6479),
        .init(row: 5, from: 0.6680, to: 0.7644),
        .init(row: 6, from: 0.0147, to: 0.1191), .init(row: 6, from: 0.2236, to: 0.3280),
        .init(row: 6, from: 0.3494, to: 0.4525), .init(row: 6, from: 0.5382, to: 0.6479),
        .init(row: 6, from: 0.6801, to: 0.7791), .init(row: 6, from: 0.8929, to: 0.9920),
        .init(row: 7, from: 0.0375, to: 0.3066), .init(row: 7, from: 0.3614, to: 0.5582),
        .init(row: 7, from: 0.5596, to: 0.6479), .init(row: 7, from: 0.7015, to: 0.9719),
        .init(row: 8, from: 0.0830, to: 0.2610), .init(row: 8, from: 0.3909, to: 0.5288),
        .init(row: 8, from: 0.5609, to: 0.6479), .init(row: 8, from: 0.7470, to: 0.9264),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !animating)) { tl in
            let t = reduceMotion ? 10 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let pitch = size.height / CGFloat(Self.rows)
                for run in Self.runs {
                    let delay = Double(run.row) * 0.035 + Double(run.from) * 0.22
                    let p = min(max((t - delay) / Self.draw, 0), 1)
                    guard p > 0 else { continue }
                    let eased = 1 - pow(1 - p, 4)
                    let shear = lean * CGFloat(run.row - Self.rows / 2) * size.height * 0.012
                    let rect = CGRect(x: run.from * size.width + shear, y: CGFloat(run.row) * pitch + pitch * 0.19,
                                      width: (run.to - run.from) * size.width * eased, height: pitch * 0.62)
                    ctx.opacity = eased
                    ctx.fill(Capsule().path(in: rect), with: .color(OBTheme.action))
                }
            }
            .visualEffect { view, proxy in
                view.colorEffect(ShaderLibrary.bundle(.module).wordmarkSweep(
                    .float2(proxy.size), .float(t - Self.sweepAt),
                    .float(loops ? Self.period : 1e6), .float(Self.travel)))
            }
        }
        .frame(width: height * Self.aspect, height: height)
        .accessibilityElement()
        .accessibilityLabel("Cue")
        .accessibilityAddTraits(.isHeader)
        .onChange(of: replay) { _, _ in start = Date() }
        .task(id: "\(replay) \(loops)") { await tick() }
    }

    /// The clock runs only while something moves: the draw-in, then each sweep.
    private func tick() async {
        func wait(until t: Double) async -> Bool {
            try? await Task.sleep(for: .seconds(max(0, t + start.timeIntervalSinceNow)))
            return !Task.isCancelled
        }
        animating = true
        var sweep = Self.sweepAt
        while await wait(until: sweep + Self.travel + 0.05) {
            animating = false
            guard loops else { return }
            sweep += Self.period
            guard await wait(until: sweep - 0.05) else { return }
            animating = true
        }
    }
}

extension Wordmark: @preconcurrency Animatable {
    var animatableData: CGFloat {
        get { lean }
        set { lean = newValue }
    }
}
