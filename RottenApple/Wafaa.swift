import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - مدير الصوت
class SoundManager {
    static let shared = SoundManager()
    private var players: [String: AVAudioPlayer] = [:]
    private var movementPlayer: AVAudioPlayer?

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
        guard components.count == 2,
              let path = Bundle.main.path(forResource: String(components[0]), ofType: String(components[1])) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            players[name] = player
        } catch {
            print("Sound error: \(error.localizedDescription)")
        }
    }

    func startMovementSound(named name: String, volume: Float = 0.25) {
        guard movementPlayer == nil else {
            if movementPlayer?.isPlaying == false { movementPlayer?.play() }
            return
        }

        let components = name.split(separator: ".")
        guard components.count == 2,
              let path = Bundle.main.path(forResource: String(components[0]), ofType: String(components[1])) else {
            return
        }

        do {
            movementPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            movementPlayer?.numberOfLoops = -1
            movementPlayer?.volume = volume
            movementPlayer?.prepareToPlay()
            movementPlayer?.play()
        } catch {
            print("Movement sound error: \(error.localizedDescription)")
        }
    }

    func stopMovementSound() {
        movementPlayer?.stop()
        movementPlayer = nil
    }
}

// MARK: - نموذج جزيئات الترقيعات المحدث ليتطابق مع كود الورد
struct Confetti: Identifiable {
    let id = UUID()
    let color: Color
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 12
    var height: CGFloat = 16
    var rotation: Double = 0
    var opacity: Double = 1.0
}

// MARK: - واجهة اللعبة
struct Wafaa: View {
    // حالات اللعبة
    @State private var isPouring = false            // حالة صب القهوة
    @State private var cupX: CGFloat = -90           // موضع الفنجال الأفقي
    @State private var movingRight = true            // اتجاه حركة الفنجال
    @State private var isPausedAfterMiss = false     // إيقاف مؤقت عند الانسكاب خارج الفنجال
    @State private var gameState: GameState = .playing
    @State private var confettiList: [Confetti] = [] // قائمة الفرقعات
    
    @State private var enableMovementSound = true

    // محرك تحديث الإطارات للحركة
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    // مكان سقوط القهوة ونطاق الفوز المتناسق مع الفنجال
    let streamDropX: CGFloat = 115.0
    let targetRange: ClosedRange<CGFloat> = 70...125
    
    enum GameState {
        case playing, won
    }
    
    var body: some View {
        ZStack {
            // 1. الخلفية
            Image("background")
                .resizable()
                .ignoresSafeArea()
             
            // 2. ساحة اللعبة
            VStack {
                Spacer()
                 
                ZStack {
                    // النملة مع الدلة
                    Image("Ant")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 550, height: 360)
                        .offset(x: -35, y: -45)
                    
                    // مجرى القهوة
                    Image("coffeeStream")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 240)
                        .offset(x: 140, y: 26)
                        .opacity(isPouring ? 1.0 : 0.0)
                    
                    // الفنجال المتحرك بالأسفل
                    Image("coffee")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 135, height: 135)
                        .offset(x: cupX, y: 215)
                }
                .frame(height: 540)
                 
                Spacer()
                 
                // رسالة الفوز فقط
                VStack(spacing: 6) {
                    if gameState == .won {
                        Text("GOOD JOB! 🎉")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Spacer().frame(height: 50)
                    }
                }
                .padding(.bottom, 30)
            }
             
            // 3. فرقيعات الفوز الاحترافية المطابقة لكود الورد
            if gameState == .won {
                ForEach(confettiList) { c in
                    Rectangle()
                        .fill(c.color)
                        .frame(width: c.width, height: c.height)
                        .rotationEffect(.degrees(c.rotation))
                        .offset(x: c.x, y: c.y)
                        .opacity(c.opacity)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            switch gameState {
            case .playing:
                pourCoffee()
            case .won:
                resetGame()
            }
        }
        .onReceive(timer) { _ in
            guard gameState == .playing, !isPouring, !isPausedAfterMiss else { return }
             
            if enableMovementSound {
                SoundManager.shared.startMovementSound(named: "slide.mp3")
            }
             
            if movingRight {
                cupX += 2.4
                if cupX >= 120 { movingRight = false }
            } else {
                cupX -= 2.4
                if cupX <= -110 { movingRight = true }
            }
        }
        .onDisappear {
            SoundManager.shared.stopMovementSound()
        }
    }
    
    // MARK: - منطق الصب والتوقيت
    private func pourCoffee() {
        guard gameState == .playing, !isPouring, !isPausedAfterMiss else { return }
         
        isPouring = true
        SoundManager.shared.stopMovementSound()
         
        // اهتزاز لمس خفيف وصوت صب القهوة
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SoundManager.shared.playSound(named: "pour.mp3")
         
        let currentCupX = cupX
        let isWinningShot = targetRange.contains(currentCupX)
         
        // تثبيت الفنجال فوراً عند إصابة الهدف
        if isWinningShot {
            gameState = .won
        }
         
        // مدة تدفق مجرى القهوة
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPouring = false
             
            if isWinningShot {
                // الفوز: انتظار انتهاء صوت الصب بهدوء ثم تشغيل صوت وظهور الكونفيتي معاً
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    SoundManager.shared.playSound(named: "celebrate.mp3")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    triggerConfetti()
                }
            } else {
                // الانسكاب خارج الفنجال: هابتك الخسارة القوي والمطلوب
                isPausedAfterMiss = true
                 
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                 
                // وقفة زمنية قصيرة قبل العودة للحركة
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    isPausedAfterMiss = false
                }
            }
        }
    }
    
    // MARK: - دالة تشغيل الكونفيتي المطابقة لمنطق كود الورد
    private func triggerConfetti() {
        let colors: [Color] = [.pink, .yellow, .purple, .orange, .teal, .white, .red, .cyan]
        
        // تجهيز القطع بقيم ابتدائية قريبة من الفنجال/المنتصف
        confettiList = (0..<90).map { _ in
            Confetti(
                color: colors.randomElement() ?? .pink,
                x: CGFloat.random(in: -80...80),
                y: CGFloat.random(in: 120...180),
                width: CGFloat.random(in: 8...14),
                height: CGFloat.random(in: 13...20),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
        }
        
        // مرحلة الإطلاق للأعلى والانتشار بتنطيط سلس (EaseOut)
        withAnimation(.easeOut(duration: 0.5)) {
            for i in confettiList.indices {
                confettiList[i].x += CGFloat.random(in: -170...170)
                confettiList[i].y -= CGFloat.random(in: 230...450) // الارتفاع للأعلى
                confettiList[i].rotation += Double.random(in: -180...180)
            }
        }
        
        // مرحلة السقوط للأسفل ببطء مع التلاشي والدوران المستمر
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 2.2)) {
                for i in confettiList.indices {
                    confettiList[i].y += 650 // السقوط للأسفل
                    confettiList[i].x += CGFloat.random(in: -70...70)
                    confettiList[i].rotation += Double.random(in: 360...720)
                    confettiList[i].opacity = 0.0
                }
            }
        }
    }
    
    // MARK: - إعادة اللعبة بعد الفوز
    private func resetGame() {
        confettiList.removeAll()
        cupX = -90
        movingRight = true
        isPausedAfterMiss = false
        isPouring = false
        gameState = .playing
    }
}

#Preview {
    Wafaa()
}
