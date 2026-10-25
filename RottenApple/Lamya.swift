import SwiftUI
import AudioToolbox

// نموذج لبيانات كل بكرة خيط
struct YarnOption: Identifiable {
    let id = UUID()
    let imageName: String
    let color: Color
}

// هيكل صف الخيط المحاك
struct WovenLine: Identifiable {
    let id = UUID()
    let color: Color
    let yOffset: CGFloat
}

// عنصر المفرقعات (Confetti Particle)
struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var rotation: Double
    var opacity: Double
}

struct Lamya: View {
    let yarns: [YarnOption] = [
        YarnOption(imageName: "Red color", color: Color(red: 0.72, green: 0.28, blue: 0.24)),
        YarnOption(imageName: "Blue color", color: Color(red: 0.32, green: 0.48, blue: 0.72)),
        YarnOption(imageName: "Orange color", color: Color(red: 0.88, green: 0.58, blue: 0.30)),
        YarnOption(imageName: "Green color", color: Color(red: 0.42, green: 0.58, blue: 0.40))
    ]
    
    @State private var wovenLines: [WovenLine] = []
    @State private var usedYarnNames: Set<String> = []
    
    // حالة اكتمال الحياكة والتحول
    @State private var showFinalSadu = false
    @State private var loomScale: CGFloat = 1.0
    
    // مصفوفة المفرقعات
    @State private var confettiParticles: [ConfettiParticle] = []
    
    // حدود حركة العنكبوت
    private let leftSpiderX: CGFloat = -94
    private let rightSpiderX: CGFloat = 90
    
    @State private var spiderX: CGFloat = -94
    @State private var spiderY: CGFloat = 10
    @State private var currentLineWidth: CGFloat = 0
    @State private var isWeavingRight = true
    @State private var activeYarnColor: Color = .clear
    @State private var isWeaving = false
    
    // مقاسات الخيوط
    private let lineWidth: CGFloat = 189
    private let lineHeight: CGFloat = 2.0
    private let stepY: CGFloat = 2.4
    private let linesPerYarn = 6
    
    private let startY: CGFloat = 23.0
    private let lineOffsetX: CGFloat = -6
    
    private func getLineY(for index: Int) -> CGFloat {
        return startY - (CGFloat(index) * stepY)
    }
    
    var body: some View {
        ZStack {
            // 1. الخلفية
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // 2. النول مع الخيوط والتحول الكامل
                ZStack {
                    // النول الأساسي الأول
                    Image("Sadu")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320)
                        .opacity(showFinalSadu ? 0.0 : 1.0)
                    
                    // صورة السدو النهائي المكتمل (مزاحة لليمين لتتوسط النول)
                    Image("Sadu UP")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320)
                        .offset(x: 10)
                        .opacity(showFinalSadu ? 1.0 : 0.0)
                    
                    // الخيوط والعنكبوت: تظهر فقط أثناء الحياكة وتُزال تماماً عند ظهور السدو الثاني
                    if !showFinalSadu {
                        ForEach(wovenLines) { line in
                            Rectangle()
                                .fill(line.color)
                                .frame(width: lineWidth, height: lineHeight)
                                .shadow(color: .black.opacity(0.12), radius: 0.3, y: 0.4)
                                .offset(x: lineOffsetX, y: line.yOffset)
                        }
                        
                        // الخيط الجاري نسجه حالياً
                        if isWeaving {
                            HStack(spacing: 0) {
                                if !isWeavingRight {
                                    Spacer(minLength: 0)
                                }
                                Rectangle()
                                    .fill(activeYarnColor)
                                    .frame(width: currentLineWidth, height: lineHeight)
                                    .shadow(color: .black.opacity(0.12), radius: 0.3, y: 0.4)
                                if isWeavingRight {
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(width: lineWidth)
                            .offset(x: lineOffsetX, y: spiderY + 10)
                        }
                        
                        // العنكبوت
                        Image("Spider")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .offset(x: spiderX, y: spiderY)
                    }
                }
                .scaleEffect(loomScale)
                
                Spacer()
                
                // 3. أزرار بكرات الخيوط بالأسفل
                HStack(spacing: 16) {
                    ForEach(yarns) { yarn in
                        let isUsed = usedYarnNames.contains(yarn.imageName)
                        // عند اكتمال السدو الثاني تعود الألوان طبيعية 100%
                        let shouldDim = isUsed && !showFinalSadu
                        
                        Button(action: {
                            weaveBatch(yarn: yarn)
                        }) {
                            Image(yarn.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 65, height: 65)
                                .opacity(shouldDim ? 0.35 : 1.0)
                                .grayscale(shouldDim ? 0.8 : 0.0)
                                .animation(.easeInOut(duration: 0.4), value: showFinalSadu)
                        }
                        .disabled(isWeaving || isUsed || showFinalSadu)
                    }
                }
                .padding(.bottom, 36)
            }
            
            // 4. طبقة المفرقعات (Confetti)
            ForEach(confettiParticles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: 9, height: 9)
                    .scaleEffect(p.scale)
                    .rotationEffect(.degrees(p.rotation))
                    .opacity(p.opacity)
                    .position(x: p.x, y: p.y)
            }
        }
        .onAppear {
            spiderY = getLineY(for: 0) - 10
        }
    }
    
    // نسج سطور البكرة الحالية (6 سطور)
    private func weaveBatch(yarn: YarnOption) {
        guard !isWeaving, !usedYarnNames.contains(yarn.imageName) else { return }
        isWeaving = true
        usedYarnNames.insert(yarn.imageName)
        activeYarnColor = yarn.color
        
        weaveStep(step: 0, totalSteps: linesPerYarn, yarn: yarn)
    }
    
    private func weaveStep(step: Int, totalSteps: Int, yarn: YarnOption) {
        guard step < totalSteps else {
            isWeaving = false
            currentLineWidth = 0
            
            if usedYarnNames.count >= yarns.count {
                triggerCompletion()
            }
            return
        }
        
        let targetIndex = wovenLines.count
        let targetY = getLineY(for: targetIndex)
        let goRight = (step % 2 == 0)
        
        isWeavingRight = goRight
        spiderY = targetY - 10
        spiderX = goRight ? leftSpiderX : rightSpiderX
        currentLineWidth = 0
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        withAnimation(.linear(duration: 0.22)) {
            spiderX = goRight ? rightSpiderX : leftSpiderX
            currentLineWidth = lineWidth
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            wovenLines.append(WovenLine(color: yarn.color, yOffset: targetY))
            currentLineWidth = 0
            weaveStep(step: step + 1, totalSteps: totalSteps, yarn: yarn)
        }
    }
    
    // اكتمال الحياكة والانتقال مع التكبير والمفرقعات
    private func triggerCompletion() {
        // صعود العنكبوت للأعلى
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            spiderX = 0
            spiderY = -95
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.35)) {
                showFinalSadu = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                    loomScale = 1.15
                }
                
                spawnConfetti()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }
    
    // إنشاء المفرقعات
    private func spawnConfetti() {
        let colors: [Color] = [
            Color(red: 0.72, green: 0.28, blue: 0.24),
            Color(red: 0.32, green: 0.48, blue: 0.72),
            Color(red: 0.88, green: 0.58, blue: 0.30),
            Color(red: 0.42, green: 0.58, blue: 0.40),
            .yellow,
            .white
        ]
        
        let screenWidth = UIScreen.main.bounds.width
        let centerY = UIScreen.main.bounds.height * 0.42
        
        var newParticles: [ConfettiParticle] = []
        for _ in 0..<50 {
            let startX = screenWidth * 0.5 + CGFloat.random(in: -35...35)
            let particle = ConfettiParticle(
                color: colors.randomElement() ?? .orange,
                x: startX,
                y: centerY,
                scale: CGFloat.random(in: 0.6...1.4),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
            newParticles.append(particle)
        }
        confettiParticles = newParticles
        
        for i in confettiParticles.indices {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 90...220)
            let targetX = confettiParticles[i].x + cos(angle) * distance
            let targetY = confettiParticles[i].y + sin(angle) * distance + 30
            
            withAnimation(.easeOut(duration: Double.random(in: 0.8...1.3))) {
                confettiParticles[i].x = targetX
                confettiParticles[i].y = targetY
                confettiParticles[i].rotation += Double.random(in: 90...360)
                confettiParticles[i].opacity = 0.0
            }
        }
    }
}

#Preview {
    Lamya()
}
