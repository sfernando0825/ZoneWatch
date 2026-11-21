"""Places camera sites on the road map without any manual help.

- Two roads ("Greenhill Rd and Hutt Rd, Adelaide"): a point where the roads meet, nearest the suburb.
- One road in a suburb ("Prospect Rd, Prospect", mobile sites, phone cameras): a zone covering that
  road within the suburb, because the report doesn't say where along the road the camera stands.
- One road between two places ("Dukes Hwy, Ki Ki to Coonalpyn"): an average speed section from the
  first place to the second, enforced in that direction.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Union

from .geometry import LatLon, Projection, distance_m, length_m, segment_closest_points, shortest_path, simplify, stitch
from .names import Location, RoadName, suburb_key
from .roadmap import RoadIndex, RoadSegment

MEET_TOLERANCE_M = 15.0
"""Roads count as meeting where their lines come this close."""
JUNCTION_CLUSTER_M = 80.0
"""Meeting points this close to the chosen one belong to the same junction (divided roads meet 2-4 times)."""
MAX_FROM_SUBURB_M = 6_000.0
"""How far from the suburb's centre an intersection may be."""
SIMPLIFY_M = 4.0
MAX_ZONE_M = 25_000.0
"""A zone longer than this means the road match went wrong."""
MAX_SECTION_M = 200_000.0
SECTION_GAP_M = 1_000.0
MAX_DETOUR = 1.5
"""A section route longer than this times the straight line (plus 2 km) has gone the wrong way."""
"""Highway pieces in the map can stop short at interchanges; gaps up to this are bridged."""


@dataclass(frozen=True)
class PointPlacement:
    point: LatLon


@dataclass(frozen=True)
class ZonePlacement:
    paths: tuple[tuple[LatLon, ...], ...]
    one_way: bool
    """True when the zone is enforced only in the direction its single path is drawn."""

    @property
    def length_m(self) -> float:
        return sum(length_m(p) for p in self.paths)


@dataclass(frozen=True)
class Unplaced:
    reason: str


Placement = Union[PointPlacement, ZonePlacement, Unplaced]


class Placer:
    def __init__(self, roads: RoadIndex, suburb_centroids: dict[str, LatLon]):
        self.roads = roads
        self.centroids = suburb_centroids

    def place(self, location: Location) -> Placement:
        if location.is_intersection:
            return self.intersection(location.roads[0], location.roads[1], location.suburbs[0] if location.suburbs else "")
        if len(location.roads) != 1:
            return Unplaced(f"expected one or two roads, got {len(location.roads)}")
        if location.is_between_places:
            return self.section(location.roads[0], location.suburbs[0], location.suburbs[1])
        if not location.suburbs:
            return Unplaced("no suburb given")
        return self.zone(location.roads[0], location.suburbs[0])

    def _centre(self, suburb: str, segments: list[RoadSegment]) -> LatLon | None:
        key = suburb_key(suburb)
        if key in self.centroids:
            return self.centroids[key]
        inside = [p for s in segments if key in s.suburbs for line in s.lines for p in line]
        if inside:
            return (sum(p[0] for p in inside) / len(inside), sum(p[1] for p in inside) / len(inside))
        return None

    def intersection(self, a: RoadName, b: RoadName, suburb: str) -> Placement:
        segs_a, segs_b = self.roads.find(a), self.roads.find(b)
        if not segs_a:
            return Unplaced(f"road not on map: {a}")
        if not segs_b:
            return Unplaced(f"road not on map: {b}")
        centre = self._centre(suburb, segs_a + segs_b)
        if centre is None:
            return Unplaced(f"suburb not on map: {suburb}")
        near_a = [s for s in segs_a if s.near(centre, MAX_FROM_SUBURB_M + 2_000)]
        near_b = [s for s in segs_b if s.near(centre, MAX_FROM_SUBURB_M + 2_000)]
        proj = Projection(centre)
        lines_a = [[proj.xy(p) for p in line] for s in near_a for line in s.lines]
        lines_b = [[proj.xy(p) for p in line] for s in near_b for line in s.lines]
        meets: list[tuple[float, float]] = []
        for la in lines_a:
            box_a = _box(la, MEET_TOLERANCE_M)
            for lb in lines_b:
                if not _overlap(box_a, _box(lb, 0)):
                    continue
                for a1, a2 in zip(la, la[1:]):
                    for b1, b2 in zip(lb, lb[1:]):
                        p, q, d = segment_closest_points(a1, a2, b1, b2)
                        if d <= MEET_TOLERANCE_M:
                            meets.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2))
        if not meets:
            return Unplaced(f"{a} and {b} don't meet near {suburb}")
        best = min(meets, key=lambda m: m[0] ** 2 + m[1] ** 2)
        if (best[0] ** 2 + best[1] ** 2) ** 0.5 > MAX_FROM_SUBURB_M:
            return Unplaced(f"{a} and {b} meet too far from {suburb}")
        cluster = [m for m in meets if ((m[0] - best[0]) ** 2 + (m[1] - best[1]) ** 2) ** 0.5 <= JUNCTION_CLUSTER_M]
        x = sum(m[0] for m in cluster) / len(cluster)
        y = sum(m[1] for m in cluster) / len(cluster)
        lat, lon = proj.latlon(x, y)
        return PointPlacement((round(lat, 6), round(lon, 6)))

    def zone(self, road: RoadName, suburb: str) -> Placement:
        segs = self.roads.find(road)
        if not segs:
            return Unplaced(f"road not on map: {road}")
        key = suburb_key(suburb)
        inside = [s for s in segs if key in s.suburbs]
        if not inside:
            centre = self._centre(suburb, segs)
            if centre is None:
                return Unplaced(f"suburb not on map: {suburb}")
            inside = [s for s in segs if s.near(centre, 1_500)]
            if not inside:
                return Unplaced(f"{road} not in or near {suburb}")
        paths = tuple(tuple(simplify(p, SIMPLIFY_M)) for p in stitch(line for s in inside for line in s.lines))
        placement = ZonePlacement(paths, one_way=False)
        if placement.length_m > MAX_ZONE_M:
            return Unplaced(f"{road} in {suburb} is {placement.length_m / 1000:.0f} km long")
        return placement

    def section(self, road: RoadName, start: str, end: str) -> Placement:
        segs = self.roads.find(road)
        if not segs:
            return Unplaced(f"road not on map: {road}")
        anchors = []
        for suburb in (start, end):
            key = suburb_key(suburb)
            points = [p for s in segs if key in s.suburbs for line in s.lines for p in line]
            if points:
                mean = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
                anchors.append(min(points, key=lambda p: distance_m(p, mean)))
            elif key in self.centroids:
                anchors.append(self.centroids[key])
            else:
                return Unplaced(f"suburb not on map: {suburb}")
        lines = [(line, s.one_way) for s in segs for line in s.lines]
        path = shortest_path(
            [l for l, _ in lines], anchors[0], anchors[1], snap_m=SECTION_GAP_M, one_way=[w for _, w in lines]
        )
        if not path or len(path) < 2:
            return Unplaced(f"no route along {road} from {start} to {end}")
        straight = distance_m(path[0], path[-1])
        if length_m(path) > straight * MAX_DETOUR + 2_000:
            return Unplaced(f"route along {road} from {start} to {end} wanders ({length_m(path) / 1000:.0f} km)")
        placement = ZonePlacement((tuple(simplify(path, SIMPLIFY_M)),), one_way=True)
        if not 500 <= placement.length_m <= MAX_SECTION_M:
            return Unplaced(f"section along {road} is {placement.length_m / 1000:.1f} km")
        return placement


def _box(line, pad):
    xs = [p[0] for p in line]
    ys = [p[1] for p in line]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def _overlap(a, b) -> bool:
    return a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]
