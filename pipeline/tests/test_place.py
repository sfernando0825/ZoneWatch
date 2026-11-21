import unittest

from zonewatch_pipeline.geometry import distance_m, length_m, shortest_path, simplify, stitch
from zonewatch_pipeline.names import RoadName, parse_location, road_key
from zonewatch_pipeline.place import Placer, PointPlacement, Unplaced, ZonePlacement
from zonewatch_pipeline.roadmap import RoadIndex, RoadSegment

# A made-up grid near Adelaide: Main Rd runs north-south, Cross Rd east-west, meeting at ORIGIN.
ORIGIN = (-34.9, 138.6)
DLAT = 0.001  # about 111 m
DLON = 0.0012  # about 110 m at this latitude


def seg(i, name, rtype, points, suburbs=("TESTVILLE",), one_way="2W"):
    return RoadSegment(i, name, road_key(name), rtype, None, "ART", one_way, frozenset(suburbs), (tuple(points),))


def main_rd(n0, n1, suburbs=("TESTVILLE",)):
    return seg(100 + n0, "MAIN", "ROAD", [(ORIGIN[0] + k * DLAT, ORIGIN[1]) for k in range(n0, n1 + 1)], suburbs)


ROADS = [
    main_rd(-10, 0),
    main_rd(0, 10),
    main_rd(10, 30, suburbs=("OTHERTON",)),
    seg(1, "CROSS", "ROAD", [(ORIGIN[0], ORIGIN[1] + k * DLON) for k in range(-10, 11)]),
    seg(2, "CROSS", "STREET", [(ORIGIN[0] + 0.05, ORIGIN[1] + k * DLON) for k in range(-10, 11)]),
    seg(3, "THE PARADE", None, [(ORIGIN[0] - 0.003, ORIGIN[1] + k * DLON) for k in range(-10, 11)]),
    seg(4, "ST KILDA", "ROAD", [(ORIGIN[0] + 0.003, ORIGIN[1] + k * DLON) for k in range(-10, 11)], suburbs=("OHALLORANHILL",)),
]
CENTROIDS = {"TESTVILLE": (ORIGIN[0] + 0.002, ORIGIN[1] + 0.002), "OTHERTON": (ORIGIN[0] + 0.02, ORIGIN[1])}


class PlacerTests(unittest.TestCase):
    def setUp(self):
        self.placer = Placer(RoadIndex(ROADS), CENTROIDS)

    def test_intersection_is_where_the_roads_meet(self):
        result = self.placer.place(parse_location("Main Rd and Cross Rd, Testville"))
        self.assertIsInstance(result, PointPlacement)
        self.assertLess(distance_m(result.point, ORIGIN), 2)

    def test_intersection_needs_the_right_road_type(self):
        result = self.placer.place(parse_location("Main Rd and Cross St, Testville"))
        self.assertIsInstance(result, Unplaced)

    def test_unknown_road(self):
        result = self.placer.place(parse_location("Nowhere Rd and Cross Rd, Testville"))
        self.assertEqual(result, Unplaced("road not on map: NOWHERE ROAD"))

    def test_map_spellings(self):
        self.assertIsInstance(self.placer.place(parse_location("THE PARADE", "TESTVILLE")), ZonePlacement)
        self.assertIsInstance(self.placer.place(parse_location("SAINT KILDA RD", "OHALLORAN HILL")), ZonePlacement)

    def test_zone_covers_the_road_inside_the_suburb(self):
        result = self.placer.place(parse_location("Main Rd, Testville"))
        self.assertIsInstance(result, ZonePlacement)
        self.assertEqual(len(result.paths), 1)  # the two Testville pieces join up
        self.assertAlmostEqual(result.length_m, 20 * 111.2, delta=30)
        self.assertFalse(result.one_way)

    def test_section_runs_from_first_place_to_second(self):
        result = self.placer.place(parse_location("Main Rd, Testville to Otherton"))
        self.assertIsInstance(result, ZonePlacement)
        self.assertTrue(result.one_way)
        path = result.paths[0]
        self.assertLess(path[0][0], path[-1][0])  # drawn northwards, Testville to Otherton


class GeometryTests(unittest.TestCase):
    def test_stitch_joins_reversed_pieces(self):
        a = [(0.0, 0.0), (0.0, 0.001)]
        b = [(0.0, 0.002), (0.0, 0.001)]
        self.assertEqual(stitch([a, b]), [[(0.0, 0.002), (0.0, 0.001), (0.0, 0.0)]])

    def test_simplify_drops_straight_line_points(self):
        line = [(0.0, k * 0.0001) for k in range(11)]
        self.assertEqual(simplify(line, 1.0), [line[0], line[-1]])

    def test_shortest_path_bridges_small_gaps(self):
        a = [(0.0, 0.0), (0.0, 0.001)]
        b = [(0.0, 0.00125), (0.0, 0.003)]  # starts about 28 m after a ends
        path = shortest_path([a, b], a[0], b[-1], reach_m=10)
        self.assertEqual(path, a + b)

    def test_shortest_path_keeps_to_one_way_carriageways(self):
        # Divided road: northbound drawn south to north, southbound drawn north to south, 60 m apart.
        north = [(k * 0.001, 0.0) for k in range(6)]
        south = [(k * 0.001, 0.00066) for k in range(5, -1, -1)]
        path = shortest_path([north, south], (0.0, 0.0003), (0.005, 0.0003), one_way=["FT", "FT"], reach_m=100)
        self.assertEqual(path, north)
        path = shortest_path([north, south], (0.005, 0.0003), (0.0, 0.0003), one_way=["FT", "FT"], reach_m=100)
        self.assertEqual(path, south)

    def test_shortest_path(self):
        line = [(0.0, k * 0.001) for k in range(6)]
        path = shortest_path([line], (0.0, 0.0011), (0.0, 0.0039), reach_m=10)
        self.assertEqual(path, line[1:5])
        self.assertAlmostEqual(length_m(path), 3 * 111.2, delta=1)


if __name__ == "__main__":
    unittest.main()
