# QuietCast

QuietCast is an iOS 17+ SwiftUI podcast player for falling asleep. It stays in dark mode, limits volume, fades audio in, and can pause itself after a timer so a show does not play all night.

## Layout

Application source lives in `QuietCast/`:

- SwiftUI screens, audio playback, downloads, RSS parsing, and persistence
- `AppSettings.swift` — UserDefaults keys and defaults
- `Assets.xcassets`, `Info.plist`, and `QuietCast.entitlements`
- `silence.wav` — silent clip used to claim the Now Playing session
- `requirements.md` — feature specification

Shared data uses the App Group `group.com.quietcast.shared`, with a fallback to the app Documents directory when that container is unavailable.

## Xcode project

This repository does not generate an Xcode project. `QuietCast.xcodeproj` has to be created in Xcode and **committed**. Clones cannot build without that project file. Add the `QuietCast/` folder to the app target, include `silence.wav` as a bundle resource, and keep the app group entitlement. Do not leave the `.xcodeproj` only on one machine.
