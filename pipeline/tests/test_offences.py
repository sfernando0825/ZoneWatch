import unittest
from datetime import date

from zonewatch_pipeline.offences import read_sites_from_text

HEADER = (
    "Event ID,Notice Revision,Notice Type Desc,Notice Status,Offence Status,Withdrawn Reason,"
    "Incident Start Date,Time 24 Hour - Incident Start,Expiation Offence Code,Expiation Offence Description,"
    "Issue Date,Camera Category,Location Code,Location Description,Location Suburb,District/Service Area,"
    "Vehicle Description,Licence State,Registration State,Vehicle Speed,Expiation Zone Speed Limit,"
    "Offence Penalty Amount,Victim Of Crime Levy Amount,Corporate Fee Amount,Offence Total\n"
)


def row(event, day, offence, category, code, desc, suburb, limit=""):
    return (
        f'{event},EMSNOT001,EXPIATION NOTICE,EXPIATED,EXPIATED,,{day},0:05,X,{offence},{day},{category},{code},'
        f'"{desc}",{suburb},WESTERN DISTRICT,2014 GREY CAR,SOUTH AUSTRALIA,SOUTH AUSTRALIA,59,{limit},$1,$1,$0,$2\n'
    )


class ReadSitesTests(unittest.TestCase):
    def test_groups_notices_by_site(self):
        text = HEADER + "".join([
            row("E1", "1/07/2026", "Exceed speed limit by less than 10 kph", "FIXED CAMERA", "186", "Prospect Rd, Prospect", " Prospect", "50"),
            row("E1", "1/07/2026", "Exceed speed limit by less than 10 kph", "FIXED CAMERA", "186", "Prospect Rd, Prospect", " Prospect", "50"),
            row("E2", "3/08/2026", "Exceed speed limit by 20-29 kph", "FIXED CAMERA", "186", "Prospect Rd, Prospect", " Prospect", "50"),
            row("E3", "2/07/2026", "EXCEED SPEED LIMIT", "MOBILE CAMERA", "1865", "PORT RD", "CHELTENHAM", "60"),
        ])
        sites = read_sites_from_text(text)
        fixed = sites[("fixed", "186")]
        self.assertEqual(fixed.notices, 2)
        self.assertEqual(fixed.speed_limit_kmh, 50)
        self.assertEqual(fixed.first_seen, date(2026, 7, 1))
        self.assertEqual(fixed.last_seen, date(2026, 8, 3))
        self.assertEqual(fixed.camera_type, "fixedSpeed")
        mobile = sites[("mobile", "1865")]
        self.assertEqual(mobile.camera_type, "mobileSpeed")
        self.assertEqual(str(mobile.location.roads[0]), "PORT ROAD")
        self.assertEqual(mobile.location.suburbs, ("CHELTENHAM",))

    def test_classifies_camera_types(self):
        text = HEADER + "".join([
            row("A", "1/07/2026", "Enter an intersection or marked foot crossing showing a red traffic light", "FIXED CAMERA", "51", "Greenhill Rd and Hutt Rd, Adelaide", " Adelaide", "60"),
            row("B", "1/07/2026", "Exceed speed limit by less than 10 kph", "FIXED CAMERA", "51", "Greenhill Rd and Hutt Rd, Adelaide", " Adelaide", "60"),
            row("C", "1/07/2026", "Use mobile phone while driving", "FIXED CAMERA", "1011", "Lane 1, North-South Motorway, Regency Park", " Regency Park"),
            row("D", "1/07/2026", "Exceed speed limit by 10-19 kph (Average Speed Camera)", "FIXED CAMERA", "608", "Dukes Hwy, Ki Ki to Coonalpyn", " Ki Ki to Coonalpyn", "110"),
            row("E", "1/07/2026", "Be the owner of unregistered motor vehicle driven or found standing on a road", "FIXED CAMERA", "406", "Dukes Hwy, Keith", " Keith"),
            row("F", "1/07/2026", "DISOBEY RED DISC AT PEDESTRIAN CROSSING", "FIXED CAMERA", "47", "PARK TCE", "SALISBURY", "60"),
        ])
        types = {code: s.camera_type for (_, code), s in read_sites_from_text(text).items()}
        self.assertEqual(types, {
            "51": "redLightSpeed",
            "1011": "phoneCamera",
            "608": "averageSpeedSection",
            "406": None,
            "47": "redLightSpeed",
        })

    def test_heavy_vehicle_limit_is_not_the_zone_limit(self):
        text = HEADER + "".join([
            row("A", "1/07/2026", "Exceed speed limit by 10-19 kph", "FIXED CAMERA", "802", "South Eastern Fwy, Leawood Gardens", " Leawood Gardens", "90"),
            row("B", "1/07/2026", "Prescribed road - Truck/Bus exceed speed limit by 10 kph or more", "FIXED CAMERA", "802", "South Eastern Fwy, Leawood Gardens", " Leawood Gardens", "60"),
            row("C", "1/07/2026", "Prescribed road - Truck/Bus exceed speed limit by 10 kph or more", "FIXED CAMERA", "802", "South Eastern Fwy, Leawood Gardens", " Leawood Gardens", "60"),
        ])
        self.assertEqual(read_sites_from_text(text)[("fixed", "802")].speed_limit_kmh, 90)


if __name__ == "__main__":
    unittest.main()
