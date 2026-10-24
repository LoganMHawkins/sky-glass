# Skyglass

Point your iPhone at the sky and see what's there — stars, the Moon, the Sun, planets, deep-sky
objects, satellites, the ISS and Starlink — drawn over the live camera with a Liquid Glass,
red/purple/pink space theme.

## Features

- **Camera AR view** — CoreMotion attitude (true north) + camera field of view line the overlay up with the real sky. Pinch to zoom.
- **Three layers** (glass toggles at the bottom):
  - **Sky** — ~150 bright stars with constellation figures, Sun, Moon (with live phase), all 7 planets, and 21 notable deep-sky objects.
  - **Satellites** — CelesTrak `stations` + `visual` groups (ISS, Tiangong, Hubble, bright rocket bodies…), with motion trails and sunlit/shadow state.
  - **Starlink** — the whole constellation (~10k), only drawn when above the horizon.
- **At a glance** — whatever sits under the reticle (or whatever you tap) gets a glass card with three key stats.
- **Full overview** — a detail sheet per object: live position, physical facts, rise/transit/set, moon phase dates, and for satellites the orbit, identity and predicted passes for the next 48 h (marked visible when sunlit against a dark sky).
- **Explore/search** — every object, filterable by layer; picking one shows an edge arrow guiding you to it.
- **Simulator** — no motion hardware, so it shows a virtual sky you can drag around.

## How it works

| Area | File |
| --- | --- |
| Sun / Moon / planets (Schlyter low-precision elements, Moon parallax) | `Skyglass/Astro/SolarSystem.swift` |
| Star + deep-sky catalogues, constellation lines | `Skyglass/Astro/StarCatalog.swift` |
| Coordinates, precession, refraction, rise/set | `Skyglass/Astro/AstroMath.swift` |
| SGP4 near-earth propagator (verified against Vallado's test vectors) | `Skyglass/Satellites/SGP4.swift` |
| CelesTrak download/cache (6 h), propagation, pass prediction | `Skyglass/Satellites/SatelliteTracker.swift` |
| Motion → camera basis, camera, location | `Skyglass/Sensors/` |
| Per-second refresh, hit-testing, projection | `Skyglass/Sky/SkyModel.swift` |
| Per-frame Canvas drawing | `Skyglass/Sky/SkyRenderer.swift` |
| Glance + detail content | `Skyglass/Sky/ObjectInfo.swift` |
| UI (Liquid Glass) | `Skyglass/Views/` |

Sky frame everywhere: x = true north, y = west, z = up (matches `CMAttitudeReferenceFrame.xTrueNorthZVertical`).

## Build

Requires Xcode 26+ (iOS 26 SDK for Liquid Glass) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open Skyglass.xcodeproj
```

Run on a real iPhone for the camera AR view. Satellite data comes from CelesTrak and is cached for 6 hours.
