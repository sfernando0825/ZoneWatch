# ZoneWatch

ZoneWatch is a free iPhone and CarPlay app that warns Australian drivers, by sound and on screen, when they approach a fixed or mobile speed camera. It launches in South Australia first.

It works only from published government camera locations and crowd reports. It never uses radar or laser detection.

## Repository layout

| Folder | What it holds |
| --- | --- |
| `ios/` | The iPhone app, the Live Activity extension and the `ZoneWatchKit` Swift package |
| `pipeline/` | Python jobs that build the signed SA camera dataset (Phase 2) |
| `api/` | Cloudflare Worker for crowd reports (Phase 4) |
| `site/` | Privacy policy, terms and data sources page (Phase 6) |

## Getting started

```bash
brew install xcodegen
cd ios && xcodegen generate && open ZoneWatch.xcodeproj
```

Run the package tests:

```bash
swift test --package-path ios/ZoneWatchKit
```

The camera dataset pipeline has its own README in `pipeline/`.

## Data sources

- Camera sites: Expiation Notice System data, South Australia Police, via data.sa.gov.au (CC BY).
- Roads and suburbs: Location SA, Department for Infrastructure and Transport (CC BY 3.0 AU).

## Status

Phase 2 (camera data). Not released. Only the developer and 3 to 4 private testers will use it until the app is complete.
