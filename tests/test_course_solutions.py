"""Replay the recorded best line of every course (tools/solve_courses.py)
in the game build: same physics, no water, holed with the last stroke.
A failure means a course or the physics changed: run the solver again."""
import json
from pathlib import Path
import unittest

from test_runtime import Runtime

ROOT = Path(__file__).resolve().parents[1]
SOLUTIONS = json.loads((ROOT/'tests/fixtures/course-solutions.json').read_text())
COURSES = sorted((ROOT/'assets/courses').glob('*.json'))


class CourseSolutionTests(unittest.TestCase):
    def test_every_recorded_line_holes_out(self):
        for solution in SOLUTIONS:
            r = Runtime('minigolf')
            r.put('HOLE', solution['hole']-1)
            r.call('initialise_video')
            r.call('initialise_state')
            r.call('draw_course')         # water is found by the cell colour
            for stroke, (angle, power) in enumerate(solution['shots'], 1):
                self.assertFalse(r.get('HOLED'), solution['hole'])
                r.put('ANGLE', angle)
                r.put('POWER', power)
                r.call('start_shot')
                for _ in range(1000):
                    r.call('physics_tick')
                    if not r.get('ROLLING'):
                        break
                self.assertEqual(r.get('SHOTS'), stroke, (solution['hole'], 'water'))
            self.assertEqual(r.get('HOLED'), 1, solution['hole'])

    def test_status_line_shows_the_par_of_each_hole(self):
        r = Runtime('minigolf')
        r.call('initialise_video')
        codes = {' ': 32, **{d: 48+int(d) for d in '0123456789'},
                 **{c: ord(c)-64 for c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'}}
        for solution in SOLUTIONS:
            r.put('HOLE', solution['hole']-1)
            r.call('draw_status')
            row = r.bus[r.S['SCREEN_BASE']+24*40:r.S['SCREEN_BASE']+25*40]
            par = json.loads(COURSES[solution['hole']-1].read_text())['par']
            text = f"PAR {par}"
            self.assertEqual(list(row[8:8+len(text)]), [codes[c] for c in text], solution['hole'])

    def test_every_course_has_a_line(self):
        self.assertEqual([s['hole'] for s in SOLUTIONS if s['shots']], list(range(1, 19)))


if __name__ == '__main__':
    unittest.main()
