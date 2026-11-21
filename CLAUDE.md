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
- `pipeline/`: Python (stdlib + `cryptography`), builds the signed SA camera dataset daily via `.github/workflows/dataset.yml` (Phase 2).
- `ios/ZoneWatch/Resources/sa-cameras.json(.sig)`: the dataset snapshot built into the app.
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

### Camera dataset (Phase 2)

```bash
cd pipeline
.venv/bin/python -m unittest discover -s tests -t .
.venv/bin/python -m zonewatch_pipeline build --out build --key ~/.config/zonewatch/dataset-signing-key.pem
cp build/sa-cameras.json build/sa-cameras.json.sig ../ios/ZoneWatch/Resources/   # refresh the app's built-in snapshot
```

The venv uses Xcode's Python 3.9 (`/usr/bin/python3 -m venv .venv`) because Homebrew's Python 3.14 has a broken expat on this Mac. Read `build/build-report.md` after a build for sites that weren't placed. The private signing key never goes in the repo; the app holds the public key in `DatasetSignature.publicKey`.

### Simulated drives

```bash
# After installing the app on a booted simulator ($DEV = its UDID)
xcrun simctl privacy $DEV grant location-always com.zonewatch.app
xcrun simctl launch $DEV com.zonewatch.app -ZWStartTestDrive YES   # starts a drive without motion data
# Waypoints go through stdin ('-'): negative latitudes on the command line are read as options.
xcrun simctl location $DEV start --speed=30 --interval=1 - < ios/TestRoutes/GreenhillAnzacToGlenelg.txt
# Drive log: $(xcrun simctl get_app_container $DEV com.zonewatch.app data)/Documents/Drives/
```

`GreenhillAnzacToGlenelg.txt` follows the real road (from the SA Roads map), Greenhill Road west then Anzac Highway to Glenelg, with the real dataset. Expected: red light cameras at Greenhill Rd & Anzac Hwy, Anzac Hwy & Marion Rd and Anzac Hwy & Cross Rd, and one mobile camera site zone for Anzac Highway; no alerts for the cross streets.

The Phase 1 made-up test points (`PrototypeCameras`) still work: add `-ZWPrototypeCameras YES` to the launch and replay `ios/TestRoutes/AnzacHighwayToGlenelg.gpx` in Xcode (Debug > Simulate Location). Expected towards Glenelg: test points 1, 2, 4, 5, 6.

## Conventions

- Swift 6 language mode, strict concurrency. iOS 17 minimum; CarPlay Live Activity features need iOS 26 and go behind `#available`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Bundle IDs: app `com.zonewatch.app`, Live Activity `com.zonewatch.app.LiveActivity`, App Group `group.com.zonewatch.app`.
- Units: metres and metres per second inside the code; km/h only for display and speed limits.
- Commit after each step with passing tests; keep diffs small.
