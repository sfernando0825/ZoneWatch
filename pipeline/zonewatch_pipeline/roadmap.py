"""Reads the SA Roads and Suburbs maps (Location SA, data.sa.gov.au, CC BY 3.0 AU).

Roads_GDA2020.geojson is about 600 MB with one feature per line, so it is streamed and only roads
whose names are wanted are parsed. GDA2020 differs from WGS84 by well under a metre, which is far
below what camera alerts need, so coordinates are used as they are.
"""

from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass
from typing import Iterable

from .geometry import LatLon, distance_m
from .names import RoadName, road_key, suburb_key

_NAME = re.compile(r'"name": "([^"]*)"')


@dataclass(frozen=True)
class RoadSegment:
    id: int
    name: str
    key: str
    type: str | None
    suffix: str | None
    road_class: str | None
    one_way: str | None
    """"2W" both ways, "FT" in drawing order, "TF" against it, "N" closed."""
    suburbs: frozenset[str]
    """Suburb keys on the left and right of the segment."""
    lines: tuple[tuple[LatLon, ...], ...]

    def matches(self, road: RoadName, ignore_type: bool = False) -> bool:
        if self.key != road.key:
            return False
        if road.type and not ignore_type and self.type != road.type:
            return False
        if road.suffix and self.suffix != road.suffix:
            return False
        return True

    def near(self, point: LatLon, within_m: float) -> bool:
        return any(distance_m(point, p) <= within_m for line in self.lines for p in line[:: max(1, len(line) // 8)] + line[-1:])


def map_name(name: str | None) -> str:
    """Map names use hyphens in some places ("NORTH-SOUTH ROAD") and spaces in others; compare without."""
    return " ".join((name or "").upper().replace("-", " ").split())


def load_suburb_names(domains_csv: str) -> dict[int, str]:
    names: dict[int, str] = {}
    with open(domains_csv, newline="", encoding="utf-8-sig") as fh:
        for row in csv.reader(fh):
            if len(row) >= 4 and row[0] in ("SUBURBIDLEFT", "SUBURBIDRIGHT") and row[2].isdigit():
                names[int(row[2])] = row[3]
    return names


def load_segments(roads_geojson: str, suburb_names: dict[int, str], wanted_keys: set[str]) -> list[RoadSegment]:
    """Segments of roads whose road_key is wanted."""
    segments = []
    with open(roads_geojson, encoding="utf-8") as fh:
        for line in fh:
            m = _NAME.search(line)
            if not m or road_key(m.group(1)) not in wanted_keys:
                continue
            feature = json.loads(line.rstrip().rstrip(","))
            props, geom = feature["properties"], feature.get("geometry")
            if not geom or props.get("status") not in (None, "OPER"):
                continue
            parts = geom["coordinates"] if geom["type"] == "MultiLineString" else [geom["coordinates"]]
            lines = tuple(tuple((round(lat, 6), round(lon, 6)) for lon, lat, *_ in part) for part in parts if len(part) >= 2)
            if not lines:
                continue
            subs = frozenset(
                suburb_key(suburb_names[i])
                for i in (props.get("suburbidleft"), props.get("suburbidright"))
                if i in suburb_names
            )
            segments.append(RoadSegment(
                id=int(props.get("persistentid") or 0),
                name=map_name(props.get("name")),
                key=road_key(props.get("name") or ""),
                type=(props.get("roadtype") or "").strip() or None,
                suffix=(props.get("typesuffix") or "").strip() or None,
                road_class=props.get("class"),
                one_way=props.get("one_way"),
                suburbs=subs,
                lines=lines,
            ))
    return segments


def load_suburb_centroids(suburbs_geojson: str) -> dict[str, LatLon]:
    """Area-weighted centre of each suburb's largest polygon, keyed by suburb_key."""
    centroids: dict[str, LatLon] = {}
    with open(suburbs_geojson, encoding="utf-8") as fh:
        for line in fh:
            if '"Feature"' not in line:
                continue
            feature = json.loads(line.rstrip().rstrip(","))
            name = feature["properties"].get("suburb")
            geom = feature.get("geometry")
            if not name or not geom:
                continue
            polygons = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
            best = None
            for polygon in polygons:
                ring = polygon[0]
                area, cx, cy = 0.0, 0.0, 0.0
                for (x1, y1, *_), (x2, y2, *_) in zip(ring, ring[1:]):
                    cross = x1 * y2 - x2 * y1
                    area += cross
                    cx += (x1 + x2) * cross
                    cy += (y1 + y2) * cross
                if area == 0:
                    continue
                c = (cy / (3 * area), cx / (3 * area))
                if best is None or abs(area) > best[0]:
                    best = (abs(area), c)
            if best:
                centroids[suburb_key(name)] = best[1]
    return centroids


class RoadIndex:
    def __init__(self, segments: Iterable[RoadSegment]):
        self.by_key: dict[str, list[RoadSegment]] = {}
        for s in segments:
            self.by_key.setdefault(s.key, []).append(s)

    def find(self, road: RoadName) -> list[RoadSegment]:
        for candidate in (road, *alternatives(road)):
            segs = self.by_key.get(candidate.key, [])
            exact = [s for s in segs if s.matches(candidate)]
            found = exact or [s for s in segs if s.matches(candidate, ignore_type=True)]
            if found:
                return found
        return []


def alternatives(road: RoadName) -> list[RoadName]:
    """Other ways the map may hold a road: "THE PARADE" is a name with no type."""
    if road.type:
        return [RoadName(f"{road.name} {road.type}", None, road.suffix)]
    return []


def wanted_keys(road: RoadName) -> set[str]:
    return {road.key, *(r.key for r in alternatives(road))}

