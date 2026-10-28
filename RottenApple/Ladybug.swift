import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - مدير صوت اللعبة
class LadybugSoundManager {
    static let shared = LadybugSoundManager()
    private var players: [String: AVAudioPlayer] = [:]
    private var stepPlayer: AVAudioPlayer?

    private init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }

    func playSound(named name: String) {
        let components = name.split(separator: ".")
        let baseName = String(components[0])
        let ext = components.count > 1 ? String(components[1]) : "mp3"

        guard let path = Bundle.main.path(forResource: baseName, ofType: ext) else { return }

        let url = URL(fileURLWithPath: path)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            players[name] = player
        } catch {
            print("Playback error: \(error.localizedDescription)")
        }
    }

    func startStepLoop(named name: String = "bugSteps.mp3") {
        guard stepPlayer == nil else {
            if stepPlayer?.isPlaying == false { stepPlayer?.play() }
            return
        }

        let components = name.split(separator: ".")
        let baseName = String(components[0])
        let ext = components.count > 1 ? String(components[1]) : "mp3"

        guard let path = Bundle.main.path(forResource: baseName, ofType: ext) else { return }

        do {
            stepPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            stepPlayer?.numberOfLoops = -1
            stepPlayer?.volume = 0.5
            stepPlayer?.prepareToPlay()
            stepPlayer?.play()
        } catch {
            print("Steps loop error: \(error.localizedDescription)")
        }
    }

    func stopStepLoop() {
        stepPlayer?.stop()
        stepPlayer = nil
    }
}

// MARK: - جزيئات كونفيتي الفوز
struct LadybugConfetti: Identifiable {
    let id = UUID()
    let color: Color
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacity: Double = 1.0
}

// MARK: - مسار ناعم (Catmull-Rom) بطول قوس ثابت
struct SmoothPath {
    let samples: [CGPoint]
    let cumulative: [CGFloat]
    let totalLength: CGFloat

    /// inset: يقرّب النقاط من خط المنتصف (قلّله لو الدعسوقة تلمس الحافة)
    init(points: [CGPoint], samplesPerSegment: Int = 24, inset: CGFloat = 0.9) {
        let pts = points.map { CGPoint(x: $0.x * inset, y: $0.y) }
        let p = [pts.first!] + pts + [pts.last!]
        var out: [CGPoint] = []

        for i in 1..<(p.count - 2) {
            let p0 = p[i-1], p1 = p[i], p2 = p[i+1], p3 = p[i+2]
            for s in 0..<samplesPerSegment {
                let t = CGFloat(s) / CGFloat(samplesPerSegment)
                let t2 = t * t, t3 = t2 * t
                func calc(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2*b) + (-a + c)*t + (2*a - 5*b + 4*c - d)*t2 + (-a + 3*b - 3*c + d)*t3)
                }
                out.append(CGPoint(x: calc(p0.x, p1.x, p2.x, p3.x),
                                   y: calc(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(pts.last!)

        var cum: [CGFloat] = [0]
        for i in 1..<out.count {
            cum.append(cum[i-1] + hypot(out[i].x - out[i-1].x, out[i].y - out[i-1].y))
        }
        samples = out
        cumulative = cum
        totalLength = cum.last!
    }

    /// موقع النقطة عند progress (0...1)
    func point(at progress: CGFloat) -> CGPoint {
        let target = min(max(progress, 0), 1) * totalLength
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let seg = cumulative[i] - cumulative[i-1]
        let f = seg > 0 ? (target - cumulative[i-1]) / seg : 0
        return CGPoint(x: samples[i-1].x + (samples[i].x - samples[i-1].x) * f,
                       y: samples[i-1].y + (samples[i].y - samples[i-1].y) * f)
    }

    /// أقرب progress على المسار لنقطة معينة، ضمن نافذة حول progress الحالي
    func nearestProgress(to target: CGPoint, around current: CGFloat, window: CGFloat) -> CGFloat {
        let lower = max(current - window, 0) * totalLength
        let upper = min(current + window, 1) * totalLength
        var best = current
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in samples.indices where cumulative[i] >= lower && cumulative[i] <= upper {
            let d = hypot(samples[i].x - target.x, samples[i].y - target.y)
            if d < bestDist {
                bestDist = d
                best = cumulative[i] / totalLength
            }
        }
        return best
    }
}

// MARK: - الواجهة الرئيسية للعبة
struct LadybugGameView: View {
    private let path: SmoothPath

    @State private var progress: CGFloat = 0.0
    @State private var lastProgress: CGFloat = 0.0
    @State private var grabOffset: CGPoint? = nil
    @State private var lastHapticProgress: CGFloat = 0.0

    // حالات الفوز والأنيميشن
    @State private var hasWon: Bool = false
    @State private var isDanceTilted: Bool = false
    @State private var isDanceScaled: Bool = false
    @State private var confettiList: [LadybugConfetti] = []

    // محركات الاهتزاز
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let successHaptic = UINotificationFeedbackGenerator()

    init() {
        // نقاط منتصف المسار
        path = SmoothPath(points: [
            CGPoint(x: 4,   y: 341),   // البداية أسفل الباث
            CGPoint(x: 2,   y: 287),
            CGPoint(x: 12,  y: 247),
            CGPoint(x: 56,  y: 216),
            CGPoint(x: 88,  y: 184),   // انعطاف يمين أول
            CGPoint(x: 95,  y: 148),
            CGPoint(x: 60,  y: 124),
            CGPoint(x: -4,  y: 120),
            CGPoint(x: -60, y: 116),
            CGPoint(x: -99, y: 88),    // انعطاف يسار
            CGPoint(x: -68, y: 58),
            CGPoint(x: 4,   y: 50),
            CGPoint(x: 68,  y: 41),
            CGPoint(x: 95,  y: 13),    // انعطاف يمين ثاني
            CGPoint(x: 52,  y: -17),
            CGPoint(x: -20, y: -23),
            CGPoint(x: -76, y: -35),
            CGPoint(x: -91, y: -63),   // انعطاف يسار أخير
            CGPoint(x: -60, y: -103),
            CGPoint(x: -16, y: -126)   // مدخل بيت التفاحة
        ])
    }

    private var currentPosition: CGPoint {
        hasWon ? CGPoint(x: 0, y: 120) : path.point(at: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. الخلفية
                Image("buground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // 2. المسار المتعرج
                if !hasWon {
                    Image("path")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 620)
                        .offset(y: 30)
                        .transition(.opacity)
                }

                // 3. بيت التفاحة
                Image("home")
                    .resizable()
                    .scaledToFit()
                    .frame(width: hasWon ? 330 : 170, height: hasWon ? 330 : 170)
                    .offset(x: 20, y: hasWon ? -40 : -245)

                // 4. الدعسوقة
                Image("ladybug")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 65, height: 65)
                    .scaleEffect(hasWon ? (isDanceScaled ? 1.25 : 0.9) : 1.0)
                    .rotationEffect(.degrees(hasWon ? (isDanceTilted ? 15 : -15) : 0))
                    .offset(x: currentPosition.x, y: currentPosition.y)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("game"))
                            .onChanged { value in
                                guard !hasWon else { return }

                                let center = CGPoint(x: geometry.size.width / 2,
                                                     y: geometry.size.height / 2)
                                let finger = CGPoint(x: value.location.x - center.x,
                                                     y: value.location.y - center.y)

                                // عند بداية اللمس نحفظ الفرق بين الإصبع ومركز الدعسوقة لمنع القفزة
                                if grabOffset == nil {
                                    grabOffset = CGPoint(x: finger.x - currentPosition.x,
                                                         y: finger.y - currentPosition.y)
                                }
                                let offsetValue = grabOffset ?? .zero
                                let target = CGPoint(x: finger.x - offsetValue.x,
                                                     y: finger.y - offsetValue.y)

                                progress = path.nearestProgress(to: target, around: progress, window: 0.06)

                                LadybugSoundManager.shared.startStepLoop(named: "bugSteps.mp3")
                                if abs(progress - lastHapticProgress) > 0.012 {
                                    lightHaptic.impactOccurred(intensity: 0.35)
                                    lastHapticProgress = progress
                                }

                                if progress >= 0.98 {
                                    triggerWin()
                                }
                            }
                            .onEnded { _ in
                                grabOffset = nil
                                guard !hasWon else { return }
                                lastProgress = progress
                                LadybugSoundManager.shared.stopStepLoop()
                            }
                    )

                // 5. احتفالية الفوز
                if hasWon {
                    ForEach(confettiList) { c in
                        Circle()
                            .fill(c.color)
                            .frame(width: 12, height: 12)
                            .offset(x: c.x, y: c.y)
                            .opacity(c.opacity)
                    }
                    .allowsHitTesting(false)

                    VStack {
                        Spacer()

                        Text("WELCOME HOME! 🍎🎉")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.red)
                            .shadow(color: .black.opacity(0.35), radius: 10, x: 5, y: 10)
                            .padding(.bottom, 140)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: "game")
            .contentShape(Rectangle())
            .onTapGesture {
                if hasWon {
                    resetGame()
                }
            }
            .onAppear {
                lightHaptic.prepare()
                successHaptic.prepare()
            }
            .onDisappear {
                LadybugSoundManager.shared.stopStepLoop()
            }
        }
    }

    private func triggerWin() {
        LadybugSoundManager.shared.stopStepLoop()

        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            hasWon = true
            progress = 1.0
        }

        LadybugSoundManager.shared.playSound(named: "celebrate.mp3")
        successHaptic.notificationOccurred(.success)

        withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) {
            isDanceTilted = true
            isDanceScaled = true
        }

        let colors: [Color] = [.red, .yellow, .orange, .green, .pink, .purple, .cyan]
        confettiList = (0..<65).map { _ in
            LadybugConfetti(
                color: colors.randomElement() ?? .yellow,
                x: CGFloat.random(in: -150...150),
                y: CGFloat.random(in: -200...100),
                opacity: 1.0
            )
        }

        withAnimation(.easeOut(duration: 1.4)) {
            for i in confettiList.indices {
                confettiList[i].x += CGFloat.random(in: -80...80)
                confettiList[i].y += CGFloat.random(in: 200...400)
                confettiList[i].opacity = 0.0
            }
        }
    }

    private func resetGame() {
        withAnimation(.easeInOut(duration: 0.4)) {
            hasWon = false
            isDanceTilted = false
            isDanceScaled = false
            confettiList.removeAll()
            progress = 0.0
            lastProgress = 0.0
            grabOffset = nil
            lastHapticProgress = 0.0
        }
    }
}

#Preview {
    LadybugGameView()
}
