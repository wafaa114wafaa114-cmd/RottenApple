//
//  Yara.swift
//  RottenApple
//
//  The whole game lives in this one file. Sections, top to bottom:
//
//    • APP SCREEN — the first view the app shows
//    • GAME STATE — which level is showing, which levels are done
//    • GAME CONTAINER — worm level first, then spider level
//    • LEVEL 1 — APPLE CLEANUP: rules (view model)
//    • LEVEL 1 — APPLE CLEANUP: screen
//    • LEVEL 2 — SPIDER SHOES: rules (view model)
//    • LEVEL 2 — SPIDER SHOES: screen
//    • HAPTICS — every vibration in the game
//    • SOUNDS — the sound effects (files in the Sounds folder)
//    • ART — image names and where each piece sits
//    • LAYOUT HELPERS — fits the art to any screen size
//    • SHARED UI — buttons, top bar
//    • CONFETTI — the burst at the end of each level
//    • LEVEL COMPLETE CARD
//
//  The pictures come from GameAssets.xcassets (in the left sidebar).
//  Haptics only vibrate on a real iPhone, not in the Simulator.
//

import SwiftUI
import UIKit
import Observation
import AVFoundation


// ========================================================================
// MARK: - APP SCREEN — the first view the app shows
// ========================================================================

struct ContentView: View {
    var body: some View {
        GameContainerView()
            .preferredColorScheme(.light)
            .statusBarHidden()
            // Let drags near the screen edges reach the game first.
            .defersSystemGestures(on: .all)
            .persistentSystemOverlays(.hidden)
    }
}

#Preview {
    ContentView()
}

// ========================================================================
// MARK: - GAME STATE — which level is showing, which levels are done
// ========================================================================

@Observable
final class GameViewModel {

    enum Screen: Equatable {
        case appleCleanup   // Level 1 (worm)
        case spiderShoes    // Level 2 (spider)
    }

    /// The game opens straight into the worm level.
    var screen: Screen = .appleCleanup

    /// Level 1: every seed and the worm have been removed from the apple.
    var isLevel1Complete = false
    /// Level 2: all 8 shoes are on the spider's feet.
    var isLevel2Complete = false

    /// Shows the "well done" card over the current level.
    var isShowingLevelComplete = false

    /// Changing this rebuilds the level, giving it a fresh board.
    private(set) var runID = UUID()

    func play(_ level: Screen) {
        isShowingLevelComplete = false
        runID = UUID()
        screen = level
    }

    func completeCurrentLevel() {
        switch screen {
        case .appleCleanup: isLevel1Complete = true
        case .spiderShoes:  isLevel2Complete = true
        }
        isShowingLevelComplete = true
    }

    func replay() { play(screen) }
    func next()   { play(.spiderShoes) }
}

// ========================================================================
// MARK: - GAME CONTAINER — worm level first, then spider level
// ========================================================================

struct GameContainerView: View {
    @State private var game = GameViewModel()

    var body: some View {
        ZStack {
            // Sky background behind both levels (GameAssets.xcassets → level_background).
            Image(Art.levelBackground)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            switch game.screen {
            case .appleCleanup:
                AppleCleanupView(onComplete: { game.completeCurrentLevel() })
                    .id(game.runID)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

            case .spiderShoes:
                SpiderShoeView(onComplete: { game.completeCurrentLevel() })
                    .id(game.runID)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if game.isShowingLevelComplete {
                completeOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: game.screen)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: game.runID)
        .animation(.easeInOut(duration: 0.25), value: game.isShowingLevelComplete)
        .onAppear {
            HapticManager.shared.prepare()
            SoundManager.shared.prepare()
        }
    }

    @ViewBuilder
    private var completeOverlay: some View {
        if game.screen == .appleCleanup {
            LevelCompleteOverlay(
                title: "Squeaky clean!",
                message: "No seeds, no worm.\nJust a happy apple.",
                showsNext: true,
                onReplay: { game.replay() },
                onNext: { game.next() }
            )
        } else {
            LevelCompleteOverlay(
                title: "Party ready!",
                message: "All eight feet are\nfashionably dressed.",
                showsNext: false,
                onReplay: { game.replay() },
                onNext: {}
            )
        }
    }
}

// ========================================================================
// MARK: - LEVEL 1 — APPLE CLEANUP: rules (view model)
// ========================================================================

@Observable
final class AppleCleanupViewModel {

    enum Kind {
        case seed, worm

        /// How much the piece grows while held ("lifted off the apple").
        var liftScale: CGFloat { self == .seed ? 1.4 : 1.0 }
    }

    struct Item: Identifiable {
        let id: String
        let kind: Kind
        let sprite: Sprite

        /// Committed displacement from the art position.
        var offset: CGSize = .zero
        /// Live finger translation during a drag.
        var translation: CGSize = .zero
        /// Translation at the last drag "texture" tick.
        var tickAnchor: CGSize = .zero
        var spin: Double = 0

        var isDragging = false
        var isOutside = false
        var isCleared = false
        var isFlying = false
        /// Worm only: sliding back into its hole after being let go on the apple.
        var isReturning = false

        var center: CGPoint { sprite.rect.center + offset + translation }

        /// The point that has to leave the apple. For the worm that's its head
        /// (the part you hold), not the middle of its long body.
        var exitPoint: CGPoint {
            kind == .worm ? Art.Apple.wormHead.rect.center + offset + translation : center
        }

        /// Seeds leave at the apple's edge. The worm's head already sits near
        /// the edge, so it has to be pulled a little past it.
        var exitMargin: CGFloat { kind == .worm ? 1.12 : 1.0 }

        var isOffApple: Bool { !Art.Apple.contains(exitPoint, grow: exitMargin) }
    }

    private(set) var items: [Item]
    private(set) var isComplete = false

    @ObservationIgnored var onComplete: (() -> Void)?
    @ObservationIgnored private let haptics = HapticManager.shared
    @ObservationIgnored private let sounds = SoundManager.shared

    // Tuning
    /// Screen points between the soft ticks felt while dragging.
    private let dragTickSpacing: CGFloat = 26
    /// Canvas pixels a cleared piece travels (well past the screen edge).
    private let flyDistance: CGFloat = 3200

    init() {
        let seeds = Art.Apple.seeds.map { Item(id: $0.name, kind: .seed, sprite: $0) }
        items = seeds + [Item(id: "worm", kind: .worm, sprite: Art.Apple.wormBody)]
    }

    // MARK: Drag lifecycle

    /// Called on every DragGesture change. The first call is the pick-up.
    func drag(_ id: String, translation: CGSize, pointsPerUnit: CGFloat) {
        guard let i = index(of: id), !items[i].isCleared else { return }

        if !items[i].isDragging {
            items[i].isDragging = true
            items[i].tickAnchor = translation
            haptics.pickUp()
            if items[i].kind == .seed { sounds.play(.seedPickup, volume: 0.6) }
        }

        items[i].translation = translation

        // .medium "texture" ticks as the piece slides along.
        if (translation - items[i].tickAnchor).length * pointsPerUnit >= dragTickSpacing {
            items[i].tickAnchor = translation
            haptics.dragTick()
        }

        // Tell the finger the moment it crosses the apple's edge.
        let outside = items[i].isOffApple
        if outside != items[i].isOutside {
            items[i].isOutside = outside
            outside ? haptics.crossedOutOfApple() : haptics.crossedBackOntoApple()
        }
    }

    func endDrag(_ id: String, translation: CGSize, predictedEndTranslation: CGSize) {
        guard let i = index(of: id), items[i].isDragging else { return }

        // Commit the drag (visually a no-op: offset + translation is unchanged).
        items[i].offset = items[i].offset + translation
        items[i].translation = .zero
        items[i].isDragging = false

        // A quick flick toward the edge counts too: check where the throw would land.
        let flick = predictedEndTranslation - translation
        let throwLimit: CGFloat = 500   // canvas pixels
        let thrown = flick.length > throwLimit ? flick.normalized * throwLimit : flick
        let landsOffApple = !Art.Apple.contains(items[i].exitPoint + thrown, grow: items[i].exitMargin)

        if items[i].isOffApple || landsOffApple {
            flyAway(i, flick: flick)
        } else if items[i].kind == .worm {
            sendWormHome(i)
        } else {
            haptics.putDown()
        }
    }

    // MARK: Outcomes

    private func flyAway(_ i: Int, flick: CGSize) {
        items[i].isCleared = true
        items[i].isOutside = false
        // Sound + matching vibration as it flies off the apple.
        switch items[i].kind {
        case .seed:
            sounds.play(.seedRemoved)
            haptics.seedRemoved()
        case .worm:
            sounds.play(.wormRemoved)
            haptics.wormRemoved()
        }

        // Follow the flick; if the finger just let go, fly straight away from the apple.
        let direction = flick.length > 60 ? flick : items[i].center - Art.Apple.bounds.center
        let unit = direction.normalized
        let target = items[i].offset + unit * flyDistance

        withAnimation(.easeIn(duration: 0.5)) {
            items[i].offset = target
            items[i].spin = unit.width >= 0 ? 420 : -420
            items[i].isFlying = true
        } completion: { [weak self] in
            self?.checkCompletion()
        }
    }

    private func sendWormHome(_ i: Int) {
        haptics.wormRetreat()
        items[i].isReturning = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            items[i].offset = .zero
            items[i].isOutside = false
        } completion: { [weak self] in
            // Back in the hole: hide the body again, leaving just the head peeking out.
            guard let self, let w = self.index(of: "worm"), !self.items[w].isDragging else { return }
            self.items[w].isReturning = false
        }
    }

    private func checkCompletion() {
        guard !isComplete, items.allSatisfy(\.isCleared) else { return }
        isComplete = true
        haptics.levelComplete()
        sounds.play(.celebration)
        Task { @MainActor [weak self] in
            // Let the confetti fall before the "well done" card appears.
            try? await Task.sleep(for: .milliseconds(2400))
            self?.onComplete?()
        }
    }

    private func index(of id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }
}

// ========================================================================
// MARK: - LEVEL 1 — APPLE CLEANUP: screen
// ========================================================================

struct AppleCleanupView: View {
    let onComplete: () -> Void

    @State private var vm = AppleCleanupViewModel()

    private static let board = "appleBoard"

    var body: some View {
        VStack(spacing: 0) {
            LevelHUD(
                title: "Clean the Apple",
                hint: "Drag the seeds and the worm off the apple"
            )

            GeometryReader { geo in
                let space = CanvasSpace(focus: Art.Apple.focus, in: geo.size, padding: 20)
                board(space)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Confetti bursts with the celebration sound when the apple is clean.
        .overlay { ConfettiBurst(isActive: vm.isComplete) }
        .onAppear {
            vm.onComplete = onComplete
            HapticManager.shared.prepare()
        }
    }

    // MARK: Board

    private func board(_ space: CanvasSpace) -> some View {
        ZStack {
            // The apple itself (never moves). Bounces when the level is cleared.
            ZStack {
                ArtImage(Art.Apple.skin, in: space)
                ArtImage(Art.Apple.flesh, in: space)
                ArtImage(Art.Apple.stem, in: space)
                ArtImage(Art.Apple.wormHole, in: space)
            }
            .keyframeAnimator(initialValue: CGFloat(1), trigger: vm.isComplete) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.08, duration: 0.18)
                    SpringKeyframe(0.97, duration: 0.16)
                    SpringKeyframe(1.0, duration: 0.35)
                }
            }

            ForEach(vm.items) { item in
                itemView(item, space)
            }
        }
        .coordinateSpace(.named(Self.board))
    }

    // MARK: Draggable pieces

    private func itemView(_ item: AppleCleanupViewModel.Item, _ space: CanvasSpace) -> some View {
        let size = space.size(item.sprite.rect.size)
        // Seeds are tiny on a phone — give fingers at least a 50pt target.
        let hit = CGSize(width: max(size.width, 50), height: max(size.height, 50))

        return Group {
            if item.kind == .worm {
                WormView(showsBody: item.isDragging || item.isOutside || item.isCleared || item.isReturning,
                         space: space)
            } else {
                Image(item.sprite.name)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(width: hit.width, height: hit.height)
        .contentShape(PieceHitShape(isWorm: item.kind == .worm))
        .shadow(color: .black.opacity(item.isDragging && item.kind == .worm ? 0.2 : 0), radius: 6, y: 4)
        // Lift: grow + drop shadow while held. This implicit animation only
        // covers the modifiers above it, so the fly-away animation stays separate.
        .scaleEffect(item.isDragging && item.kind == .seed ? item.kind.liftScale * (item.isOutside ? 1.08 : 1) : 1)
        .shadow(color: .black.opacity(item.isDragging && item.kind == .seed ? 0.25 : 0),
                radius: item.isDragging ? 8 : 0, y: item.isDragging ? 6 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: item.isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: item.isOutside)
        .gesture(dragGesture(for: item.id, space: space))
        .rotationEffect(.degrees(item.spin))
        .opacity(item.isFlying ? 0 : 1)
        .allowsHitTesting(!item.isCleared)
        .position(space.point(item.center))
        .zIndex(item.isDragging ? 100 : (item.kind == .worm ? 1 : 2))
        .accessibilityLabel(item.kind == .worm ? "Worm" : "Seed")
    }

    private func dragGesture(for id: String, space: CanvasSpace) -> some Gesture {
        // minimumDistance 0 → the pick-up haptic fires the instant a finger lands.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.board))
            .onChanged { value in
                vm.drag(id,
                        translation: space.canvasDelta(value.translation),
                        pointsPerUnit: space.scale)
            }
            .onEnded { value in
                vm.endDrag(id,
                           translation: space.canvasDelta(value.translation),
                           predictedEndTranslation: space.canvasDelta(value.predictedEndTranslation))
            }
    }
}

// MARK: - Worm

/// At rest only the worm's head peeks out of the hole. As soon as you grab
/// it, the whole worm comes out with your finger.
private struct WormView: View {
    let showsBody: Bool
    let space: CanvasSpace

    var body: some View {
        let base = Art.Apple.wormBody
        ZStack(alignment: .topLeading) {
            if showsBody {
                layer(base, relativeTo: base)
            }
            layer(Art.Apple.wormHead, relativeTo: base)
        }
        .frame(width: space.size(base.rect.size).width,
               height: space.size(base.rect.size).height,
               alignment: .topLeading)
    }

    private func layer(_ sprite: Sprite, relativeTo base: Sprite) -> some View {
        let size = space.size(sprite.rect.size)
        return Image(sprite.name)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .offset(x: (sprite.rect.minX - base.rect.minX) * space.scale,
                    y: (sprite.rect.minY - base.rect.minY) * space.scale)
    }
}

/// Touch area: a padded rectangle for seeds; for the worm, just its head
/// (the only part you can see while it's in the hole).
nonisolated private struct PieceHitShape: Shape {
    let isWorm: Bool

    func path(in rect: CGRect) -> Path {
        guard isWorm else { return Path(rect) }
        // worm_head sits in the right-hand 35% / top 70% of the worm_body image.
        let head = CGRect(x: rect.minX + rect.width * 0.64,
                          y: rect.minY,
                          width: rect.width * 0.36,
                          height: rect.height * 0.72)
        return Path(roundedRect: head.insetBy(dx: -10, dy: -10), cornerRadius: 24)
    }
}

// ========================================================================
// MARK: - LEVEL 2 — SPIDER SHOES: rules (view model)
// ========================================================================

@Observable
final class SpiderShoeViewModel {

    struct Foot: Identifiable {
        let id: Int
        /// The tip of the leg — where the leg goes into a shoe.
        let tip: CGPoint
        /// Which way the leg points at its tip (degrees, 90 = straight down).
        let angle: Double
        let isLeft: Bool
    }

    struct Shoe: Identifiable {
        let id: Int
        let sprite: Sprite
        /// The leg this shoe was drawn on in the art.
        let drawnAngle: Double
        let drawnOnLeft: Bool
        /// From the shoe's centre to its opening (where the leg goes in), as drawn.
        let openingOffset: CGSize
        let home: CGPoint
        let homeRotation: Double

        var position: CGPoint          // centre of the shoe, canvas pixels
        var rotation: Double
        /// Mirrored left↔right, so it points outward on the other side of the spider.
        var isFlipped = false
        var dragStart: CGPoint = .zero

        var isDragging = false
        /// The free foot close enough to snap to right now.
        var targetFoot: Int?
        /// The foot this shoe is on, once fitted.
        var fittedFoot: Int?

        var isFitted: Bool { fittedFoot != nil }

        /// Should this shoe be mirrored to sit on `foot`?
        func flips(for foot: Foot) -> Bool { foot.isLeft != drawnOnLeft }

        /// The opening's offset from the centre, mirrored if needed.
        func opening(flipped: Bool) -> CGSize {
            flipped ? CGSize(width: -openingOffset.width, height: openingOffset.height) : openingOffset
        }
    }

    let feet: [Foot]
    private(set) var shoes: [Shoe]
    private(set) var isComplete = false
    /// Bumped once when the level is finished — drives the spider's happy dance.
    private(set) var danceTrigger = 0

    @ObservationIgnored var onComplete: (() -> Void)?
    @ObservationIgnored private let haptics = HapticManager.shared
    @ObservationIgnored private let sounds = SoundManager.shared
    @ObservationIgnored private var pointsPerUnit: CGFloat = 0.3

    // Tuning
    /// Release a shoe within this many screen points of any free leg tip to
    /// snap. The hover tick uses the same distance, so the tick means "let go now".
    private let snapRadius: CGFloat = 44

    init() {
        feet = Art.Spider.legTips.enumerated().map { index, tip in
            Foot(id: index, tip: tip, angle: Art.Spider.legAngles[index],
                 isLeft: tip.x < Art.Spider.middleX)
        }

        let slots = Art.Spider.scatterSlots.shuffled()
        shoes = Art.Spider.shoes.enumerated().map { index, sprite in
            let leg = Art.Spider.shoeDrawnOnLeg[index]
            let tip = Art.Spider.legTips[leg]
            let tilt = Double.random(in: -24...24)
            return Shoe(id: index, sprite: sprite,
                        drawnAngle: Art.Spider.legAngles[leg],
                        drawnOnLeft: tip.x < Art.Spider.middleX,
                        openingOffset: tip - sprite.rect.center,
                        home: slots[index], homeRotation: tilt,
                        position: slots[index], rotation: tilt)
        }
    }

    // MARK: Drag lifecycle

    func drag(_ id: Int, translation: CGSize, pointsPerUnit: CGFloat) {
        guard let i = index(of: id), !shoes[i].isFitted else { return }
        self.pointsPerUnit = pointsPerUnit

        if !shoes[i].isDragging {
            shoes[i].dragStart = shoes[i].position
            haptics.pickUp()
            // Straighten up and lift as it's picked up.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                shoes[i].isDragging = true
                shoes[i].rotation = 0
            }
        }

        shoes[i].position = shoes[i].dragStart + translation

        let target = nearestFreeFoot(for: shoes[i])
        if target != shoes[i].targetFoot {
            shoes[i].targetFoot = target
            if target != nil { haptics.hoverNearFoot() }
        }
    }

    func endDrag(_ id: Int) {
        guard let i = index(of: id), shoes[i].isDragging else { return }

        if let footID = shoes[i].targetFoot, let foot = feet.first(where: { $0.id == footID }) {
            // Snap onto this foot. Mirror the shoe if it was drawn for the other
            // side, then turn it to follow this leg (around its opening).
            let flip = shoes[i].flips(for: foot)
            let drawnAngle = flip ? 180 - shoes[i].drawnAngle : shoes[i].drawnAngle
            let limit = Art.Spider.maxShoeTurn
            let turn = min(max(foot.angle - drawnAngle, -limit), limit)

            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                shoes[i].isFlipped = flip
                shoes[i].position = foot.tip - shoes[i].opening(flipped: flip)
                shoes[i].rotation = turn
                shoes[i].fittedFoot = footID
                shoes[i].isDragging = false
                shoes[i].targetFoot = nil
            }
            haptics.snapped()
            sounds.play(.shoeOn)
            checkCompletion()
            return
        }

        haptics.putDown()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            shoes[i].position = shoes[i].home
            shoes[i].rotation = shoes[i].homeRotation
            shoes[i].isDragging = false
            shoes[i].targetFoot = nil
        }
    }

    // MARK: Helpers

    /// The closest leg tip without a shoe that this shoe's opening is near.
    private func nearestFreeFoot(for shoe: Shoe) -> Int? {
        feet
            .filter { foot in !shoes.contains { $0.fittedFoot == foot.id } }
            .map { foot -> (id: Int, distance: CGFloat) in
                let opening = shoe.position + shoe.opening(flipped: shoe.flips(for: foot))
                return (foot.id, opening.distance(to: foot.tip) * pointsPerUnit)
            }
            .filter { $0.distance <= snapRadius }
            .min { $0.distance < $1.distance }?.id
    }

    private func checkCompletion() {
        guard !isComplete, shoes.allSatisfy(\.isFitted) else { return }
        isComplete = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            self.danceTrigger += 1
            self.haptics.levelComplete()
            self.sounds.play(.celebration)
            // Let the confetti fall before the "well done" card appears.
            try? await Task.sleep(for: .milliseconds(2400))
            self.onComplete?()
        }
    }

    private func index(of id: Int) -> Int? {
        shoes.firstIndex { $0.id == id }
    }
}

// ========================================================================
// MARK: - LEVEL 2 — SPIDER SHOES: screen
// ========================================================================

struct SpiderShoeView: View {
    let onComplete: () -> Void

    @State private var vm = SpiderShoeViewModel()

    private static let board = "spiderBoard"

    var body: some View {
        VStack(spacing: 0) {
            LevelHUD(
                title: "Shoes for Spider",
                hint: "Put a shoe on every foot"
            )

            GeometryReader { geo in
                let space = CanvasSpace(focus: Art.Spider.focus, in: geo.size, padding: 12)
                board(space, size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Confetti bursts with the celebration sound when the spider dances.
        .overlay { ConfettiBurst(isActive: vm.danceTrigger > 0) }
        .onAppear {
            vm.onComplete = onComplete
            HapticManager.shared.prepare()
        }
    }

    // MARK: Board

    private func board(_ space: CanvasSpace, size: CGSize) -> some View {
        // The spider dances around its own middle. Worked out here, outside the
        // animation, so the animation doesn't have to read the art data itself.
        let danceAnchor = space.unitPoint(Art.Spider.body.rect.center, in: size)

        return ZStack {
            ArtImage(Art.Spider.body, in: space)
                .zIndex(0)

            ForEach(vm.shoes) { shoe in
                shoeView(shoe, space)
            }
        }
        .coordinateSpace(.named(Self.board))
        // Happy dance once every shoe is on.
        .keyframeAnimator(initialValue: DanceFrame(), trigger: vm.danceTrigger) { content, frame in
            content
                .rotationEffect(.degrees(frame.angle),
                                anchor: danceAnchor)
                .offset(y: frame.lift)
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                CubicKeyframe(-6, duration: 0.15)
                CubicKeyframe(6, duration: 0.2)
                CubicKeyframe(-5, duration: 0.2)
                CubicKeyframe(5, duration: 0.2)
                SpringKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.lift) {
                SpringKeyframe(-18, duration: 0.18)
                SpringKeyframe(0, duration: 0.2)
                SpringKeyframe(-14, duration: 0.18)
                SpringKeyframe(0, duration: 0.2)
                SpringKeyframe(-10, duration: 0.18)
                SpringKeyframe(0, duration: 0.3)
            }
        }
    }

    // MARK: Shoes

    private func shoeView(_ shoe: SpiderShoeViewModel.Shoe, _ space: CanvasSpace) -> some View {
        let size = space.size(shoe.sprite.rect.size)
        let frame = CGSize(width: max(size.width, 54), height: max(size.height, 54))
        let isNear = shoe.targetFoot != nil
        // Turn around the shoe's opening, so a fitted shoe stays on its leg tip.
        let opening = shoe.opening(flipped: shoe.isFlipped)
        let pivot = UnitPoint(x: 0.5 + opening.width * space.scale / frame.width,
                              y: 0.5 + opening.height * space.scale / frame.height)

        return Image(shoe.sprite.name)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            // Mirror shoes that sit on the other side from where they were drawn.
            .scaleEffect(x: shoe.isFlipped ? -1 : 1, y: 1)
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            // Squash-and-stretch "boing" when it lands on the foot.
            .keyframeAnimator(initialValue: CGFloat(1), trigger: shoe.isFitted) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.0, duration: 0.12)
                    SpringKeyframe(1.25, duration: 0.12)
                    SpringKeyframe(0.94, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.25)
                }
            }
            // Held shoes lift up; near a foot they settle down a little, ready to slip on.
            .scaleEffect(shoe.isDragging ? (isNear ? 1.03 : 1.18) : 1)
            .shadow(color: .black.opacity(shoe.isDragging ? (isNear ? 0.12 : 0.25) : 0),
                    radius: shoe.isDragging ? 8 : 0, y: shoe.isDragging ? 6 : 0)
            .rotationEffect(.degrees(shoe.rotation), anchor: pivot)
            .gesture(dragGesture(for: shoe.id, space: space))
            .allowsHitTesting(!shoe.isFitted && !vm.isComplete)
            .position(space.point(shoe.position))
            .zIndex(shoe.isDragging ? 100 : (shoe.isFitted ? 5 : 10))
            .accessibilityLabel("Shoe \(shoe.id + 1)")
    }

    private func dragGesture(for id: Int, space: CanvasSpace) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.board))
            .onChanged { value in
                vm.drag(id,
                        translation: space.canvasDelta(value.translation),
                        pointsPerUnit: space.scale)
            }
            .onEnded { _ in
                vm.endDrag(id)
            }
    }
}

nonisolated private struct DanceFrame {
    var angle: Double = 0
    var lift: CGFloat = 0
}

// ========================================================================
// MARK: - HAPTICS — every vibration in the game
// ========================================================================

@MainActor
final class HapticManager {

    static let shared = HapticManager()

    /// Flip off to silence every haptic (e.g. from a settings toggle).
    var isEnabled = true

    private let light  = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let soft   = UIImpactFeedbackGenerator(style: .soft)
    private let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    // MARK: - Low-level building blocks

    /// Wakes the Taptic Engine so the first hit has no latency.
    /// Call when a level appears.
    func prepare() {
        [light, medium, heavy, soft, rigid].forEach { $0.prepare() }
        notification.prepare()
    }

    /// A single impact. `intensity` is 0...1.
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard isEnabled else { return }
        let generator = generator(for: style)
        generator.impactOccurred(intensity: min(max(intensity, 0), 1))
        generator.prepare() // keep it warm for the next hit
    }

    /// System success / warning / error patterns.
    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }

    /// One step of a custom pattern: wait `delay`, then fire the impact.
    struct Step {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        let intensity: CGFloat
        let delay: Duration
        init(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat = 1, after delay: Duration = .zero) {
            self.style = style
            self.intensity = intensity
            self.delay = delay
        }
    }

    /// Plays a short sequence of impacts — our "custom patterns".
    func play(_ steps: [Step]) {
        guard isEnabled else { return }
        Task { @MainActor in
            for step in steps {
                if step.delay > .zero { try? await Task.sleep(for: step.delay) }
                impact(step.style, intensity: step.intensity)
            }
        }
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light:  light
        case .medium: medium
        case .heavy:  heavy
        case .soft:   soft
        case .rigid:  rigid
        @unknown default: medium
        }
    }
}

// MARK: - Semantic game haptics

extension HapticManager {

    // Shared

    /// Finger lands on a draggable piece.
    func pickUp()   { impact(.light, intensity: 0.9) }

    /// Piece released somewhere that does nothing.
    func putDown()  { impact(.soft, intensity: 0.6) }

    /// Squishy buttons.
    func buttonDown() { impact(.light, intensity: 0.6) }

    /// Whole level finished.
    func levelComplete() {
        notify(.success)
        play([Step(.heavy, 0.8, after: .milliseconds(260)),
              Step(.light, 0.6, after: .milliseconds(90))])
    }

    // Level 1 — Apple Cleanup

    /// Light "texture" ticks while a piece slides across the apple.
    func dragTick() { impact(.medium, intensity: 0.35) }

    /// The dragged piece just left the apple: releasing now will clear it.
    func crossedOutOfApple() { impact(.rigid, intensity: 0.8) }

    /// The dragged piece came back over the apple.
    func crossedBackOntoApple() { impact(.soft, intensity: 0.5) }

    /// A seed flies off. Matches the two quick pops in "removing seed1.wav".
    func seedRemoved() {
        play([Step(.heavy, 1.0),
              Step(.rigid, 0.9, after: .milliseconds(40))])
    }

    /// The worm flies off. Matches the three wiggly bumps in "removing worm.wav".
    func wormRemoved() {
        play([Step(.medium, 0.8, after: .milliseconds(20)),
              Step(.heavy, 1.0, after: .milliseconds(20)),
              Step(.medium, 0.9, after: .milliseconds(80)),
              Step(.medium, 0.8, after: .milliseconds(60))])
    }

    /// The worm wriggles back into its hole.
    func wormRetreat() {
        play([Step(.soft, 0.7),
              Step(.soft, 0.5, after: .milliseconds(70)),
              Step(.soft, 0.3, after: .milliseconds(70))])
    }

    // Level 2 — Spider Shoe-Fitting

    /// Subtle tick: the shoe is close enough to its foot to snap on release.
    func hoverNearFoot() { impact(.light, intensity: 0.75) }

    /// The shoe goes on. Matches the thump in "shoes on.wav", plus a tiny spring "settle".
    func snapped() {
        play([Step(.heavy, 1.0, after: .milliseconds(20)),
              Step(.soft, 0.4, after: .milliseconds(160))])
    }

    /// Released near a foot that isn't this shoe's.
    func wrongFoot() {
        play([Step(.rigid, 0.55),
              Step(.rigid, 0.55, after: .milliseconds(90))])
    }
}

// ========================================================================
// MARK: - SOUNDS — the sound effects (files in the Sounds folder)
// ========================================================================

/// Plays the game's sound effects. The files live in the "Sounds" folder of
/// the project; Xcode copies them into the app automatically.
///
/// Sounds follow the phone's silent switch and mix with music that is
/// already playing, which is what players expect from a small game.
@MainActor
final class SoundManager {

    static let shared = SoundManager()

    /// Flip off to silence every sound (e.g. from a settings toggle).
    var isEnabled = true

    enum Sound: String, CaseIterable {
        case seedPickup  = "seed_pickup"    // tiny click when you grab a seed
        case seedRemoved = "seed_removed"   // a seed flies off the apple
        case wormRemoved = "worm_removed"   // the worm flies off the apple
        case shoeOn      = "shoe_on"        // a shoe snaps onto a foot
        case celebration = "celebration"    // a level is finished

        var fileExtension: String { self == .celebration ? "mp3" : "wav" }
    }

    /// Each file is read once and kept in memory so it plays instantly.
    private var soundData: [Sound: Data] = [:]
    /// Players that are still sounding (so quick repeats can overlap).
    private var activePlayers: [AVAudioPlayer] = []

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for sound in Sound.allCases {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: sound.fileExtension),
               let data = try? Data(contentsOf: url) {
                soundData[sound] = data
            } else {
                print("⚠️ Missing sound file: \(sound.rawValue).\(sound.fileExtension)")
            }
        }
    }

    /// Loads the sounds ahead of time. Call when the game appears.
    func prepare() {}

    func play(_ sound: Sound, volume: Float = 1) {
        guard isEnabled, let data = soundData[sound],
              let player = try? AVAudioPlayer(data: data) else { return }
        activePlayers.removeAll { !$0.isPlaying }
        player.volume = volume
        player.prepareToPlay()
        player.play()
        activePlayers.append(player)
    }
}

// ========================================================================
// MARK: - ART — image names and where each piece sits
// ========================================================================

enum Art {

    // MARK: Level 1 — Apple Cleanup (canvas 2732 × 2048)

    enum Apple {
        static let canvas = CGSize(width: 2732, height: 2048)

        /// The part of the canvas we fit on screen (apple + worm, with breathing room).
        static let focus = CGRect(x: 560, y: 120, width: 1930, height: 1880)

        static let skin  = Sprite("apple_skin",  612, 228, 1634, 1725)
        static let flesh = Sprite("apple_flesh", 696, 322, 1449, 1555)
        static let stem  = Sprite("apple_stem", 1122, 165,  564,  388)

        static let wormBody = Sprite("worm_body", 1135, 664, 1296, 612)  // includes the head
        static let wormHead = Sprite("worm_head", 1980, 664,  451, 429)  // drawn over the hole
        static let wormHole = Sprite("worm_hole", 1981, 829,  122, 280)


        static let seeds: [Sprite] = [
            Sprite("seed_1", 1478,  862,  80, 106),
            Sprite("seed_2", 1249,  920, 128,  59),
            Sprite("seed_3", 1494, 1081,  93,  66),
            Sprite("seed_4", 1399, 1184,  58, 112),
            Sprite("seed_5", 1279, 1086,  78,  88),
            Sprite("seed_6", 1411,  696,  51, 138),
        ]

        /// The apple's bounding box. A piece whose centre leaves this region is cleared.
        static let bounds = skin.rect

        /// `true` = strict rectangular bounding box.
        /// `false` = a rounded "squircle" inscribed in that box, which follows the
        /// apple's outline so the box's empty corners don't count as "on the apple".
        static let usesStrictBoundingBox = false

        /// `grow` makes the shape a bit bigger (1.1 = 10% bigger).
        static func contains(_ p: CGPoint, grow: CGFloat = 1) -> Bool {
            if usesStrictBoundingBox {
                return bounds.insetBy(dx: -bounds.width * (grow - 1) / 2,
                                      dy: -bounds.height * (grow - 1) / 2).contains(p)
            }
            let dx = abs(p.x - bounds.midX) / (bounds.width / 2 * grow)
            let dy = abs(p.y - bounds.midY) / (bounds.height / 2 * grow)
            return dx * dx * dx + dy * dy * dy <= 1   // superellipse, n = 3
        }
    }

    // MARK: Level 2 — Spider Shoe-Fitting (canvas 1206 × 2622)

    enum Spider {
        static let canvas = CGSize(width: 1206, height: 2622)

        /// Centred on the spider, with room above and below for loose shoes.
        static let focus = CGRect(x: -18, y: 120, width: 1206, height: 1890)

        static let body = Sprite("spider_body", 122, 740, 915, 577)

        /// The tip of each of the 8 legs: 4 left legs, then 4 right legs.
        static let legTips: [CGPoint] = [
            CGPoint(x:  122, y: 1122), CGPoint(x:  222, y: 1262),
            CGPoint(x:  324, y: 1313), CGPoint(x:  506, y: 1314),
            CGPoint(x:  678, y: 1305), CGPoint(x:  841, y: 1273),
            CGPoint(x:  937, y: 1223), CGPoint(x: 1033, y: 1119),
        ]

        /// The spider's middle. Legs left of this are left legs.
        static let middleX: CGFloat = 579

        /// Which way each leg points at its tip, in degrees
        /// (0 = right, 90 = straight down). Same order as `legTips`.
        static let legAngles: [Double] = [132, 114, 111, 78, 89, 68.5, 59, 55]

        /// A shoe turns to follow the leg it's put on, but never by more than
        /// this, so it doesn't end up kicking upward.
        static let maxShoeTurn: Double = 40

        /// Each shoe as drawn in the art. Any shoe fits any leg.
        static let shoes: [Sprite] = [
            Sprite("shoe_1", 944, 1008, 191, 215),
            Sprite("shoe_2", 845, 1084, 179, 194),
            Sprite("shoe_3",  35, 1045, 169, 148),
            Sprite("shoe_4", 233, 1244, 137, 111),
            Sprite("shoe_5", 122, 1081, 206, 230),
            Sprite("shoe_6", 791, 1195, 123, 124),
            Sprite("shoe_7", 637, 1193, 122, 171),
            Sprite("shoe_8", 414, 1227, 121, 163),
        ]

        /// The leg each shoe was drawn on (same order as `shoes`; index into `legTips`).
        /// Used to find the shoe's opening, its angle and which way it points.
        static let shoeDrawnOnLeg: [Int] = [7, 6, 0, 2, 1, 5, 4, 3]

        /// Where loose shoes wait around the outer edges (canvas centres).
        /// Shoes are shuffled across these slots every round.
        static let scatterSlots: [CGPoint] = [
            // above the spider
            CGPoint(x:  150, y:  320), CGPoint(x:  440, y:  420),
            CGPoint(x:  740, y:  420), CGPoint(x: 1030, y:  320),
            // below the spider
            CGPoint(x:  150, y: 1810), CGPoint(x:  440, y: 1710),
            CGPoint(x:  740, y: 1710), CGPoint(x: 1030, y: 1810),
        ]
    }

    // MARK: UI

    static let redoButton = "button_redo"
    static let levelBackground = "level_background"
}

/// Brand colours sampled from the art.
enum Theme {
    static let cream   = Color(red: 1.00, green: 0.965, blue: 0.90)
    static let appleRed = Color(red: 1.00, green: 0.40, blue: 0.40)
    static let flesh   = Color(red: 0.90, green: 0.88, blue: 0.62)
    static let ink     = Color(red: 0.24, green: 0.17, blue: 0.17)
}

// ========================================================================
// MARK: - LAYOUT HELPERS — fits the art to any screen size
// ========================================================================

nonisolated struct Sprite: Equatable, Sendable {
    let name: String
    let rect: CGRect

    init(_ name: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        self.name = name
        self.rect = CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Maps canvas pixels ⇄ screen points for a given container size.
nonisolated struct CanvasSpace: Sendable {
    /// Screen points per canvas pixel.
    let scale: CGFloat
    /// Screen position of canvas (0, 0).
    let origin: CGPoint

    /// Fits `focus` (a region of the canvas) inside `size`, centred.
    init(focus: CGRect, in size: CGSize, padding: CGFloat = 16) {
        let available = CGSize(width: max(size.width - padding * 2, 1),
                               height: max(size.height - padding * 2, 1))
        scale = min(available.width / focus.width, available.height / focus.height)
        origin = CGPoint(x: size.width / 2 - focus.midX * scale,
                         y: size.height / 2 - focus.midY * scale)
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }

    func size(_ s: CGSize) -> CGSize {
        CGSize(width: s.width * scale, height: s.height * scale)
    }

    /// Screen-point drag translation → canvas pixels.
    func canvasDelta(_ t: CGSize) -> CGSize {
        CGSize(width: t.width / scale, height: t.height / scale)
    }

    /// Where `point` sits as a UnitPoint of a container of `size` (for anchors).
    func unitPoint(_ p: CGPoint, in size: CGSize) -> UnitPoint {
        let s = point(p)
        return UnitPoint(x: s.x / max(size.width, 1), y: s.y / max(size.height, 1))
    }
}

/// Draws a static sprite at its canvas position.
struct ArtImage: View {
    let sprite: Sprite
    let space: CanvasSpace

    init(_ sprite: Sprite, in space: CanvasSpace) {
        self.sprite = sprite
        self.space = space
    }

    var body: some View {
        let size = space.size(sprite.rect.size)
        Image(sprite.name)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .position(space.point(sprite.rect.center))
            .accessibilityHidden(true)
    }
}

// MARK: - Geometry helpers

nonisolated extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

nonisolated extension CGSize {
    static func + (l: CGSize, r: CGSize) -> CGSize { CGSize(width: l.width + r.width, height: l.height + r.height) }
    static func - (l: CGSize, r: CGSize) -> CGSize { CGSize(width: l.width - r.width, height: l.height - r.height) }
    static func * (l: CGSize, r: CGFloat) -> CGSize { CGSize(width: l.width * r, height: l.height * r) }

    var length: CGFloat { (width * width + height * height).squareRoot() }

    var normalized: CGSize {
        let len = length
        return len > 0 ? CGSize(width: width / len, height: height / len) : CGSize(width: 1, height: 0)
    }
}

nonisolated extension CGPoint {
    static func + (l: CGPoint, r: CGSize) -> CGPoint { CGPoint(x: l.x + r.width, y: l.y + r.height) }
    static func - (l: CGPoint, r: CGPoint) -> CGSize { CGSize(width: l.x - r.x, height: l.y - r.y) }
    static func - (l: CGPoint, r: CGSize) -> CGPoint { CGPoint(x: l.x - r.width, y: l.y - r.height) }

    func distance(to other: CGPoint) -> CGFloat { (self - other).length }
}

// ========================================================================
// MARK: - SHARED UI — buttons, top bar
// ========================================================================

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { HapticManager.shared.buttonDown() }
            }
    }
}

/// An image asset used as a button (home, redo).
struct ArtButton: View {
    let asset: String
    let width: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: width)
        }
        .buttonStyle(SquishyButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Top bar shown inside each level.
struct LevelHUD: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(hint)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.6))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// ========================================================================
// MARK: - CONFETTI — the burst at the end of each level
// ========================================================================

/// One paper piece of confetti (same style as Renad's flower game).
struct YaraConfetti {
    let color: Color
    let size: CGSize
    /// Where it starts, relative to the burst point.
    let start: CGSize
    /// How far it shoots up and sideways first.
    let launch: CGSize
    let launchDuration: Double
    /// How far it drifts sideways while falling.
    let fallDrift: CGFloat
    let fallDuration: Double
    /// Spin speed in radians per second.
    let spin: Double
}

/// Shows a burst of confetti the moment `isActive` turns true: paper pieces
/// shoot up, then spin as they fall down the whole screen.
/// Put it over a level with `.overlay { ConfettiBurst(isActive: ...) }`.
struct ConfettiBurst: View {
    let isActive: Bool
    /// Where the burst comes from, as a fraction of the level's size.
    var origin = UnitPoint(x: 0.5, y: 0.55)

    @State private var pieces: [YaraConfetti] = []
    @State private var startDate: Date?

    /// How long the whole burst lasts (longest launch + longest fall).
    private static let totalDuration = 3.3

    var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { timeline in
            Canvas { context, size in
                guard let startDate else { return }
                let t = timeline.date.timeIntervalSince(startDate)
                let base = CGPoint(x: origin.x * size.width, y: origin.y * size.height)

                for piece in pieces {
                    guard let spot = position(of: piece, at: t, from: base, screenHeight: size.height)
                    else { continue }
                    var pen = context
                    pen.translateBy(x: spot.x, y: spot.y)
                    pen.rotate(by: .radians(piece.spin * t))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    pen.fill(Path(rect), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active { triggerConfettiAnimation() }
        }
    }

    private func triggerConfettiAnimation() {
        let colors: [Color] = [.pink, .yellow, .purple, .orange, .teal, .white]

        pieces = (0..<90).map { _ in
            YaraConfetti(
                color: colors.randomElement() ?? .pink,
                size: CGSize(width: .random(in: 8...14), height: .random(in: 13...20)),
                start: CGSize(width: .random(in: -80...80), height: -CGFloat.random(in: 20...100)),
                launch: CGSize(width: .random(in: -170...170), height: -CGFloat.random(in: 230...450)),
                launchDuration: .random(in: 0.4...0.6),
                fallDrift: .random(in: -70...70),
                fallDuration: .random(in: 1.8...2.6),
                spin: .random(in: -16...16)
            )
        }
        startDate = .now

        // Stop drawing once every piece has fallen off the screen.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.totalDuration))
            startDate = nil
            pieces = []
        }
    }

    /// Where a piece is `t` seconds into the burst, or nil once it's gone.
    private func position(of piece: YaraConfetti, at t: Double,
                          from base: CGPoint, screenHeight: CGFloat) -> CGPoint? {
        let start = CGPoint(x: base.x + piece.start.width, y: base.y + piece.start.height)

        if t < piece.launchDuration {
            // Shoot up, slowing down at the top (ease out).
            let u = t / piece.launchDuration
            let eased = 1 - (1 - u) * (1 - u)
            return CGPoint(x: start.x + piece.launch.width * eased,
                           y: start.y + piece.launch.height * eased)
        }

        // Then fall the height of the screen, speeding up (ease in).
        let u = (t - piece.launchDuration) / piece.fallDuration
        guard u < 1 else { return nil }
        let eased = u * u
        return CGPoint(x: start.x + piece.launch.width + piece.fallDrift * eased,
                       y: start.y + piece.launch.height + screenHeight * eased)
    }
}

// ========================================================================
// MARK: - LEVEL COMPLETE CARD
// ========================================================================

struct LevelCompleteOverlay: View {
    let title: String
    let message: String
    let showsNext: Bool
    let onReplay: () -> Void
    let onNext: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .multilineTextAlignment(.center)

                HStack(spacing: 22) {
                    ArtButton(asset: Art.redoButton, width: 72, label: "Play again", action: onReplay)

                    if showsNext {
                        Button(action: onNext) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 30, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Circle().fill(Theme.appleRed))
                                .overlay(Circle().strokeBorder(Theme.flesh, lineWidth: 5))
                        }
                        .buttonStyle(SquishyButtonStyle())
                        .accessibilityLabel("Next level")
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Theme.cream)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            )
            .padding(24)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
    }
}
