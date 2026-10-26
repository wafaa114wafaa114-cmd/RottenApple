import SwiftUI
import SpriteKit
import UIKit

class Flower: SKSpriteNode {
    var home = CGPoint.zero
    var collected = false
}

class FlowerScene: SKScene {

    // ----- بيانات الورود من التصميم -----
    let flowerData: [(name: String, x: CGFloat, y: CGFloat)] = [
        ("Purple1", 96, 173),  ("Pink1", 184, 159),   ("Yellow1", 273, 169),
        ("Yellow1", 57, 331),  ("Pink1", 178, 341),   ("Purple1", 286, 333),
        ("Purple1", 97, 490),  ("Yellow1", 183, 480), ("Pink1", 277, 490)
    ]

    // موضع السلة: إزاحة خفيفة لليسار وتنزيل طفيف للأسفل
    let basketX: CGFloat = 60
    let basketY: CGFloat = 530
    
    // توزيع الورود داخل السلة
    let slots: [(dx: CGFloat, angle: CGFloat, scale: CGFloat)] = [
        (0, 0, 1.05), (-24, 12, 0.95), (24, -12, 0.95),
        (-46, 20, 0.85), (46, -20, 0.85), (-65, 28, 0.78),
        (65, -28, 0.78), (-12, 5, 0.90), (14, -5, 0.90)
    ]

    // عمق استقرار الساق لتستقر الزهور داخل السلة
    let stemDepth: CGFloat = 0.42

    // ----- عناصر المشهد والحالة -----
    var basket = SKSpriteNode()
    var flowers: [Flower] = []
    var dragged: Flower?
    var grabOffset = CGPoint.zero
    var collectedCount = 0

    override func didMove(to view: SKView) {
        removeAllChildren()
        flowers.removeAll()
        collectedCount = 0

        // 1. الخلفية
        let bg = SKSpriteNode(imageNamed: "bg_flower")
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bg.size = self.size
        bg.zPosition = 0
        addChild(bg)

        // 2. السلة
        basket = SKSpriteNode(imageNamed: "Basket")
        basket.setScale(1.42)
        basket.position = CGPoint(
            x: basketX + (basket.size.width / 2),
            y: size.height - (basketY + (basket.size.height / 2))
        )
        basket.zPosition = 5
        addChild(basket)

        // 3. الورود
        for item in flowerData {
            let f = Flower(imageNamed: item.name)
            f.anchorPoint = CGPoint(x: 0.5, y: 0)
            f.position = CGPoint(
                x: item.x + f.size.width / 2,
                y: size.height - (item.y + f.size.height)
            )
            f.home = f.position
            f.zPosition = 3
            addChild(f)
            flowers.append(f)
        }
    }

    // ----- لمس وسحب الورود -----
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, dragged == nil else { return }
        let p = touch.location(in: self)
        for f in flowers.reversed() where !f.collected && f.contains(p) {
            dragged = f
            grabOffset = CGPoint(x: f.position.x - p.x, y: f.position.y - p.y)
            f.removeAllActions()
            f.zPosition = 10
            f.run(.scale(to: 1.15, duration: 0.1))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let f = dragged, let touch = touches.first else { return }
        let p = touch.location(in: self)
        f.position = CGPoint(x: p.x + grabOffset.x, y: p.y + grabOffset.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let f = dragged, let touch = touches.first else { return }
        dragged = nil
        let p = touch.location(in: self)
        let dropZone = basket.frame.insetBy(dx: -45, dy: -45)
        
        if dropZone.contains(p) {
            addToBasket(f)
        } else {
            sendHome(f)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let f = dragged {
            dragged = nil
            sendHome(f)
        }
    }

    // ----- إدخال الوردة في السلة -----
    func addToBasket(_ f: Flower) {
        f.removeAllActions()
        f.collected = true
        let slot = slots[min(collectedCount, slots.count - 1)]

        let stemBase = basket.frame.maxY - (basket.frame.height * stemDepth)
        let target = CGPoint(x: basket.frame.midX + slot.dx, y: stemBase)

        f.zPosition = 4 + CGFloat(collectedCount) * 0.01
        collectedCount += 1

        let move = SKAction.move(to: target, duration: 0.3)
        let turn = SKAction.rotate(toAngle: slot.angle * .pi / 180, duration: 0.3, shortestUnitArc: true)
        let grow = SKAction.scale(to: slot.scale, duration: 0.3)
        [move, turn, grow].forEach { $0.timingMode = .easeOut }
        f.run(.group([move, turn, grow]))

        basket.run(.sequence([
            .scale(to: 1.48, duration: 0.1),
            .scale(to: 1.42, duration: 0.1)
        ]))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if collectedCount == flowers.count {
            celebrate()
        }
    }

    func sendHome(_ f: Flower) {
        f.removeAllActions()
        let back = SKAction.group([
            .move(to: f.home, duration: 0.25),
            .scale(to: 1.0, duration: 0.25)
        ])
        back.timingMode = .easeInEaseOut
        f.run(back) { f.zPosition = 3 }
    }

    // ----- احتفال الفرقعات -----
    func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        basket.run(.sequence([
            .scale(to: 1.54, duration: 0.15),
            .scale(to: 1.42, duration: 0.15)
        ]))

        spawnConfetti()
    }

    private func spawnConfetti() {
        let colors: [UIColor] = [.systemPink, .systemYellow, .systemPurple, .systemOrange, .systemTeal, .white]

        for _ in 0..<90 {
            let width = CGFloat.random(in: 8...14)
            let height = CGFloat.random(in: 13...20)
            let piece = SKSpriteNode(color: colors.randomElement() ?? .systemPink, size: CGSize(width: width, height: height))
            
            piece.position = CGPoint(
                x: basket.position.x + CGFloat.random(in: -80...80),
                y: basket.position.y + CGFloat.random(in: 20...100)
            )
            piece.zPosition = 20
            addChild(piece)

            let launchX = CGFloat.random(in: -170...170)
            let launchY = CGFloat.random(in: 230...450)
            let launch = SKAction.moveBy(x: launchX, y: launchY, duration: Double.random(in: 0.4...0.6))
            launch.timingMode = .easeOut

            let fallX = CGFloat.random(in: -70...70)
            let fall = SKAction.moveBy(x: fallX, y: -size.height, duration: Double.random(in: 1.8...2.6))
            fall.timingMode = .easeIn

            let rotate = SKAction.rotate(byAngle: CGFloat.random(in: -8...8), duration: 0.5)
            let spinForever = SKAction.repeatForever(rotate)

            let fullSequence = SKAction.sequence([
                launch,
                fall,
                .removeFromParent()
            ])

            piece.run(.group([fullSequence, spinForever]))
        }
    }
}

// ----- واجهة العرض متوافقة مع أبعاد الجهاز تلقائياً -----
struct Renad: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: createScene(size: geo.size))
                .ignoresSafeArea()
        }
    }

    private func createScene(size: CGSize) -> SKScene {
        let scene = FlowerScene(size: size)
        scene.scaleMode = .resizeFill
        return scene
    }
}

#Preview {
    Renad()
}
