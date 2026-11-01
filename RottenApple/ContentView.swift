//
//  ContentView.swift
//  RottenApple
//
//  Moves between the title screen, the level shelf and each level.
//
//  The splash plays once, then the level shelf is the home page.
//  Every level has a home button (back to the shelf) in its top-left corner,
//  and the same "well done" card when it's won, with redo and next. Next goes
//  to the following level in `GameLevel.playOrder`; on the last level the card
//  shows a home button instead of next.
//
//  To add a level: add a case to `GameLevel` (Home.swift), give it an apple
//  button in `HomeArt.levelButtons`, add it to `playOrder` and `doneText`
//  below, and show its view in `levelView`.
//

import SwiftUI

struct ContentView: View {
    enum Screen: Equatable {
        case title
        case levels
        case playing(GameLevel)
    }

    @State private var screen: Screen = .title
    /// Changing this rebuilds the current level from scratch (redo).
    @State private var runID = UUID()
    @State private var isShowingDone = false

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleScreen(onStart: { screen = .levels })
                    .transition(.opacity)

            case .levels:
                LevelSelectScreen(onPick: { play($0) })
                    .transition(.opacity)

            case .playing(let level):
                // Pinned to the screen's size: some levels draw wider than the
                // screen, which would push the home button off the edge.
                GeometryReader { geo in
                    levelView(level)
                        .id(runID)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: .topLeading) { homeButton }
                        .overlay {
                            if isShowingDone {
                                let text = level.doneText
                                LevelCompleteOverlay(title: text.title,
                                                     message: text.message,
                                                     showsNext: true,
                                                     nextGoesHome: level.next == nil,
                                                     onReplay: { replay() },
                                                     onNext: { next(after: level) })
                                    .transition(.opacity)
                            }
                        }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: screen)
        .animation(.easeInOut(duration: 0.25), value: isShowingDone)
        .animation(.easeInOut(duration: 0.25), value: runID)
        .preferredColorScheme(.light)
        .statusBarHidden()
        // Let drags near the screen edges reach the games first.
        .defersSystemGestures(on: .all)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            HapticManager.shared.prepare()
            YaraSoundManager.shared.prepare()
        }
    }

    // MARK: Home button on every level

    private var homeButton: some View {
        ArtButton(asset: Art.homeButton, width: 54, label: "Home") {
            goHome()
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    // MARK: Moving between levels

    private func play(_ level: GameLevel) {
        isShowingDone = false
        runID = UUID()
        screen = .playing(level)
    }

    private func replay() {
        isShowingDone = false
        runID = UUID()
    }

    private func next(after level: GameLevel) {
        if let nextLevel = level.next {
            play(nextLevel)
        } else {
            goHome()
        }
    }

    private func goHome() {
        isShowingDone = false
        screen = .levels
    }

    /// What a level calls when it's won. Wins from a level that has since
    /// been restarted (redo pressed during the confetti) are ignored.
    private func levelWon(in run: UUID) -> () -> Void {
        return { if run == runID { isShowingDone = true } }
    }

    // MARK: The levels

    @ViewBuilder
    private func levelView(_ level: GameLevel) -> some View {
        let won = levelWon(in: runID)
        switch level {
        case .flowers:     Renad(onComplete: won)
        case .ladybug:     LadybugGameView(onComplete: won)
        case .coffee:      Wafaa(onComplete: won)
        case .worm:        Yara(startAt: .appleCleanup, onLevelComplete: won)
        case .spiderShoes: Yara(startAt: .spiderShoes, onLevelComplete: won)
        case .sadu:        Lamya(onComplete: won)
        }
    }
}

// MARK: - Level order and "well done" text

extension GameLevel {
    /// The order "next" goes through: the numbers on Reema's apple buttons.
    static let playOrder: [GameLevel] = [.flowers, .ladybug, .coffee, .worm, .spiderShoes, .sadu]

    /// The level after this one, or nil after the last level.
    var next: GameLevel? {
        guard let index = Self.playOrder.firstIndex(of: self),
              index + 1 < Self.playOrder.count else { return nil }
        return Self.playOrder[index + 1]
    }

    /// What the "well done" card says for each level.
    var doneText: (title: String, message: String) {
        switch self {
        case .flowers:     ("Basket full!", "Every flower found\nits place.")
        case .ladybug:     ("Welcome home!", "The ladybug made it\nback to the apple.")
        case .coffee:      ("Perfect pour!", "Not a single drop\nspilled.")
        case .worm:        ("Squeaky clean!", "No seeds, no worm.\nJust a happy apple.")
        case .spiderShoes: ("Party ready!", "All eight feet are\nfashionably dressed.")
        case .sadu:        ("Sadu complete!", "Every thread\nwoven in.")
        }
    }
}

#Preview {
    ContentView()
}
