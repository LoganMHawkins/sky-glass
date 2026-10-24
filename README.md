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
| Satellite download (proxy → CelesTrak → cache, 6 h), propagation, pass prediction | `Skyglass/Satellites/SatelliteTracker.swift` |
| CelesTrak caching proxy (Cloudflare Worker) | `proxy/` |
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

Run on a real iPhone for the camera AR view. Satellite data is cached on the device for 6 hours.

## Satellite data proxy

CelesTrak answers each query only once per IP per update window (about 2 hours) and returns HTTP 403
otherwise, so phones behind a shared IP (carrier NAT, office Wi-Fi) compete for one quota. `proxy/` is a
Cloudflare Worker that downloads each group on a cron every 2 hours, keeps the last good copy in KV and
serves it to every client:

- `GET /gp/{stations,visual,starlink,active}.json` → the CelesTrak GP JSON array.
- A refused, non-200 or non-array CelesTrak response is never stored or passed on; the old copy stays.
- Before the first cron run, a request for an empty group triggers one fetch; if that fails the Worker answers 503.

The app tries, in order: fresh on-device cache → proxy → CelesTrak directly → stale on-device cache, and
still falls back to filtering the `active` catalogue if a group query fails everywhere.

### Deploy

```bash
cd proxy
npm install
npx wrangler login        # once
npx wrangler deploy       # first deploy also creates the KV namespace
```

It is deployed at `https://skyglass-proxy.logan-d80.workers.dev` (KV namespace `skyglass-proxy-gp`), which is
the `SKYGLASS_PROXY_URL` in `project.yml`. If that URL changes, update the setting and run `xcodegen generate`;
an empty value makes the app go straight to CelesTrak. Check the cron with `npx wrangler tail`.

### Run it locally

```bash
cd proxy
npx wrangler dev --test-scheduled --ip 127.0.0.1
curl http://127.0.0.1:8787/__scheduled   # runs the cron once to fill local KV
```

Launch the Simulator build with the `SKYGLASS_PROXY_URL` environment variable (Xcode scheme → Run →
Environment, or `SIMCTL_CHILD_SKYGLASS_PROXY_URL=http://127.0.0.1:8787 xcrun simctl launch …`); it
overrides the Info.plist value.
