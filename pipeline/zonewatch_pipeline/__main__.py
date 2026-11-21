"""Command line: python -m zonewatch_pipeline <command>

  build   Download sources (cached), place cameras, validate, write and optionally sign the dataset.
  keygen  Make a new Ed25519 signing key. The private key never goes in the repository.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from . import dataset as ds
from .offences import read_sites_from_paths
from .place import Placer
from .roadmap import RoadIndex, load_segments, load_suburb_centroids, load_suburb_names, wanted_keys
from .sources import fetch_all


def cmd_build(args) -> int:
    started = time.time()
    cache = Path(args.cache)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    paths = fetch_all(cache)
    print(f"sources ready ({time.time() - started:.0f}s): {[p.name for p in paths['offence_reports']]}")

    sites = read_sites_from_paths(str(p) for p in paths["offence_reports"])
    wanted = {k for s in sites.values() if s.camera_type and s.location for r in s.location.roads for k in wanted_keys(r)}
    segments = load_segments(str(paths["roads"]), load_suburb_names(str(paths["road_domains"])), wanted)
    placer = Placer(RoadIndex(segments), load_suburb_centroids(str(paths["suburbs"])))
    print(f"{len(sites)} sites, {len(segments)} road segments ({time.time() - started:.0f}s)")

    dataset, report = ds.build(sites, placer)
    (out / "build-report.md").write_text(report.markdown())
    previous = json.loads(Path(args.previous).read_text()) if args.previous and Path(args.previous).exists() else None
    ds.validate(dataset, report, previous)

    data = ds.encode(dataset)
    target = out / f"{args.name}.json"
    target.write_bytes(data)
    (out / f"{args.name}.sha256").write_text(ds.content_hash(dataset) + "\n")
    key_pem = os.environ.get("ZW_SIGNING_KEY", "").encode() or (Path(args.key).read_bytes() if args.key else b"")
    if key_pem:
        (out / f"{args.name}.json.sig").write_text(ds.sign(data, key_pem) + "\n")
        print("signed")
    else:
        print("not signed: no key given")
    print(
        f"wrote {target} ({len(data) / 1024:.0f} KB): {len(dataset['cameras'])} cameras, "
        f"{len(dataset['zones'])} zones, {len(report.unplaced)} not placed, data through {dataset['dataThrough']} "
        f"({time.time() - started:.0f}s)"
    )
    return 0


def cmd_keygen(args) -> int:
    target = Path(args.out).expanduser()
    if target.exists():
        print(f"{target} already exists; not overwriting", file=sys.stderr)
        return 1
    target.parent.mkdir(parents=True, exist_ok=True)
    pem, public = ds.generate_key()
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as fh:
        fh.write(pem)
    print(f"private key: {target}")
    print(f"public key (base64, goes in the app): {public}")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="zonewatch_pipeline")
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("--cache", default=".cache")
    b.add_argument("--out", default="build")
    b.add_argument("--name", default="sa-cameras")
    b.add_argument("--key", help="Ed25519 private key PEM file (or set ZW_SIGNING_KEY)")
    b.add_argument("--previous", help="previous dataset, to catch a big drop in entries")
    b.set_defaults(func=cmd_build)
    k = sub.add_parser("keygen")
    k.add_argument("--out", required=True)
    k.set_defaults(func=cmd_keygen)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
