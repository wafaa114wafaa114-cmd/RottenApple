//
//  Reema.swift
//  RottenApple
//
//  Reema's splash screen: the closed apple, then it dissolves into the open
//  apple house while the logo grows in. After that the app moves on to the
//  level page by itself (or straight away if the player taps).
//
//  CHANGED for the full app (Reema's animation itself is unchanged):
//  • `ContentView` → `Reema`: the app's ContentView moves between screens,
//    so the splash has its own name and tells the app when it's finished.
//  • No NavigationStack / LevelsView here: ContentView shows the level page.
//  • "background" → "home_background" (the same picture): Wafaa's and
//    Lamya's levels also have an image called "background".
//  • The swirl_icon / apple_icon block is left out for now: those two
//    pictures aren't in the project yet. Add the images and put the block back.
//

import SwiftUI

struct Reema: View {

    /// Called when the splash is done, to move on to the level page.
    let onFinished: () -> Void

    enum Stage { case closed, open }

    @State private var stage: Stage = .closed
    @State private var didFinish = false

    // MARK: - Tweakable values
    private let pauseOnClosedApple: Double = 1.0   // seconds on the closed apple before it opens
    private let openDuration: Double = 0.6         // closed -> open dissolve
    private let logoStartScale: CGFloat = 0.3      // logo starts this small, grows to 1
    private let pauseOnOpenApple: Double = 1.5     // ADDED: seconds on the open apple before the level page

    // MARK: - Measured from the PNG files (pixels)
    private let closedImageSize = CGSize(width: 1320, height: 2868)
    private let closedApple = CGRect(x: 161, y: 1589, width: 1029, height: 1057)
    private let openImageSize = CGSize(width: 2732, height: 2048)
    private let openApple = CGRect(x: 582, y: 167, width: 1695, height: 1785)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Where the closed apple really sits on screen (it is scaledToFill)
            let fill = max(w / closedImageSize.width, h / closedImageSize.height)
            let closedCenter = CGPoint(
                x: w / 2 + (closedApple.midX - closedImageSize.width / 2) * fill,
                y: h / 2 + (closedApple.midY - closedImageSize.height / 2) * fill)

            // Scale the open image so its apple matches the closed apple's width
            let k = closedApple.width * fill / openApple.width
            let openFrame = CGSize(width: openImageSize.width * k, height: openImageSize.height * k)
            let offset = CGPoint(x: (openApple.midX - openImageSize.width / 2) * k,
                                 y: (openApple.midY - openImageSize.height / 2) * k)

            ZStack {
                // Background
                Image("home_background")
                    .resizable().scaledToFill()
                    .frame(width: w, height: h).clipped()

                // Closed apple – visible only at the start
                Image("closed_apple")
                    .resizable().scaledToFill()
                    .frame(width: w, height: h).clipped()
                    .opacity(stage == .closed ? 1 : 0)
                    .animation(.easeInOut(duration: openDuration), value: stage)

                // Open apple – same spot as the closed apple
                Image("open_apple")
                    .resizable()
                    .frame(width: openFrame.width, height: openFrame.height)
                    .position(x: closedCenter.x - offset.x, y: closedCenter.y - offset.y)
                    .opacity(stage == .closed ? 0 : 1)
                    .animation(.easeInOut(duration: openDuration), value: stage)

                // Logo – appears small and grows while the apple opens
                Image("logo")
                    .resizable().scaledToFit()
                    .frame(width: w * 0.875)
                    .scaleEffect(stage == .closed ? logoStartScale : 1.0)
                    .opacity(stage == .closed ? 0 : 1)
                    .position(x: w * 0.505, y: h * 0.346)
                    .animation(.spring(response: 1.0, dampingFraction: 0.65), value: stage)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture {
                if stage == .open {
                    finish()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { startSplash() }
    }

    // MARK: - Flow

    /// Waits on the closed apple, then opens it (logo comes in with it),
    /// then moves on to the level page.
    private func startSplash() {
        stage = .closed
        Task {
            try? await Task.sleep(nanoseconds: UInt64(pauseOnClosedApple * 1_000_000_000))
            stage = .open
            // ADDED: move on by itself after a moment on the open apple.
            try? await Task.sleep(nanoseconds: UInt64((openDuration + pauseOnOpenApple) * 1_000_000_000))
            finish()
        }
    }

    /// ADDED: tells the app the splash is done (only once).
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

#Preview {
    Reema(onFinished: {})
}
