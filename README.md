# LUNARA — Open Source Computational Photography

[![iOS build](https://github.com/angelmaltos03-alt/lunara-camera/actions/workflows/ios-build.yml/badge.svg)](https://github.com/angelmaltos03-alt/lunara-camera/actions/workflows/ios-build.yml)

LUNARA is an experimental native iOS camera focused on natural, adaptive computational photography. Standard photo development runs locally on the iPhone. Optional cloud-assisted processing is planned only as an explicit, consent-based extension.

## Current MVP

- SwiftUI camera interface and AVFoundation photo capture.
- Multi-camera device preference (triple/dual virtual camera, then wide camera) where supported.
- On-device Vision classification for scene recognition and live moon-candidate detection.
- Scene-aware Core Image development for portraits, food, landscapes, vehicles, documents, general scenes, and moon captures.
- **AUTO mode:** conservative corrections based on the detected scene.
- **PRO mode:** live hardware-aware ISO, shutter speed, manual lens focus, and white-balance temperature controls, plus non-destructive image-development adjustments (contrast, saturation, warmth, definition). Values are clamped to the active camera format's reported limits.
- Creative looks: Natural, Vivid, Warm, Cool, and Mono, with adjustable intensity.
- Original/processed comparison and saving the optimized copy to Photos.
- Zoom slider using the active camera device's reported range (capped at 40x; actual range depends on hardware and active format).
- Dedicated Moon Mode with a seven-frame high-resolution burst, minimum-ISO short exposures, and infinity-focus lock where supported.
- On-device lunar frame scoring using an edge-detail metric, Vision translational registration against the sharpest reference, and aligned weighted averaging. If registration is insufficient, LUNARA falls back to the sharpest single frame.
- MIT license.

## Editing behavior and limits

The original capture is kept unchanged. LUNARA re-runs its development pipeline from that original whenever a user changes an editing control, avoiding cumulative edits and quality loss from repeatedly processing an already processed copy.

The live viewfinder is rendered with Metal and runs through the same Core Image development graph as the full-resolution still. Scene classification is updated periodically from preview frames; the still is independently analyzed after capture, so scene classification can occasionally differ. The preview is a real-time approximation at video-frame resolution, while the saved image uses the full-resolution photo sensor output.

Moon detection is best-effort Vision classification, not a guaranteed astronomical detector. Moon Mode captures seven frames with a short, hardware-bounded exposure and minimum ISO, scores detail, aligns frames with Vision translational registration, and averages only successfully registered frames. If fewer than two frames can be aligned, it falls back to the sharpest source frame. This is a first-generation local stacker: motion, clouds, atmospheric turbulence, exposure drift, and camera shake can still reduce quality. It does **not** synthesize craters or claim digital zoom creates optical detail.

## Build

1. Open `LunaraCamera/LunaraCamera.xcodeproj` in Xcode.
2. Select a physical iPhone as the run destination.
3. Set your development team under Signing & Capabilities.
4. Change the bundle identifier if needed for your own build.
5. Run. Camera access is required.

The project currently targets iOS 17.0 or later. GitHub Actions builds the iOS Simulator target on macOS; a successful simulator build does not replace testing on a physical iPhone.

## Open-source reference

The editing controls and image-development architecture were informed by **[Lumen Camera](https://github.com/Irenapoghosian/lumen-camera)**, a Swift camera project that demonstrates a shared image-filter pipeline for live preview and full-resolution captures, adjustable filter intensity, and GPU rendering with Core Image/Metal. LUNARA now uses its own shared Core Image development graph for both Metal-rendered live frames and full-resolution stills. Lumen's architecture informed this implementation. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributions

Contributions are welcome. Please open an issue before large changes, include device/iOS details for camera bugs, and never commit API keys, signing certificates, personal photos, or private credentials.

## Roadmap

- Manual focus, shutter speed, ISO, exposure compensation, and white balance.
- RAW/ProRAW capture where supported.
- Dedicated astronomical moon detector and scene-aware exposure recommendations.
- Burst capture and aligned multi-frame lunar stacking (not yet implemented).
- Automated tests and a physical-device compatibility matrix.
- Optional cloud enhancement adapter with explicit per-image consent and secure server-side secrets.

## License

MIT. See [LICENSE](LICENSE).
