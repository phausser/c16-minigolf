"""Independent geometry roundtrips and malformed-stream handling."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from course_codec import encode, decode


class CourseCodecTests(unittest.TestCase):
    def setUp(self):
        self.course = json.loads((ROOT/'assets/test-course.json').read_text())
        self.geometry = {key:self.course[key] for key in ('start','cup','outline','obstacles')}

    def test_test_course_roundtrip_preserves_vertices_and_right_hand_room(self):
        packed = encode(self.course)
        self.assertEqual(decode(packed),self.geometry)
        self.assertLess(len(packed),85)
        self.assertGreater(max(p[0] for p in decode(packed)['outline']),255)

    def test_long_edges_and_32_unit_runs(self):
        course = {'start':[40,40],'cup':[272,112],
                  'outline':[[16,24],[304,24],[304,152],[16,152]],'obstacles':[]}
        self.assertEqual(decode(encode(course)),course)

    def test_water_areas_roundtrip_and_validation(self):
        course = {'start':[40,88],'cup':[272,88],'obstacles':[],
                  'outline':[[16,24],[304,24],[304,152],[16,152]],
                  'hazards':[[128,64,176,112],[208,24,240,48]]}
        packed = encode(course)
        self.assertEqual(packed[5], 1 | 2 << 5)
        self.assertEqual(list(packed[-8:]), [16,8,21,13, 26,3,29,5])
        self.assertEqual(decode(packed), course)
        for hazards in ([[128,64,176,110]],       # not cell aligned
                        [[8,64,40,112]],          # covers the frame
                        [[32,80,48,96]],          # start in water
                        [[128,64,176,112]]*8):    # too many areas
            with self.assertRaises(ValueError, msg=hazards):
                encode(dict(course, hazards=hazards))

    def test_every_truncation_and_trailing_byte_is_rejected(self):
        packed = encode(self.course)
        for index in range(len(packed)):
            with self.assertRaises(ValueError):
                decode(packed[:index])
        with self.assertRaises(ValueError):
            decode(packed+b'\0')

    def test_start_coordinates_cannot_be_silently_rounded(self):
        self.course['start'][0] += 1
        with self.assertRaises(ValueError):
            encode(self.course)

    def test_wrong_side_flag_and_open_contour_are_rejected(self):
        packed = bytearray(encode(self.course))
        packed[6] ^= 128            # outline side flag
        with self.assertRaises(ValueError):
            decode(packed)
        packed[6] ^= 128
        packed[-1] ^= 1
        with self.assertRaises(ValueError):
            decode(packed)
