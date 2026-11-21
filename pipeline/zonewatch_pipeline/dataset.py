"""Assembles, checks and signs the camera dataset the app downloads.

Format (schemaVersion 1), compact JSON, UTF-8:

{
  "schemaVersion": 1, "region": "SA", "version": 20261122,
  "generatedAt": "2026-11-22T03:00:00Z", "dataThrough": "2026-10-31",
  "attribution": ["..."],
  "cameras": [   // a known point, e.g. a red light and speed camera at an intersection
    {"id": "sa-f-51", "type": "redLightSpeed", "lat": -34.9, "lon": 138.6, "heading": null,
     "road": "Greenhill Road & Hutt Road", "suburb": "Adelaide", "speedLimitKmh": 60,
     "lastSeen": "2026-10-30", "notices": 414}
  ],
  "zones": [     // a stretch of road where the camera stands somewhere along it
    {"id": "sa-m-1865", "type": "mobileSpeed", "paths": [[[-34.9, 138.5], ...]], "oneWay": false,
     "road": "Port Road", "suburb": "Cheltenham", "speedLimitKmh": 60,
     "lastSeen": "2026-10-12", "notices": 30, "lengthM": 1450}
  ]
}

"heading" is the direction of travel the camera enforces in degrees, or null for every direction.
For a zone with "oneWay": true, only travel in the direction its single path is drawn is enforced.
Coordinates are [lat, lon] in WGS84 degrees (GDA2020 source, the difference is under a metre).
"""

from __future__ import annotations

import base64
import hashlib
import json
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, timezone

from .geometry import distance_m, length_m, simplify, stitch
from .names import Location, title
from .offences import Site
from .place import SIMPLIFY_M, Placer, PointPlacement, Unplaced, ZonePlacement
from .sources import ATTRIBUTION

SCHEMA_VERSION = 1
SA_BOUNDS = (-38.2, 128.9, -25.9, 141.1)  # south, west, north, east
MIN_FIXED_PLACED_RATE = 0.8


@dataclass
class BuildReport:
    placed: Counter = field(default_factory=Counter)
    unplaced: list = field(default_factory=list)
    skipped: list = field(default_factory=list)
    merged: list = field(default_factory=list)

    def markdown(self) -> str:
        lines = ["# Camera dataset build report", "", "## Placed", ""]
        lines += [f"- {k}: {v}" for k, v in sorted(self.placed.items())]
        lines += ["", f"## Not placed ({len(self.unplaced)})", ""]
        lines += [f"- `{sid}` {desc}: {reason}" for sid, desc, reason in self.unplaced]
        lines += ["", f"## Skipped, not a camera ZoneWatch alerts for ({len(self.skipped)})", ""]
        lines += [f"- `{sid}` {desc}" for sid, desc in self.skipped]
        lines += ["", f"## Merged sites with the same location ({len(self.merged)})", ""]
        lines += [f"- {', '.join(ids)}: {desc}" for ids, desc in self.merged]
        return "\n".join(lines) + "\n"


def _code_order(code: str):
    return (0, int(code)) if code.isdigit() else (1, code)


def _road_text(location: Location) -> str:
    return " & ".join(r.display() for r in location.roads)


def _suburb_text(location: Location) -> str:
    return " to ".join(title(s) for s in location.suburbs)


def build(sites: dict, placer: Placer, generated_at: datetime | None = None) -> tuple[dict, BuildReport]:
    report = BuildReport()
    generated_at = generated_at or datetime.now(timezone.utc)

    # Same camera type at the same described place: one entry (e.g. one site code per lane).
    groups: dict[tuple, list[Site]] = {}
    for (category, code), site in sorted(sites.items(), key=lambda kv: (kv[0][0], _code_order(kv[0][1]))):
        sid = f"sa-{category[0]}-{code}"
        camera_type = site.camera_type
        location = site.location
        if camera_type is None:
            report.skipped.append((sid, site.description))
            continue
        if location is None:
            report.unplaced.append((sid, site.description, "could not read the location"))
            continue
        # A speed-only code at a red light camera site is the same camera box.
        kind = "redLightOrSpeed" if camera_type in ("redLightSpeed", "fixedSpeed") else camera_type
        key = (category, kind, location.roads, location.suburbs)
        groups.setdefault(key, []).append(site)

    cameras, zones = [], []
    data_through: date | None = None
    for (category, kind, _, _), members in groups.items():
        members.sort(key=lambda s: _code_order(s.code))
        types = {m.camera_type for m in members}
        camera_type = ("redLightSpeed" if "redLightSpeed" in types else "fixedSpeed") if kind == "redLightOrSpeed" else kind
        first = members[0]
        sid = f"sa-{category[0]}-{first.code}"
        if len(members) > 1:
            report.merged.append(([f"sa-{category[0]}-{m.code}" for m in members], first.description))
        location = first.location
        placement = placer.place(location)
        if isinstance(placement, Unplaced):
            report.unplaced.append((sid, first.description, placement.reason))
            continue
        last_seen = max(m.last_seen for m in members if m.last_seen)
        data_through = max(data_through or last_seen, last_seen)
        limits = Counter()
        for m in members:
            limits.update(m.limits)
        common = {
            "id": sid,
            "type": camera_type,
            "road": _road_text(location),
            "suburb": _suburb_text(location),
            "speedLimitKmh": int(limits.most_common(1)[0][0]) if limits else None,
            "lastSeen": last_seen.isoformat(),
            "notices": sum(m.notices for m in members),
        }
        if isinstance(placement, PointPlacement):
            lat, lon = placement.point
            cameras.append({**common, "lat": round(lat, 6), "lon": round(lon, 6), "heading": None})
            report.placed[f"{camera_type} (point)"] += 1
        else:
            assert isinstance(placement, ZonePlacement)
            zones.append({
                **common,
                "paths": [[[round(lat, 5), round(lon, 5)] for lat, lon in path] for path in placement.paths],
                "oneWay": placement.one_way,
                "lengthM": round(placement.length_m),
            })
            report.placed[f"{camera_type} (zone)"] += 1

    zones = merge_mobile_runs(zones, report)

    dataset = {
        "schemaVersion": SCHEMA_VERSION,
        "region": "SA",
        "version": int(generated_at.strftime("%Y%m%d")),
        "generatedAt": generated_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dataThrough": data_through.isoformat() if data_through else None,
        "attribution": ATTRIBUTION,
        "cameras": sorted(cameras, key=lambda c: c["id"]),
        "zones": sorted(zones, key=lambda z: z["id"]),
    }
    return dataset, report


JOIN_M = 40.0
"""Mobile zones on the same road whose ends come this close are one continuous run."""


def merge_mobile_runs(zones: list[dict], report: BuildReport) -> list[dict]:
    """Joins mobile camera zones that continue one another along the same road.

    Busy arterials have a mobile site in almost every suburb they pass through. As separate zones
    they would alert every kilometre; as one run they alert once, when the driver joins the road.
    """
    others = [z for z in zones if z["type"] != "mobileSpeed"]
    by_road: dict[str, list[dict]] = {}
    for z in zones:
        if z["type"] == "mobileSpeed":
            by_road.setdefault(z["road"], []).append(z)

    merged = []
    for road, group in by_road.items():
        parent = list(range(len(group)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        ends = [[tuple(p) for path in z["paths"] for p in (path[0], path[-1])] for z in group]
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                if find(i) != find(j) and any(distance_m(a, b) <= JOIN_M for a in ends[i] for b in ends[j]):
                    parent[find(j)] = find(i)
        runs: dict[int, list[dict]] = {}
        for i, z in enumerate(group):
            runs.setdefault(find(i), []).append(z)
        for run in runs.values():
            if len(run) == 1:
                merged.append(run[0])
                continue
            run.sort(key=lambda z: _code_order(z["id"].split("-")[-1]))
            lines = [[tuple(p) for p in path] for z in run for path in z["paths"]]
            paths = [simplify(path, SIMPLIFY_M) for path in stitch(lines)]
            limits = {z["speedLimitKmh"] for z in run}
            suburbs = [z["suburb"] for z in run]
            merged.append({
                "id": run[0]["id"],
                "type": "mobileSpeed",
                "road": road,
                "suburb": suburbs[0] if len(suburbs) == 1 else f"{suburbs[0]} and {len(suburbs) - 1} more suburbs",
                # Limits can change along a road; with no single limit, don't claim one.
                "speedLimitKmh": limits.pop() if len(limits) == 1 else None,
                "lastSeen": max(z["lastSeen"] for z in run),
                "notices": sum(z["notices"] for z in run),
                "paths": [[[round(lat, 5), round(lon, 5)] for lat, lon in path] for path in paths],
                "oneWay": False,
                "lengthM": round(sum(length_m(path) for path in paths)),
            })
            report.merged.append(([z["id"] for z in run], f"mobile sites along {road}"))
    return others + merged


class ValidationError(Exception):
    pass


def validate(dataset: dict, report: BuildReport | None = None, previous: dict | None = None, min_fixed: int = 50) -> None:
    problems = []
    if dataset.get("schemaVersion") != SCHEMA_VERSION:
        problems.append("wrong schemaVersion")
    ids = [e["id"] for e in dataset["cameras"] + dataset["zones"]]
    if len(ids) != len(set(ids)):
        problems.append("duplicate ids")
    south, west, north, east = SA_BOUNDS

    def inside(lat, lon):
        return south <= lat <= north and west <= lon <= east

    for c in dataset["cameras"]:
        if not inside(c["lat"], c["lon"]):
            problems.append(f"{c['id']} outside South Australia")
    for z in dataset["zones"]:
        if not z["paths"] or any(len(p) < 2 for p in z["paths"]):
            problems.append(f"{z['id']} has an empty path")
        elif not all(inside(lat, lon) for p in z["paths"] for lat, lon in p):
            problems.append(f"{z['id']} outside South Australia")
        if z["oneWay"] and len(z["paths"]) != 1:
            problems.append(f"{z['id']} is one way but has {len(z['paths'])} paths")
    for e in dataset["cameras"] + dataset["zones"]:
        limit = e["speedLimitKmh"]
        if limit is not None and not 10 <= limit <= 130:
            problems.append(f"{e['id']} has speed limit {limit}")
    fixed = [e for e in dataset["cameras"] + dataset["zones"] if e["id"].startswith("sa-f-")]
    if len(fixed) < min_fixed:
        problems.append(f"only {len(fixed)} fixed cameras")
    if report is not None:
        unplaced_fixed = [u for u in report.unplaced if u[0].startswith("sa-f-")]
        rate = len(fixed) / max(1, len(fixed) + len(unplaced_fixed))
        if rate < MIN_FIXED_PLACED_RATE:
            problems.append(f"only {rate:.0%} of fixed sites placed")
    if previous is not None:
        before = len(previous.get("cameras", [])) + len(previous.get("zones", []))
        after = len(dataset["cameras"]) + len(dataset["zones"])
        if before and after < before * 0.8:
            problems.append(f"entries dropped from {before} to {after}")
    if problems:
        raise ValidationError("; ".join(problems))


def encode(dataset: dict) -> bytes:
    return json.dumps(dataset, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def content_hash(dataset: dict) -> str:
    """Hash of everything except the build time, to tell whether a new build changed anything."""
    stable = {k: v for k, v in dataset.items() if k not in ("generatedAt", "version")}
    return hashlib.sha256(encode(stable)).hexdigest()


def sign(data: bytes, private_key_pem: bytes) -> str:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    key = load_pem_private_key(private_key_pem, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise ValueError("signing key must be Ed25519")
    return base64.b64encode(key.sign(data)).decode("ascii")


def verify(data: bytes, signature_b64: str, public_key_b64: str) -> bool:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_b64))
    try:
        key.verify(base64.b64decode(signature_b64), data)
        return True
    except InvalidSignature:
        return False


def generate_key() -> tuple[bytes, str]:
    """A new Ed25519 key: (private key PEM, raw public key in base64 for the app)."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    key = Ed25519PrivateKey.generate()
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return pem, base64.b64encode(public).decode("ascii")
