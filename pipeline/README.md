# Camera dataset pipeline

Builds the signed South Australia camera dataset (`sa-cameras.json`) that the app downloads.
Everything comes from open government data; no third-party camera sites are used.

| Source | What it gives | Licence |
| --- | --- | --- |
| SAPOL Camera Offence Reports, data.sa.gov.au (current and previous financial year) | every fixed and mobile camera site that issued a notice, its location text, offences and zone speed limit | CC BY |
| Location SA Roads (GDA2020 GeoJSON) | road lines with names, types, one-way flags and suburbs on each side | CC BY 3.0 AU |
| Location SA Suburbs and Localities | suburb centres | CC BY 3.0 AU |

## How cameras are placed (automatic only, for now)

- **Two roads** ("Greenhill Rd and Hutt Rd, Adelaide") become a **point** where the roads meet, nearest the suburb.
- **One road in a suburb** (mid-block speed cameras, phone cameras, red light cameras at pedestrian crossings, mobile camera sites) becomes a **zone**: that road within the suburb, because the reports don't say where along the road the camera is.
- **One road between two places** ("Dukes Hwy, Ki Ki to Coonalpyn") becomes an **average speed section** routed along the road from the first place to the second, enforced in that direction only.
- Sites that only ever record unregistered or uninsured vehicles are left out: they aren't speed, red light or phone cameras.
- Sites with the same location and kind of camera (one code per lane, or a speed-only code at a red light camera) are merged.

Each build writes `build/build-report.md` listing what was placed, merged, skipped and not placed (with the reason).

## Run it

```bash
cd pipeline
python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -t .
.venv/bin/python -m zonewatch_pipeline build --out build --key ~/.config/zonewatch/dataset-signing-key.pem
```

Downloads are cached in `.cache/` (offence reports for 20 hours, maps for 30 days). The first run downloads about 220 MB of maps.

## Signing

The dataset is signed with Ed25519. The app holds the public key (`DatasetSignature.publicKey` in ZoneWatchKit) and rejects a dataset whose signature doesn't match.

- The private key lives outside the repository: `~/.config/zonewatch/dataset-signing-key.pem` (made with `python -m zonewatch_pipeline keygen --out <path>`). Never commit it.
- GitHub Actions reads it from the `ZW_SIGNING_KEY` repository secret. Without that secret the daily job builds and validates but doesn't publish.

## Daily job

`.github/workflows/dataset.yml` runs at 06:00 Adelaide time. It builds, validates (no entries outside SA, at least 80% of fixed sites placed, no drop of more than 20% from the last published dataset) and, when the content changed, uploads the dataset, signature and report to the `dataset-sa` GitHub release. That release is interim hosting until the Cloudflare backend exists (Phase 4).

## Dataset format

See the docstring at the top of `zonewatch_pipeline/dataset.py`.
