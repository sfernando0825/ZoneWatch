"""Turns SAPOL location descriptions into road names and suburbs that match the SA Roads map.

Examples of what SAPOL writes:
    "Greenhill Rd and Hutt Rd, Adelaide"     two roads meeting at an intersection
    "KENSINGTON RD & PORTRUSH RD"            two roads, suburb in a separate column
    "Prospect Rd, Prospect"                  one road within a suburb
    "Lane 1, North-South Motorway, Regency Park"
    "Sturt Hwy, Lowbank to Wigley Flat"      an average speed section between two places
    "Commercial St East and Crouch St North, Mount Gambier"
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# Abbreviation -> road type as written in the SA Roads map ("roadtype" field).
ROAD_TYPES = {
    "RD": "ROAD", "ROAD": "ROAD",
    "ST": "STREET", "STREET": "STREET",
    "AVE": "AVENUE", "AV": "AVENUE", "AVENUE": "AVENUE",
    "TCE": "TERRACE", "TERRACE": "TERRACE",
    "HWY": "HIGHWAY", "HIGHWAY": "HIGHWAY",
    "DR": "DRIVE", "DRV": "DRIVE", "DRIVE": "DRIVE",
    "BVD": "BOULEVARD", "BLVD": "BOULEVARD", "BOULEVARD": "BOULEVARD",
    "PDE": "PARADE", "PARADE": "PARADE",
    "CRES": "CRESCENT", "CR": "CRESCENT", "CRESCENT": "CRESCENT",
    "CT": "COURT", "COURT": "COURT",
    "PL": "PLACE", "PLACE": "PLACE",
    "LN": "LANE", "LANE": "LANE",
    "WAY": "WAY",
    "EXP": "EXPRESSWAY", "EXPWY": "EXPRESSWAY", "EXPRESSWAY": "EXPRESSWAY",
    "FWY": "FREEWAY", "FREEWAY": "FREEWAY",
    "MWY": "MOTORWAY", "MOTORWAY": "MOTORWAY",
    "GR": "GROVE", "GROVE": "GROVE",
    "CL": "CLOSE", "CLOSE": "CLOSE",
    "CCT": "CIRCUIT", "CIRCUIT": "CIRCUIT",
    "SQ": "SQUARE", "SQUARE": "SQUARE",
    "PKWY": "PARKWAY", "PARKWAY": "PARKWAY",
    "ESP": "ESPLANADE", "ESPLANADE": "ESPLANADE",
    "WALK": "WALK",
    "PKY": "PARKWAY",
    "CAUSEWAY": "CAUSEWAY",
}

# Words after the road type, as in the map's "typesuffix" field.
SUFFIXES = {"NORTH", "SOUTH", "EAST", "WEST", "EXTENSION"}

# Abbreviations inside a road's or suburb's name.
NAME_WORDS = {"LWR": "LOWER", "UPR": "UPPER", "NTH": "NORTH", "STH": "SOUTH", "MT": "MOUNT", "PT": "PORT", "GRND": "GRAND"}

# Whole names SAPOL shortens in ways the word table can't undo.
NAME_ALIASES = {"SE": "SOUTH EASTERN"}


@dataclass(frozen=True)
class RoadName:
    name: str
    """The road's name without its type, e.g. "PORTRUSH". Hyphens become spaces, as in the map."""
    type: str | None = None
    """The road type, e.g. "ROAD", or None when the description gives none."""
    suffix: str | None = None
    """"EAST" in "Commercial St East"."""

    def __str__(self) -> str:
        return " ".join(p for p in (self.name, self.type, self.suffix) if p)

    @property
    def key(self) -> str:
        return road_key(self.name)

    def display(self) -> str:
        """Title case for the app, e.g. "Portrush Road"."""
        return " ".join(w.capitalize() if not w.startswith("O'") else "O'" + w[2:].capitalize() for w in str(self).split())


@dataclass(frozen=True)
class Location:
    roads: tuple[RoadName, ...]
    suburbs: tuple[str, ...]
    lane: int | None = None

    @property
    def is_intersection(self) -> bool:
        return len(self.roads) == 2

    @property
    def is_between_places(self) -> bool:
        return len(self.suburbs) == 2


def _words(text: str) -> list[str]:
    text = text.upper().replace("’", "'").replace("-", " ")
    return re.sub(r"[^A-Z0-9' ]", " ", text).split()


def parse_road(text: str) -> RoadName | None:
    words = _words(text)
    if not words:
        return None
    suffix = None
    if len(words) > 2 and words[-1] in SUFFIXES and words[-2] in ROAD_TYPES:
        suffix = words[-1]
        words = words[:-1]
    road_type = None
    if len(words) > 1 and words[-1] in ROAD_TYPES:
        road_type = ROAD_TYPES[words[-1]]
        words = words[:-1]
    name = " ".join(NAME_WORDS.get(w, w) for w in words)
    return RoadName(NAME_ALIASES.get(name, name), road_type, suffix)


def parse_location(description: str, suburb_column: str = "") -> Location | None:
    text = description.strip()
    lane = None
    lane_match = re.match(r"^\s*LANE\s+(\d+)\s*,\s*", text, flags=re.IGNORECASE)
    if lane_match:
        lane = int(lane_match.group(1))
        text = text[lane_match.end():]

    parts = [p.strip() for p in text.split(",") if p.strip()]
    if not parts:
        return None
    road_part = parts[0]
    suburb_part = parts[-1] if len(parts) > 1 else suburb_column

    pieces = re.split(r"\s+(?:AND|&)\s+", road_part, flags=re.IGNORECASE)
    roads = tuple(r for r in (parse_road(x) for x in pieces) if r)
    suburbs = tuple(
        normalise_suburb(s) for s in re.split(r"\s+TO\s+", suburb_part or "", flags=re.IGNORECASE) if s.strip()
    )
    if not roads:
        return None
    return Location(roads=roads, suburbs=suburbs, lane=lane)


def normalise_suburb(text: str) -> str:
    return " ".join(NAME_WORDS.get(w, w) for w in _words(text))


def _loose(words: list[str]) -> list[str]:
    return ["ST" if w == "SAINT" else w.replace("'", "") for w in words]


def road_key(name: str) -> str:
    """Compares road names loosely, the way SAPOL and the map differ:
    "SAINT KILDA" = "ST KILDA", "O'SULLIVAN" = "OSULLIVAN", "ALDGATE TO STRATHALBYN" = "ALDGATE-STRATHALBYN"."""
    return " ".join(w for w in _loose(_words(name)) if w != "TO")


def suburb_key(text: str) -> str:
    """Compares suburbs loosely: "KiKi" = "Ki Ki", "Saint Marys" = "St Marys", "OHalloran" = "O'Halloran"."""
    return "".join(_loose(normalise_suburb(text).split()))


def title(text: str) -> str:
    return " ".join("Mc" + w[2:].capitalize() if w.startswith("MC") and len(w) > 3 else w.capitalize() for w in text.split())
