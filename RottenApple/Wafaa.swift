import SwiftUI
import Combine

// جزيئات الترقيعات عند الفوز
struct Confetti: Identifiable {
    let id = UUID()
    let color: Color
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacity: Double = 1.0
}

struct Wafaa: View {
    // MARK: - حالات اللعبة
    @State private var isPouring = false             // هل تصب الآن؟
    @State private var cupX: CGFloat = -90           // حركة الفنجال يمين ويسار
    @State private var movingRight = true            // اتجاه حركة الفنجال
    @State private var gameState: GameState = .playing
    @State private var confettiList: [Confetti] = [] // الترقيعات
    
    // محرك حركة الفنجال التلقائية
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    // مكان سقوط القهوة ونطاق الفوز المتناسق مع الفنجال الكبير
    let streamDropX: CGFloat = 115.0
    let targetRange: ClosedRange<CGFloat> = 70...125
    
    enum GameState {
        case playing, won, lost
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
                    // النملة مع الدلة بحجمكِ المعتمد
                    Image("Ant")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 550, height: 360)
                        .offset(x: -35, y: -45)
                    
                    // مجرى القهوة المضبوط بمقاسكِ وإحداثياتكِ
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
                
                // رسائل النتيجة بعد الصب
                VStack(spacing: 6) {
                    if gameState == .lost {
                        Text("Almost had it! 💥")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.red)
                        
                        Text("Tap anywhere to try again")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    } else if gameState == .won {
                        Text("GOOD JOB! 🎉")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Spacer().frame(height: 50)
                    }
                }
                .padding(.bottom, 30)
            }
            
            // 3. فرقيعات الفوز تغطي كامل الشاشة
            if gameState == .won {
                ForEach(confettiList) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 12, height: 12)
                        .offset(x: c.x, y: c.y)
                        .opacity(c.opacity)
                }
                .allowsHitTesting(false)
            }
        }
        // لمس الشاشة للصب أو لإعادة اللعب
        .contentShape(Rectangle())
        .onTapGesture {
            switch gameState {
            case .playing:
                pourCoffee()
            case .won, .lost:
                resetGame()
            }
        }
        // حركة الفنجال المحصورة داخل الشاشة
        .onReceive(timer) { _ in
            guard gameState == .playing else { return }
            
            if movingRight {
                cupX += 2.4
                if cupX >= 120 { movingRight = false }
            } else {
                cupX -= 2.4
                if cupX <= -110 { movingRight = true }
            }
        }
    }
    
    // فحص الصب
    private func pourCoffee() {
        guard gameState == .playing, !isPouring else { return }
        
        isPouring = true
        let currentCupX = cupX
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if targetRange.contains(currentCupX) {
                gameState = .won
                triggerConfetti()
            } else {
                gameState = .lost
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPouring = false
            }
        }
    }
    
    // تشغيل الترقيعات على مستوى الشاشة بالكامل
    private func triggerConfetti() {
        let colors: [Color] = [.orange, .yellow, .pink, .green, .purple, .cyan, .red, .blue]
        
        // توليد 60 قطعة فرقيعات تنتشر في كل الشاشة
        confettiList = (0..<60).map { _ in
            Confetti(
                color: colors.randomElement() ?? .yellow,
                x: CGFloat.random(in: -160...160),
                y: CGFloat.random(in: -300...(-100)),
                opacity: 1.0
            )
        }
        
        withAnimation(.easeOut(duration: 1.2)) {
            for i in confettiList.indices {
                confettiList[i].x += CGFloat.random(in: -60...60)
                confettiList[i].y += CGFloat.random(in: 200...450) // تساقط نحو الأسفل عبر الشاشة
                confettiList[i].opacity = 0.0
            }
        }
    }
    
    // إعادة المحاولة
    private func resetGame() {
        confettiList.removeAll()
        cupX = -90
        movingRight = true
        gameState = .playing
        isPouring = false
    }
}

#Preview {
    Wafaa()
}
