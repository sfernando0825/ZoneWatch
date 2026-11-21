import unittest

from zonewatch_pipeline.names import RoadName, parse_location, parse_road, suburb_key


class ParseRoadTests(unittest.TestCase):
    def test_expands_type_abbreviation(self):
        self.assertEqual(parse_road("Portrush Rd"), RoadName("PORTRUSH", "ROAD"))
        self.assertEqual(parse_road("PARK TCE"), RoadName("PARK", "TERRACE"))
        self.assertEqual(parse_road("West Lakes Bvd"), RoadName("WEST LAKES", "BOULEVARD"))

    def test_expands_words_in_the_name(self):
        self.assertEqual(parse_road("LWR NORTH EAST RD"), RoadName("LOWER NORTH EAST", "ROAD"))

    def test_full_type_words(self):
        self.assertEqual(parse_road("Cross Road"), RoadName("CROSS", "ROAD"))
        self.assertEqual(parse_road("Northern Expressway"), RoadName("NORTHERN", "EXPRESSWAY"))

    def test_keeps_hyphens_and_apostrophes(self):
        self.assertEqual(parse_road("North-South Motorway"), RoadName("NORTH SOUTH", "MOTORWAY"))
        self.assertEqual(parse_road("O'Sullivan Beach Rd"), RoadName("O'SULLIVAN BEACH", "ROAD"))

    def test_type_suffix(self):
        self.assertEqual(parse_road("Commercial St East"), RoadName("COMMERCIAL", "STREET", "EAST"))
        self.assertEqual(parse_road("North East Rd"), RoadName("NORTH EAST", "ROAD"))

    def test_short_forms(self):
        self.assertEqual(parse_road("Pt Wakefield Hwy"), RoadName("PORT WAKEFIELD", "HIGHWAY"))
        self.assertEqual(parse_road("SE Freeway"), RoadName("SOUTH EASTERN", "FREEWAY"))

    def test_display(self):
        self.assertEqual(RoadName("O'SULLIVAN BEACH", "ROAD").display(), "O'Sullivan Beach Road")

    def test_saint_is_not_street_when_first(self):
        self.assertEqual(parse_road("St Bernards Rd"), RoadName("ST BERNARDS", "ROAD"))


class ParseLocationTests(unittest.TestCase):
    def test_intersection_with_suburb(self):
        loc = parse_location("Greenhill Rd and Hutt Rd, Adelaide")
        self.assertEqual(loc.roads, (RoadName("GREENHILL", "ROAD"), RoadName("HUTT", "ROAD")))
        self.assertEqual(loc.suburbs, ("ADELAIDE",))
        self.assertTrue(loc.is_intersection)

    def test_ampersand_and_suburb_column(self):
        loc = parse_location("KENSINGTON RD & PORTRUSH RD", "MARRYATVILLE")
        self.assertEqual(loc.roads, (RoadName("KENSINGTON", "ROAD"), RoadName("PORTRUSH", "ROAD")))
        self.assertEqual(loc.suburbs, ("MARRYATVILLE",))

    def test_single_road(self):
        loc = parse_location("Prospect Rd, Prospect")
        self.assertEqual(loc.roads, (RoadName("PROSPECT", "ROAD"),))
        self.assertFalse(loc.is_intersection)

    def test_lane_prefix(self):
        loc = parse_location("Lane 1, North-South Motorway, Regency Park")
        self.assertEqual(loc.lane, 1)
        self.assertEqual(loc.roads, (RoadName("NORTH SOUTH", "MOTORWAY"),))
        self.assertEqual(loc.suburbs, ("REGENCY PARK",))

    def test_between_two_places(self):
        loc = parse_location("Sturt Hwy, Lowbank to Wigley Flat")
        self.assertEqual(loc.suburbs, ("LOWBANK", "WIGLEY FLAT"))
        self.assertTrue(loc.is_between_places)

    def test_suburb_short_forms(self):
        loc = parse_location("SE Freeway, Callington to Mt Barker Summit")
        self.assertEqual(loc.suburbs, ("CALLINGTON", "MOUNT BARKER SUMMIT"))
        self.assertEqual(suburb_key("KiKi"), suburb_key("Ki Ki"))

    def test_apostrophe_suburb(self):
        loc = parse_location("Main South Rd, O'Halloran Hill")
        self.assertEqual(loc.suburbs, ("O'HALLORAN HILL",))


if __name__ == "__main__":
    unittest.main()
