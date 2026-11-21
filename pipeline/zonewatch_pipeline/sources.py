"""Downloads the open government data the dataset is built from, with a local cache.

Only government sources are used (see CLAUDE.md): data.sa.gov.au for camera offence reports and
the Location SA data portal for the road and suburb maps.
"""

from __future__ import annotations

import json
import os
import shutil
import time
import urllib.request
import zipfile
from pathlib import Path

USER_AGENT = "ZoneWatch-pipeline/1.0 (+https://github.com/sfernando0825/ZoneWatch)"
CKAN_PACKAGE = "https://data.sa.gov.au/data/api/3/action/package_show?id=expiation-notice-system-data"
ROADS_ZIP = "https://www.dptiapps.com.au/dataportal/Roads_geojson.zip"
SUBURBS_ZIP = "https://www.dptiapps.com.au/dataportal/Suburbs_geojson.zip"

ATTRIBUTION = [
    "Camera sites: Expiation Notice System data, South Australia Police, data.sa.gov.au, CC BY",
    "Roads and suburbs: Location SA, Department for Infrastructure and Transport, CC BY 3.0 AU",
]


def download(url: str, dest: Path, max_age_s: float | None = None) -> Path:
    if dest.exists() and (max_age_s is None or time.time() - dest.stat().st_mtime < max_age_s):
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=300) as response, open(tmp, "wb") as out:
        shutil.copyfileobj(response, out)
    os.replace(tmp, dest)
    return dest


def offence_report_urls(cache: Path, years: int = 2) -> list[tuple[str, str]]:
    """(name, url) of the newest `years` yearly Camera Offence Reports, newest first."""
    package = download(CKAN_PACKAGE, cache / "ckan-package.json", max_age_s=6 * 3600)
    resources = json.loads(package.read_text())["result"]["resources"]
    reports = [
        (r["name"], r["url"])
        for r in resources
        if "camera offence report" in r["name"].lower() and r["url"].lower().endswith(".zip")
    ]
    reports.sort(key=lambda r: r[0], reverse=True)
    return reports[:years]


def extract(zip_path: Path, member_suffix: str, dest_dir: Path) -> Path:
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.lower().endswith(member_suffix.lower()) and not n.startswith("__MACOSX")]
        if not names:
            raise FileNotFoundError(f"no *{member_suffix} in {zip_path.name}")
        name = names[0]
        target = dest_dir / Path(name).name
        if not target.exists() or target.stat().st_mtime < zip_path.stat().st_mtime:
            dest_dir.mkdir(parents=True, exist_ok=True)
            with z.open(name) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
        return target


def fetch_all(cache: Path, map_max_age_days: float = 30) -> dict:
    """Downloads (or reuses) everything and returns local paths."""
    reports = []
    for name, url in offence_report_urls(cache):
        zip_path = download(url, cache / "offences" / Path(url).name, max_age_s=20 * 3600)
        reports.append(extract(zip_path, ".csv", cache / "offences" / zip_path.stem))
    map_age = map_max_age_days * 86400
    roads_zip = download(ROADS_ZIP, cache / "maps" / "Roads_geojson.zip", max_age_s=map_age)
    suburbs_zip = download(SUBURBS_ZIP, cache / "maps" / "Suburbs_geojson.zip", max_age_s=map_age)
    return {
        "offence_reports": reports,
        "roads": extract(roads_zip, "Roads_GDA2020.geojson", cache / "maps" / "roads"),
        "road_domains": extract(roads_zip, "Road_Domains.csv", cache / "maps" / "roads"),
        "suburbs": extract(suburbs_zip, "Suburbs_GDA2020.geojson", cache / "maps" / "suburbs"),
    }
