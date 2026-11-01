# Rotten Apple

Native SwiftUI iPhone app with two offline mini-games.

## Run

Open `RottenApple.xcodeproj` in Xcode, choose the `RottenApple` scheme and an iPhone simulator or device, then Run. The app starts at the level menu; tap either card to play.

## Included artwork and feedback

- The spider and apple illustrations, hand-drawn home-screen palette, and PDF level backdrop come from the supplied `RottenApple Assets` folder. Cropped transparent versions are included in `RottenApple/Assets.xcassets`.
- The source sheet contains four shoe illustrations. They fill the first four slots; slots five through eight use simple, in-palette boot placeholders in `ShoeArtwork` until the remaining four drawings are available.
- The apple artwork contains five visible seeds; the configurable seed count is `seedCount` in `AppleCleaningLevelView`.
- UIKit impact and notification generators provide light pickup, placement/removal, and completion haptics. No local sound files were supplied, so sound is omitted; add bundled audio in the asset catalog and call it from the level completion handlers if desired.
- All game state and assets are local. No network, account, or backend is used.
