"""Reads SAPOL's Camera Offence Reports (data.sa.gov.au, CC BY) and groups notices into camera sites.

Each row is one expiation notice. The columns used here are the camera category (fixed or mobile),
the site code, the location text, the offence, the date and the zone speed limit. No personal data
is kept: vehicle and notice details are read past and dropped.
"""

from __future__ import annotations

import csv
import io
from collections import Counter
from dataclasses import dataclass, field
from datetime import date
from typing import Iterable, TextIO

from .names import Location, parse_location


@dataclass
class Site:
    category: str
    """"fixed" or "mobile"."""
    code: str
    description: str
    suburb_column: str
    notices: int = 0
    offences: Counter = field(default_factory=Counter)
    limits: Counter = field(default_factory=Counter)
    first_seen: date | None = None
    last_seen: date | None = None

    @property
    def location(self) -> Location | None:
        return parse_location(self.description, self.suburb_column)

    @property
    def speed_limit_kmh(self) -> int | None:
        if not self.limits:
            return None
        return int(self.limits.most_common(1)[0][0])

    @property
    def camera_type(self) -> str | None:
        return classify(self)


def _parse_date(text: str) -> date | None:
    try:
        d, m, y = (int(x) for x in text.strip().split("/"))
        return date(y, m, d)
    except ValueError:
        return None


def read_sites(files: Iterable[TextIO]) -> dict[tuple[str, str], Site]:
    """Groups notices by (category, location code) across one or more yearly reports."""
    sites: dict[tuple[str, str], Site] = {}
    seen_events: set[str] = set()
    for fh in files:
        for row in csv.DictReader(fh):
            raw_category = (row.get("Camera Category") or "").strip().upper()
            category = {"FIXED CAMERA": "fixed", "MOBILE CAMERA": "mobile"}.get(raw_category)
            code = (row.get("Location Code") or "").strip()
            if not category or not code:
                continue
            key = (category, code)
            site = sites.get(key)
            if site is None:
                site = sites[key] = Site(
                    category=category,
                    code=code,
                    description=(row.get("Location Description") or "").strip(),
                    suburb_column=(row.get("Location Suburb") or "").strip(),
                )
            event = (row.get("Event ID") or "").strip()
            offence = (row.get("Expiation Offence Description") or "").strip()
            site.offences[offence] += 1
            if event and event not in seen_events:
                seen_events.add(event)
                site.notices += 1
            limit = (row.get("Expiation Zone Speed Limit") or "").strip()
            if limit.isdigit() and not _is_heavy_vehicle(offence):
                site.limits[limit] += 1
            when = _parse_date(row.get("Incident Start Date") or "")
            if when:
                site.first_seen = min(site.first_seen or when, when)
                site.last_seen = max(site.last_seen or when, when)
    return sites


def read_sites_from_paths(paths: Iterable[str]) -> dict[tuple[str, str], Site]:
    handles = [open(p, newline="", encoding="utf-8-sig") for p in paths]
    try:
        return read_sites(handles)
    finally:
        for h in handles:
            h.close()


def read_sites_from_text(text: str) -> dict[tuple[str, str], Site]:
    return read_sites([io.StringIO(text)])


def _is_heavy_vehicle(offence: str) -> bool:
    return "TRUCK" in offence.upper() or "BUS" in offence.upper()


def classify(site: Site) -> str | None:
    """The camera type to show drivers, or None when the site isn't a camera drivers are warned about.

    Some fixed sites only ever record unregistered or uninsured vehicles: they don't enforce speed,
    red lights or phone use, so ZoneWatch doesn't alert for them.
    """
    kinds = {_offence_kind(o) for o in site.offences}
    location = site.location
    if site.category == "mobile":
        return "mobileSpeed" if "speed" in kinds else None
    if location and location.is_between_places:
        return "averageSpeedSection"
    if "redLight" in kinds:
        return "redLightSpeed"
    if "phone" in kinds:
        return "phoneCamera"
    if "speed" in kinds or "averageSpeed" in kinds:
        return "fixedSpeed"
    return None


def _offence_kind(offence: str) -> str:
    o = offence.upper()
    if "AVERAGE SPEED" in o:
        return "averageSpeed"
    if "SPEED" in o:
        return "speed"
    if "RED" in o and ("LIGHT" in o or "ARROW" in o or "DISC" in o):
        return "redLight"
    if "MOBILE PHONE" in o:
        return "phone"
    if "SEATBELT" in o or "SEAT BELT" in o:
        return "seatbelt"
    return "other"
