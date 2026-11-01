//
//  Home.swift
//  RottenApple
//
//  The title screen and the level shelf, built from Reema's artwork
//  (HomeAssets.xcassets). Reema: this is yours to change or replace —
//  it's a starting point so the whole app can be played end to end.
//
//    • TitleScreen       — the splash: logo + closed apple. After a moment the
//                          apple opens into the apple house, then the level
//                          shelf appears by itself.
//    • LevelSelectScreen — the home page: the 3×3 apple buttons. Each one starts
//                          a level; the empty apples (7–9) are levels to come.
//
//  Positions are in the artwork's own pixels (a 1320 × 2868 canvas, the
//  size Reema drew on) and are scaled to fit any iPhone.
//

import SwiftUI

// MARK: - Every level in the game

/// One case per level. Add new levels here (and to `HomeArt.levelButtons`).
enum GameLevel: Hashable {
    case flowers       // Renad — flowers into the basket
    case ladybug       // Wafaa — the ladybug walks home
    case coffee        // Wafaa — pour the coffee
    case worm          // Yara  — clean the apple
    case spiderShoes   // Yara  — shoes for the spider
    case sadu          // Lamya — weave the Sadu
}

// MARK: - Artwork positions

enum HomeArt {
    /// Reema's canvas size, in pixels.
    static let canvas = CGRect(x: 0, y: 0, width: 1320, height: 2868)

    static let background = "home_background"

    // Title screen
    static let titleLogo   = Sprite("home_logo", 160, 330, 1000, 547)
    static let closedApple = Sprite("home_closed_apple", 145, 1575, 1053, 1077)
    static let openApple   = Sprite("home_open_apple", 121, 1520, 1100, 1161)

    // Level shelf
    static let shelfLogo  = Sprite("home_logo", 300, 260, 720, 394)
    static let shelfHouse = Sprite("home_open_apple", 255, 1880, 810, 855)

    /// Reema's apple buttons, where she placed them, moved down to sit
    /// under the logo. `level` is nil for apples that don't have a level yet.
    static let levelButtons: [(sprite: Sprite, level: GameLevel?)] = {
        let down: CGFloat = 640
        return [
            (Sprite("level_icon_1", 138, 183 + down, 300, 291), .flowers),
            (Sprite("level_icon_2", 516, 176 + down, 300, 291), .ladybug),
            (Sprite("level_icon_6", 883, 181 + down, 300, 291), .sadu),
            (Sprite("level_icon_3", 142, 521 + down, 289, 291), .coffee),
            (Sprite("level_icon_5", 510, 509 + down, 300, 291), .spiderShoes),
            (Sprite("level_icon_4", 888, 518 + down, 300, 291), .worm),
            (Sprite("level_icon_7", 143, 836 + down, 299, 291), nil),
            (Sprite("level_icon_8", 517, 835 + down, 300, 292), nil),
            (Sprite("level_icon_9", 873, 841 + down, 300, 291), nil),
        ]
    }()
}

// MARK: - Title screen (splash)

/// Shows the logo and the closed apple for a moment, opens the apple into
/// the apple house, then moves on to the level shelf by itself.
struct TitleScreen: View {
    let onStart: () -> Void

    /// How long the closed apple shows before it opens.
    static let closedTime: Duration = .seconds(1.6)
    /// How long the open apple house shows before the level shelf.
    static let openTime: Duration = .seconds(1.4)

    @State private var isOpen = false
    @State private var wobble = 0

    var body: some View {
        GeometryReader { geo in
            let space = CanvasSpace(focus: HomeArt.canvas, in: geo.size, padding: 0)
            ZStack {
                ArtImage(HomeArt.titleLogo, in: space)

                if !isOpen {
                    ArtImage(HomeArt.closedApple, in: space)
                        .keyframeAnimator(initialValue: 0.0, trigger: wobble) { content, angle in
                            content.rotationEffect(.degrees(angle), anchor: .bottom)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(-6, duration: 0.08)
                                CubicKeyframe(6, duration: 0.1)
                                CubicKeyframe(-3, duration: 0.08)
                                SpringKeyframe(0, duration: 0.2)
                            }
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    ArtImage(HomeArt.openApple, in: space)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(HomeBackground())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotten Apple")
        .task { await playSplash() }
    }

    private func playSplash() async {
        try? await Task.sleep(for: Self.closedTime)
        wobble += 1
        HapticManager.shared.impact(.medium)
        try? await Task.sleep(for: .milliseconds(300))
        HapticManager.shared.impact(.heavy)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { isOpen = true }
        try? await Task.sleep(for: Self.openTime)
        onStart()
    }
}

// MARK: - Level shelf

struct LevelSelectScreen: View {
    let onPick: (GameLevel) -> Void

    /// Bumped when a not-yet-made apple is tapped, to shake it.
    @State private var shake: [Int: Int] = [:]

    var body: some View {
        GeometryReader { geo in
            let space = CanvasSpace(focus: HomeArt.canvas, in: geo.size, padding: 0)
            ZStack {
                ArtImage(HomeArt.shelfLogo, in: space)
                ArtImage(HomeArt.shelfHouse, in: space)

                ForEach(HomeArt.levelButtons.indices, id: \.self) { index in
                    levelButton(index, space: space)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(HomeBackground())
    }

    private func levelButton(_ index: Int, space: CanvasSpace) -> some View {
        let item = HomeArt.levelButtons[index]
        let size = space.size(item.sprite.rect.size)

        return Button {
            if let level = item.level {
                onPick(level)
            } else {
                shake[index, default: 0] += 1
                HapticManager.shared.play([.init(.rigid, 0.6),
                                           .init(.rigid, 0.6, after: .milliseconds(90))])
            }
        } label: {
            Image(item.sprite.name)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .opacity(item.level == nil ? 0.6 : 1)
        }
        .buttonStyle(SquishyButtonStyle())
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shake[index, default: 0]) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-8, duration: 0.06)
                CubicKeyframe(8, duration: 0.08)
                CubicKeyframe(-5, duration: 0.07)
                SpringKeyframe(0, duration: 0.15)
            }
        }
        .position(space.point(item.sprite.rect.center))
        .accessibilityLabel(item.level == nil ? "Coming soon" : "Level \(index + 1)")
    }
}

/// Reema's sky-and-grass background, filling the whole screen.
private struct HomeBackground: View {
    var body: some View {
        Image(HomeArt.background)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
}

#Preview("Title") {
    TitleScreen(onStart: {})
}

#Preview("Levels") {
    LevelSelectScreen(onPick: { _ in })
}
