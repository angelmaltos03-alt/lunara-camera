# LUNARA — Open Source Computational Photography

LUNARA is an experimental native iOS camera project focused on adaptive computational photography. Ordinary photo development runs on-device. Optional cloud-assisted processing is planned as an explicit, consent-based extension.

## Current MVP
- SwiftUI camera interface and AVFoundation photo capture.
- Multi-camera device preference (triple/dual virtual camera, then wide camera) where supported.
- On-device Vision classification for scene recognition and live moon-candidate detection.
- Adaptive Core Image development for portraits, food, landscapes, vehicles, documents, general scenes, and moon captures.
- Zoom slider using the selected camera device's supported zoom range (capped at 12x in this prototype).
- Original/processed comparison and saving to Photos.
- MIT license.

## Moon mode: important limits
Moon detection is best-effort Vision classification, not a guaranteed astronomical detector. The app labels a moon candidate when the preview classifier recognizes one; the captured image is classified again before processing. The current lunar pipeline applies conservative exposure, contrast, and sharpening only to information actually present in the capture. It does **not** synthesize craters or claim digital zoom creates optical detail.

For better moon photos, use a telephoto lens when available, stabilize the phone, avoid overexposure, and capture at the lowest practical ISO with a suitable shutter speed. Manual exposure and multi-frame stacking remain future work.

## Build
1. Open `LunaraCamera.xcodeproj` in Xcode.
2. Select a physical iPhone as the run destination.
3. Set your development team under Signing & Capabilities.
4. Change the bundle identifier if needed for your own build.
5. Run. Camera access is required.

The project currently targets iOS 17.0 or later. It has not yet been compiled or tested on a physical device in this environment.

## Contributions
Contributions are welcome. Please open an issue before large changes, include device/iOS details for camera bugs, and never commit API keys, signing certificates, personal photos, or private credentials.

## Roadmap
- Manual shutter speed, ISO, focus, exposure compensation, and white balance.
- RAW/ProRAW capture where supported.
- Better moon detection and exposure recommendations.
- Burst capture and aligned multi-frame lunar stacking.
- Optional cloud enhancement adapter with explicit per-image consent and secure server-side secrets.
- Automated tests and device compatibility matrix.

## License
MIT. See [LICENSE](LICENSE).
