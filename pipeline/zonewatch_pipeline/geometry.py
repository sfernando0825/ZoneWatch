"""Small planar geometry helpers. Points are (lat, lon) in degrees; maths happens in local metres."""

from __future__ import annotations

import heapq
import math
from typing import Iterable, Sequence

LatLon = tuple[float, float]
EARTH_RADIUS_M = 6_371_000.0


def distance_m(a: LatLon, b: LatLon) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(h)))


class Projection:
    """Equirectangular projection around a reference point; accurate to well under 1% within tens of km."""

    def __init__(self, origin: LatLon):
        self.lat0, self.lon0 = origin
        self.kx = math.cos(math.radians(self.lat0)) * math.pi / 180 * EARTH_RADIUS_M
        self.ky = math.pi / 180 * EARTH_RADIUS_M

    def xy(self, p: LatLon) -> tuple[float, float]:
        return ((p[1] - self.lon0) * self.kx, (p[0] - self.lat0) * self.ky)

    def latlon(self, x: float, y: float) -> LatLon:
        return (self.lat0 + y / self.ky, self.lon0 + x / self.kx)


def _closest_on_segment(p, a, b):
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / length2))
    return (ax + t * dx, ay + t * dy)


def _dist(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def segment_closest_points(a1, a2, b1, b2):
    """Closest pair of points between segments a1-a2 and b1-b2 (planar), and their distance."""
    # Proper crossing first.
    d1 = (a2[0] - a1[0], a2[1] - a1[1])
    d2 = (b2[0] - b1[0], b2[1] - b1[1])
    denom = d1[0] * d2[1] - d1[1] * d2[0]
    if denom != 0:
        t = ((b1[0] - a1[0]) * d2[1] - (b1[1] - a1[1]) * d2[0]) / denom
        u = ((b1[0] - a1[0]) * d1[1] - (b1[1] - a1[1]) * d1[0]) / denom
        if 0 <= t <= 1 and 0 <= u <= 1:
            p = (a1[0] + t * d1[0], a1[1] + t * d1[1])
            return p, p, 0.0
    best = None
    for p, q in (
        (a1, _closest_on_segment(a1, b1, b2)),
        (a2, _closest_on_segment(a2, b1, b2)),
        (_closest_on_segment(b1, a1, a2), b1),
        (_closest_on_segment(b2, a1, a2), b2),
    ):
        d = _dist(p, q)
        if best is None or d < best[2]:
            best = (p, q, d)
    return best


def polyline_distance_m(point: LatLon, line: Sequence[LatLon]) -> float:
    proj = Projection(point)
    p = (0.0, 0.0)
    xy = [proj.xy(q) for q in line]
    if len(xy) == 1:
        return _dist(p, xy[0])
    return min(_dist(p, _closest_on_segment(p, a, b)) for a, b in zip(xy, xy[1:]))


def length_m(line: Sequence[LatLon]) -> float:
    return sum(distance_m(a, b) for a, b in zip(line, line[1:]))


def bearing_deg(a: LatLon, b: LatLon) -> float:
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlon = math.radians(b[1] - a[1])
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def simplify(line: Sequence[LatLon], tolerance_m: float) -> list[LatLon]:
    """Douglas-Peucker in local metres; keeps both ends."""
    if len(line) < 3:
        return list(line)
    proj = Projection(line[0])
    xy = [proj.xy(p) for p in line]
    keep = [False] * len(line)
    keep[0] = keep[-1] = True
    stack = [(0, len(line) - 1)]
    while stack:
        i, j = stack.pop()
        far, far_d = None, tolerance_m
        for k in range(i + 1, j):
            d = _dist(xy[k], _closest_on_segment(xy[k], xy[i], xy[j]))
            if d > far_d:
                far, far_d = k, d
        if far is not None:
            keep[far] = True
            stack += [(i, far), (far, j)]
    return [p for p, k in zip(line, keep) if k]


def _key(p: LatLon) -> tuple[int, int]:
    return (round(p[0] * 1e6), round(p[1] * 1e6))


def stitch(lines: Iterable[Sequence[LatLon]]) -> list[list[LatLon]]:
    """Joins lines that share end points into longer paths. Direction of travel is not preserved."""
    pending = [list(l) for l in lines if len(l) >= 2]
    paths: list[list[LatLon]] = []
    while pending:
        path = pending.pop()
        grew = True
        while grew:
            grew = False
            for i, line in enumerate(pending):
                if _key(line[0]) == _key(path[-1]):
                    path += line[1:]
                elif _key(line[-1]) == _key(path[-1]):
                    path += line[-2::-1]
                elif _key(line[-1]) == _key(path[0]):
                    path = line[:-1] + path
                elif _key(line[0]) == _key(path[0]):
                    path = line[:0:-1] + path
                else:
                    continue
                pending.pop(i)
                grew = True
                break
        paths.append(path)
    return paths


def shortest_path(
    lines: Iterable[Sequence[LatLon]],
    start: LatLon,
    end: LatLon,
    snap_m: float = 40.0,
    one_way: Sequence[str | None] | None = None,
    reach_m: float = 150.0,
) -> list[LatLon] | None:
    """Shortest route along the given lines from near start to near end.

    one_way, one entry per line, follows the map: "FT" travel in drawing order only, "TF" against
    it, anything else both ways. The route may begin at any vertex within reach_m of start and stop
    at any within reach_m of end, so on a divided road it picks the carriageway going the right way.

    Map pieces of one road don't always share an exact end point (interchanges, bridges), so where
    a route would dead-end, it may jump up to snap_m to a vertex that carries on the same way.
    """
    graph: dict[tuple[int, int], list[tuple[tuple[int, int], float]]] = {}
    coords: dict[tuple[int, int], LatLon] = {}
    for i, line in enumerate(lines):
        direction = one_way[i] if one_way is not None else None
        for a, b in zip(line, line[1:]):
            ka, kb = _key(a), _key(b)
            if ka == kb:
                continue
            coords[ka], coords[kb] = a, b
            w = distance_m(a, b)
            graph.setdefault(ka, [])
            graph.setdefault(kb, [])
            if direction != "TF":
                graph[ka].append((kb, w))
            if direction != "FT":
                graph[kb].append((ka, w))
    if not coords:
        return None
    _bridge_gaps(graph, coords, snap_m)

    def near(point):
        found = [k for k, p in coords.items() if distance_m(p, point) <= reach_m]
        return found or [min(coords, key=lambda k: distance_m(coords[k], point))]

    sources, targets = near(start), set(near(end))
    best = {k: 0.0 for k in sources}
    previous: dict[tuple[int, int], tuple[int, int]] = {}
    queue = [(0.0, k) for k in sources]
    heapq.heapify(queue)
    reached = None
    while queue:
        d, node = heapq.heappop(queue)
        if d > best.get(node, math.inf):
            continue
        if node in targets:
            reached = node
            break
        for nxt, w in graph[node]:
            nd = d + w
            if nd < best.get(nxt, math.inf):
                best[nxt] = nd
                previous[nxt] = node
                heapq.heappush(queue, (nd, nxt))
    if reached is None:
        return None
    path = [reached]
    while path[-1] in previous:
        path.append(previous[path[-1]])
    return [coords[k] for k in reversed(path)]


def _bridge_gaps(graph, coords, snap_m: float) -> None:
    """Adds a jump from each dead end to the nearest vertex within snap_m that continues the same way."""
    cell = snap_m / 111_000 * 2
    grid: dict[tuple[int, int], list] = {}
    for k, p in coords.items():
        grid.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append(k)
    incoming: dict[tuple[int, int], list] = {}
    for a, edges in graph.items():
        for b, _ in edges:
            incoming.setdefault(b, []).append(a)
    additions = []
    for node, sources in incoming.items():
        for prev in sources:
            onward = [n for n, _ in graph[node] if n != prev]
            if onward:
                continue
            heading = bearing_deg(coords[prev], coords[node])
            p = coords[node]
            gx, gy = int(p[0] // cell), int(p[1] // cell)
            best = None
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for other in grid.get((gx + dx, gy + dy), []):
                        if other in (node, prev):
                            continue
                        d = distance_m(p, coords[other])
                        if d > snap_m or (best is not None and d >= best[1]):
                            continue
                        if d > 1 and _turn(heading, bearing_deg(p, coords[other])) > 60:
                            continue
                        if not any(_turn(heading, bearing_deg(coords[other], coords[n])) <= 60 for n, _ in graph[other]):
                            continue
                        best = (other, d)
            if best:
                additions.append((node, best))
    for node, edge in additions:
        graph[node].append(edge)


def _turn(a: float, b: float) -> float:
    return abs((a - b + 180) % 360 - 180)
