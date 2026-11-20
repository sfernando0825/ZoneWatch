# ZoneWatch: notes for Claude Code

ZoneWatch is an iOS + CarPlay speed camera alert app for Australian drivers, launching in South Australia. One developer builds it with Claude Code. The spec, data licensing research and the phase-by-phase build plan are in the Claude Docs doc https://claude.ai/artifact/3zp5V9L6drczDVngBgNoQB (tab "ZoneWatch build plan").

## Rules

- **Public repository.** Never commit secrets, signing keys, API tokens, `.env` files or personal data.
- **Never send email** or any message on the developer's behalf without asking first, every time.
- **Every alert decision happens on the phone.** The backend only prepares data and relays crowd reports, so alerts work with no signal.
- **Never use or imply radar or laser detection.** Wording is "speed camera alerts", never "detector".
- **Hands-free while driving.** No UI that asks the driver to touch or pick up the phone while moving.
- Use only government sources and ZoneWatch's own crowd data. Never scrape third-party aggregator sites.

## Layout

- `ios/project.yml`: XcodeGen definition. The `.xcodeproj` is generated and not committed.
- `ios/ZoneWatch/`: app target (SwiftUI).
- `ios/ZoneWatchLiveActivity/`: widget extension for the Live Activity (Lock Screen, Dynamic Island, CarPlay Dashboard).
- `ios/ZoneWatchKit/`: Swift package with all logic that can be tested without a device (alert engine, camera store, models). Keep the app targets thin.
- `pipeline/`: Python, SA dataset ingest (Phase 2).
- `api/`: TypeScript Cloudflare Worker with Hono and D1 (Phase 4).
- `site/`: static site on Cloudflare Pages (Phase 6).

## Commands

```bash
# Generate the Xcode project (run after changing project.yml or adding files)
cd ios && xcodegen generate

# Package tests (fast, run on macOS)
swift test --package-path ios/ZoneWatchKit

# Build the app for the simulator without signing
xcodebuild -project ios/ZoneWatch.xcodeproj -scheme ZoneWatch \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### Simulated drive (Phase 1 proof of concept)

The test cameras in `PrototypeCameras` are made-up points along an approximate Anzac Highway route, not real cameras.

```bash
# After installing the app on a booted simulator ($DEV = its UDID)
xcrun simctl privacy $DEV grant location-always com.zonewatch.app
xcrun simctl launch $DEV com.zonewatch.app -ZWStartTestDrive YES   # starts a drive without motion data
# Waypoints go through stdin ('-'): negative latitudes on the command line are read as options.
printf '%s\n' -34.9365,138.5900 -34.9440,138.5790 -34.9510,138.5690 -34.9560,138.5600 \
  -34.9620,138.5500 -34.9690,138.5390 -34.9760,138.5270 -34.9800,138.5160 \
  | xcrun simctl location $DEV start --speed=30 --interval=1 -
# Drive log: $(xcrun simctl get_app_container $DEV com.zonewatch.app data)/Documents/Drives/
```

In Xcode, `ios/TestRoutes/AnzacHighwayToGlenelg.gpx` replays the same route at 60 km/h (Debug > Simulate Location). Expected alerts towards Glenelg: test points 1, 2, 4, 5, 6 (3 is city-bound only).

## Conventions

- Swift 6 language mode, strict concurrency. iOS 17 minimum; CarPlay Live Activity features need iOS 26 and go behind `#available`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Bundle IDs: app `com.zonewatch.app`, Live Activity `com.zonewatch.app.LiveActivity`, App Group `group.com.zonewatch.app`.
- Units: metres and metres per second inside the code; km/h only for display and speed limits.
- Commit after each step with passing tests; keep diffs small.
