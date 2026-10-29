import SwiftUI
import AVFoundation
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
    var yOffset: CGFloat
}

// عنصر المفرقعات (Confetti Particle) المحدث ليتطابق تماماً
struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 12
    var height: CGFloat = 16
    var rotation: Double = 0
    var opacity: Double = 1.0
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
    
    // مقاسات الشاشة للحفاظ على التوافق
    @State private var screenSize: CGSize = .zero
    
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
    
    // مقاسات الخيوط النسيجية
    private let lineWidth: CGFloat = 189
    private let lineHeight: CGFloat = 2.0
    private let stepY: CGFloat = 2.3
    private let linesPerYarn = 6
    
    private let startY: CGFloat = 23.0
    private let lineOffsetX: CGFloat = -6
    
    // مشغل الصوت
    @State private var audioPlayer: AVAudioPlayer?
    
    private func getLineY(for index: Int) -> CGFloat {
        return startY - (CGFloat(index) * stepY)
    }
    
    var body: some View {
        GeometryReader { geometry in
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
                        
                        // صورة السدو النهائي المكتمل (متوسطة في المنتصف تماماً)
                        Image("Sadu UP")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 320)
                            .opacity(showFinalSadu ? 1.0 : 0.0)
                        
                        // الخيوط والعنكبوت: تظهر فقط أثناء الحياكة
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
                    
                    // 3. أزرار بكرات الخيوط
                    HStack(spacing: 12) {
                        ForEach(yarns) { yarn in
                            let isUsed = usedYarnNames.contains(yarn.imageName)
                            let shouldDim = isUsed && !showFinalSadu
                            
                            Button(action: {
                                let selectionGen = UISelectionFeedbackGenerator()
                                selectionGen.selectionChanged()
                                playSound(named: "click")
                                weaveBatch(yarn: yarn)
                            }) {
                                Image(yarn.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .opacity(shouldDim ? 0.35 : 1.0)
                                    .grayscale(shouldDim ? 0.8 : 0.0)
                                    .animation(.easeInOut(duration: 0.4), value: showFinalSadu)
                            }
                            .disabled(isWeaving || isUsed || showFinalSadu)
                        }
                    }
                    .padding(.bottom, 60)
                }
                
                // 4. طبقة المفرقعات (Confetti) المحدثة بالتنسيق الجديد تماماً
                ForEach(confettiParticles) { p in
                    Rectangle()
                        .fill(p.color)
                        .frame(width: p.width, height: p.height)
                        .rotationEffect(.degrees(p.rotation))
                        .offset(x: p.x, y: p.y)
                        .opacity(p.opacity)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                screenSize = geometry.size
                spiderY = getLineY(for: 0) - 10
                
                DispatchQueue.global(qos: .background).async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        print("خطأ في تفعيل إعدادات الصوت: \(error.localizedDescription)")
                    }
                }
            }
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
            
            // 🛑 إيقاف صوت الحياكة فور انتهاء الـ 6 سطور للون الحالي
            audioPlayer?.stop()
            
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
        
        // 📳 الهابتيك الميكانيكي النقي (.rigid)
        let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 1.0)
        
        // 🔊 تشغيل صوت حياكة العنكبوت (Knitting)
        playSound(named: "Knitting")
        
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
    
    // اكتمال الحياكة والانتقال الفوري
    private func triggerCompletion() {
        spiderX = 0
        spiderY = -95
        
        showFinalSadu = true
        loomScale = 1.15
        
        spawnConfetti()
        
        // 🔊 تشغيل صوت الاحتفال (celebrate) فوراً
        playSound(named: "celebrate")
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    // إنشاء المفرقعات بالتنسيق الجديد المطابق تماماً
    private func spawnConfetti() {
        let colors: [Color] = [.pink, .yellow, .purple, .orange, .teal, .white, .red, .cyan]
        
        confettiParticles = (0..<90).map { _ in
            ConfettiParticle(
                color: colors.randomElement() ?? .pink,
                x: CGFloat.random(in: -80...80),
                y: CGFloat.random(in: 120...180),
                width: CGFloat.random(in: 8...14),
                height: CGFloat.random(in: 13...20),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
        }
        
        withAnimation(.easeOut(duration: 0.5)) {
            for i in confettiParticles.indices {
                confettiParticles[i].x += CGFloat.random(in: -170...170)
                confettiParticles[i].y -= CGFloat.random(in: 230...450)
                confettiParticles[i].rotation += Double.random(in: -180...180)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 2.2)) {
                for i in confettiParticles.indices {
                    confettiParticles[i].y += 650
                    confettiParticles[i].x += CGFloat.random(in: -70...70)
                    confettiParticles[i].rotation += Double.random(in: 360...720)
                    confettiParticles[i].opacity = 0.0
                }
            }
        }
    }
    
    // دالة مساعدة لتشغيل الصوت مع إيقاف الصوت السابق فوراً
    private func playSound(named soundName: String) {
        audioPlayer?.stop()
        
        var soundUrl = Bundle.main.url(forResource: soundName, withExtension: "wav")
        if soundUrl == nil {
            soundUrl = Bundle.main.url(forResource: soundName, withExtension: "mp3")
        }
        
        guard let url = soundUrl else {
            print("❌ ملف الصوت غير موجود في المشروع: \(soundName)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("❌ خطأ في تشغيل الصوت \(soundName): \(error.localizedDescription)")
        }
    }
}

#Preview {
    Lamya()
}

