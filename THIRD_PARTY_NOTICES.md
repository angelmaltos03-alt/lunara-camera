# Third-party research references

LUNARA currently uses its own SwiftUI, AVFoundation, Vision, Core Image, and Metal implementation. The repositories below were reviewed as engineering references; their source files have **not** been copied into LUNARA by this change.

| Project | Relevant ideas reviewed | License / handling |
|---|---|---|
| [Prism](https://github.com/Luminoid/Prism) | Camera session isolation, manual controls, burst/night capture, Metal-backed filters | MIT. Review API availability and attribution before adopting code. |
| [Starlapse](https://github.com/fortunto2/starlapse) | Locked astrophotography controls, lunar capture strategy, alignment and stacking | MIT. Algorithmic reference; port and test independently. |
| [Lumen Camera](https://github.com/Irenapoghosian/lumen-camera) | Shared live-preview and still-image filter pipeline, Metal/Core Image rendering | MIT. Architectural reference; LUNARA maintains its own processing graph. |
| [Raster](https://github.com/aldealabs/raster) | Composable real-time Metal image/video processing | MIT. Candidate for future performance evaluation; not currently a dependency. |
| [Photodew](https://github.com/IgnacioPro/iphone-raw) | RAW/ProRAW capture, camera overlays, RAW rendering and export architecture | No license file was verified during this review. Do not copy or redistribute its source unless a suitable license is confirmed. |
| [Strehl](https://github.com/Dacongan/strehl) | Lucky-imaging frame scoring, alignment and planetary/lunar stacking concepts | GPL-3.0-or-later. Research only; do not port source into this MIT project without a deliberate license-compatibility review. |

This notice records research provenance, not a claim of code reuse or endorsement. Re-check each upstream license and version before adding a package or copying any implementation.
