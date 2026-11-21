import unittest
from datetime import datetime, timezone

from zonewatch_pipeline import dataset as ds
from zonewatch_pipeline.offences import read_sites_from_text
from zonewatch_pipeline.place import Placer
from zonewatch_pipeline.roadmap import RoadIndex

from .test_offences import HEADER, row
from .test_place import CENTROIDS, ROADS


def sample_sites():
    rows = [
        row("A", "1/07/2026", "Enter an intersection or marked foot crossing showing a red traffic light", "FIXED CAMERA", "51", "Main Rd and Cross Rd, Testville", " Testville", "60"),
        row("B", "9/07/2026", "Exceed speed limit by less than 10 kph", "FIXED CAMERA", "52", "Main Rd and Cross Rd, Testville", " Testville", "60"),
        row("C", "2/07/2026", "Use mobile phone while driving", "FIXED CAMERA", "1011", "Lane 1, Main Rd, Testville", " Testville"),
        row("D", "2/07/2026", "Use mobile phone while driving", "FIXED CAMERA", "1012", "Lane 2, Main Rd, Testville", " Testville"),
        row("E", "3/07/2026", "EXCEED SPEED LIMIT", "MOBILE CAMERA", "77", "MAIN RD", "TESTVILLE", "60"),
        row("F", "3/07/2026", "Be the owner of uninsured motor vehicle driven or found standing on a road", "FIXED CAMERA", "406", "Main Rd, Testville", " Testville"),
        row("G", "3/07/2026", "Exceed speed limit by less than 10 kph", "FIXED CAMERA", "99", "Nowhere Rd, Testville", " Testville", "50"),
    ]
    return read_sites_from_text(HEADER + "".join(rows))


class MergeTests(unittest.TestCase):
    def zone(self, sid, suburb, lat0, lat1, limit=60):
        return {
            "id": sid, "type": "mobileSpeed", "road": "Main Road", "suburb": suburb, "speedLimitKmh": limit,
            "lastSeen": "2026-07-01", "notices": 2, "paths": [[[lat0, 138.6], [lat1, 138.6]]], "oneWay": False, "lengthM": 0,
        }

    def test_joins_mobile_zones_that_continue_along_a_road(self):
        report = ds.BuildReport()
        zones = [
            self.zone("sa-m-10", "A", -34.90, -34.91),
            self.zone("sa-m-2", "B", -34.91, -34.92, limit=80),
            self.zone("sa-m-30", "C", -34.95, -34.96),  # 3 km away: its own zone
            dict(self.zone("sa-f-5", "A", -34.90, -34.91), type="fixedSpeed"),
        ]
        merged = {z["id"]: z for z in ds.merge_mobile_runs(zones, report)}
        self.assertEqual(sorted(merged), ["sa-f-5", "sa-m-2", "sa-m-30"])
        run = merged["sa-m-2"]
        self.assertEqual(run["paths"], [[[-34.92, 138.6], [-34.9, 138.6]]] if run["paths"][0][0][0] == -34.92 else [[[-34.9, 138.6], [-34.92, 138.6]]])
        self.assertEqual(run["suburb"], "B and 1 more suburbs")
        self.assertIsNone(run["speedLimitKmh"])
        self.assertEqual(run["notices"], 4)
        self.assertAlmostEqual(run["lengthM"], 2224, delta=5)


class BuildTests(unittest.TestCase):
    def setUp(self):
        when = datetime(2026, 11, 22, 3, 0, tzinfo=timezone.utc)
        self.dataset, self.report = ds.build(sample_sites(), Placer(RoadIndex(ROADS), CENTROIDS), when)

    def test_entries(self):
        self.assertEqual([c["id"] for c in self.dataset["cameras"]], ["sa-f-51"])
        camera = self.dataset["cameras"][0]
        self.assertEqual(camera["type"], "redLightSpeed")
        self.assertEqual(camera["road"], "Main Road & Cross Road")
        self.assertEqual(camera["suburb"], "Testville")
        self.assertIsNone(camera["heading"])
        self.assertEqual(camera["lastSeen"], "2026-07-09")
        self.assertEqual({z["id"]: z["type"] for z in self.dataset["zones"]}, {"sa-f-1011": "phoneCamera", "sa-m-77": "mobileSpeed"})
        self.assertEqual(self.dataset["version"], 20261122)
        self.assertEqual(self.dataset["dataThrough"], "2026-07-09")

    def test_report(self):
        self.assertIn((["sa-f-1011", "sa-f-1012"], "Lane 1, Main Rd, Testville"), self.report.merged)
        self.assertIn((["sa-f-51", "sa-f-52"], "Main Rd and Cross Rd, Testville"), self.report.merged)
        self.assertEqual(self.report.skipped, [("sa-f-406", "Main Rd, Testville")])
        self.assertEqual([u[0] for u in self.report.unplaced], ["sa-f-99"])

    def test_validation_catches_problems(self):
        ds.validate(self.dataset, min_fixed=1)
        bad = dict(self.dataset, cameras=[dict(self.dataset["cameras"][0], lat=-20.0)])
        with self.assertRaisesRegex(ds.ValidationError, "outside South Australia"):
            ds.validate(bad, min_fixed=1)
        with self.assertRaisesRegex(ds.ValidationError, "dropped"):
            ds.validate(self.dataset, previous={"cameras": [{}] * 10, "zones": []}, min_fixed=1)

    def test_sign_and_verify(self):
        pem, public = ds.generate_key()
        data = ds.encode(self.dataset)
        signature = ds.sign(data, pem)
        self.assertTrue(ds.verify(data, signature, public))
        self.assertFalse(ds.verify(data + b" ", signature, public))

    def test_content_hash_ignores_build_time(self):
        later = dict(self.dataset, generatedAt="2026-11-23T03:00:00Z", version=20261123)
        self.assertEqual(ds.content_hash(self.dataset), ds.content_hash(later))


if __name__ == "__main__":
    unittest.main()
