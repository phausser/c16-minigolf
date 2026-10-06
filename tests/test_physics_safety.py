"""Physics acceptance (SPEC "Abnahmekriterien der Physik") on the real 6502
kernel: walls, end points, corners, narrow passages, tunneling, the
contact limit, the cup, reach and direction, and input replays.

Each scene installs its own contours (2-pixel grid) into course_segments;
the real broadphase and narrowphase run. physics_check.Monitor checks every
frame against the independent reference and the safety invariants.
"""
import json
import math
from pathlib import Path
import unittest

from test_runtime import Runtime, S           # also puts tools/ on the path
from generate_assets import DIRECTIONS, orientation
from physics_check import Monitor, Report, place, angle_between
import physics_reference as ref

ROOT = Path(__file__).resolve().parents[1]
FAR_CUP = (300, 164)


def encoded_segments(contours):
    """decode_course's segment format for arbitrary 2-pixel contours."""
    encoded = []
    for index, contour in enumerate(contours):
        area = sum(p[0]*q[1]-p[1]*q[0] for p, q in zip(contour, contour[1:]+contour[:1]))
        for i, a in enumerate(contour):
            b = contour[(i+1) % len(contour)]
            dx, dy = b[0]-a[0], b[1]-a[1]
            direction = DIRECTIONS.index(((dx > 0)-(dx < 0), (dy > 0)-(dy < 0)))
            normal = (direction+(2 if (area > 0) == (index == 0) else -2)) % 8
            turn = orientation(contour[i-1], a, b)
            hidden = turn == 0 or ((turn*area > 0) == (index == 0))
            encoded += [a[0]//2, a[1]//2, b[0]//2, b[1]//2, normal | (0x80 if hidden else 0)]
    return encoded


def scene(contours, cup=FAR_CUP):
    """A fresh runtime with these contours and cup; returns (runtime, course)."""
    r = Runtime()
    r.call('initialise_state')
    data = encoded_segments(contours)
    assert len(data) <= 5*S['MAX_SEGMENTS']
    r.bus[S['course_segments']:S['course_segments']+len(data)] = data
    r.put('SEGMENT_BYTES', len(data))
    r.put('HAZARD_COUNT', 0)
    r.put('COURSE_CUP_X', cup[0] & 255)
    r.put('COURSE_CUP_X_HI', cup[0] >> 8)
    r.put('COURSE_CUP_Y', cup[1])
    return r, {'outline': contours[0], 'obstacles': contours[1:], 'cup': list(cup)}


def speed_units(r):
    return r.bus[S['SPEED']]+256*r.bus[S['SPEED']+1]


def assert_clean(test, report, allow=()):
    kinds = {}
    for kind, info in report.violations:
        if kind not in allow:
            kinds.setdefault(kind, info)
    test.assertEqual(kinds, {})


# Octagon room: all four axis and all four 45-degree wall directions.
OCTAGON = [[80, 24], [240, 24], [296, 80], [296, 110], [240, 166], [80, 166], [24, 110], [24, 80]]


class WallTests(unittest.TestCase):
    def test_faces_mirror_within_one_degree_and_lose_the_spec_speed(self):
        """Every wall direction, every approaching angle, three strengths:
        the first contact mirrors the unit within 1 degree, takes the SPEC
        speed loss and never lets the ball into the wall."""
        r, course = scene([OCTAGON])
        snapshot = list(r.bus)
        report = Report()
        monitor = Monitor(r, course, report)
        contacts = 0
        for segment in ref.course_segments(course):
            (ax, ay), (bx, by), (nx, ny) = segment.a, segment.b, segment.normal
            mx, my = (ax+bx)/2, (ay+by)/2
            for angle in range(0, 128, 2):
                ux, uy = math.cos(angle*math.tau/128), math.sin(angle*math.tau/128)
                if ux*nx+uy*ny > -0.04:          # down to 2.3 degrees: flat hits
                    continue
                for power, distance in ((8, 2.3), (20, 3.1), (32, 5.7)):
                    r.bus[:] = snapshot
                    place(r, mx+nx*distance-ux*0.5, my+ny*distance-uy*0.5)
                    r.put('ANGLE', angle)
                    r.put('POWER', power)
                    r.call('start_shot')
                    for frame in range(60):
                        before = ref.kernel_state(r)
                        after = monitor.tick(('face', angle, power, frame))
                        if S['MAX_CONTACTS']-r.get('CONTACTS_LEFT'):
                            break
                    else:
                        self.fail(('no contact', angle, power))
                    contacts += 1
                    # The wall actually reached first, from the reference.
                    hit = ref._earliest_contact(monitor.segments, before.x, before.y,
                                                before.ux*before.speed/256, before.uy*before.speed/256, 1)
                    if hit is None or hit[3] != 'face':
                        continue                      # touching at the frame end
                    _, nx, ny, _ = hit
                    d = before.ux*nx+before.uy*ny
                    mirror = (before.ux-2*d*nx, before.uy-2*d*ny)
                    self.assertLess(angle_between(after.ux, after.uy, *mirror), 1, (angle, power))
                    nx, ny = segment.normal
                    speed = before.speed
                    expected = speed-speed*d*d*31/512-speed/128-1-4    # plus roll braking
                    self.assertLessEqual(after.speed, before.speed)
                    self.assertLessEqual(abs(after.speed-expected), 3, (angle, power, after.speed, expected))
        self.assertGreater(contacts, 500)
        assert_clean(self, report)

    def test_maximum_speed_never_tunnels_through_a_thin_obstacle(self):
        """A 2-pixel bar hit at 4 px per frame from every sub-pixel offset."""
        bar = [[160, 60], [162, 60], [162, 120], [160, 120]]
        r, course = scene([[[24, 24], [296, 24], [296, 160], [24, 160]], bar])
        snapshot = list(r.bus)
        report = Report()
        monitor = Monitor(r, course, report)
        for angle in list(range(0, 24, 3))+list(range(106, 128, 3)):
            for offset in range(16):
                r.bus[:] = snapshot
                place(r, 150+offset/16+3*math.cos(angle*math.tau/128), 90+offset)
                r.put('ANGLE', angle)
                r.put('POWER', 32)
                r.call('start_shot')
                for frame in range(12):
                    state = monitor.tick(('bar', angle, offset, frame))
                    self.assertLess(state.x, 160, (angle, offset, frame))
        assert_clean(self, report)


class CornerTests(unittest.TestCase):
    def test_convex_end_points_reflect_without_gain(self):
        """Exposed corners of a square and a diamond, hit near their tips
        with impact offsets across the ball diameter."""
        square = [[120, 70], [136, 70], [136, 86], [120, 86]]
        diamond = [[200, 70], [216, 86], [200, 102], [184, 86]]
        r, course = scene([[[24, 24], [296, 24], [296, 160], [24, 160]], square, diamond])
        snapshot = list(r.bus)
        report = Report()
        monitor = Monitor(r, course, report)
        tips = [(120, 70), (136, 70), (136, 86), (120, 86), (200, 70), (216, 86), (200, 102), (184, 86)]
        for tx, ty in tips:
            for angle in range(3, 128, 16):
                ux, uy = math.cos(angle*math.tau/128), math.sin(angle*math.tau/128)
                for b in (-2.3, -1.2, -0.2, 0.7, 1.9):
                    x, y = tx-ux*8-uy*b, ty-uy*8+ux*b
                    if not ref.playable(course, x, y) or ref.clearance(monitor.segments, x, y) < 2.2:
                        continue
                    r.bus[:] = snapshot
                    place(r, x, y)
                    monitor.shot(angle, 32, ('tip', tx, ty, b), limit=16, settle=False)
        self.assertGreater(report.counts.get('vertex', 0), 40)
        assert_clean(self, report)

    def test_inner_corners_resolve_double_contacts(self):
        """90-degree and 135-degree inner corners: shots straight into the
        corner touch both walls in one frame and come back."""
        r, course = scene([OCTAGON])
        rect, rect_course = scene([[[24, 24], [296, 24], [296, 160], [24, 160]]])
        cases = [(rect, rect_course, (24, 24)), (rect, rect_course, (296, 160)),
                 (r, course, (80, 24)), (r, course, (296, 80)), (r, course, (24, 110))]
        doubles = 0
        report = Report()
        for runtime, geometry, (cx, cy) in cases:
            snapshot = list(runtime.bus)
            monitor = Monitor(runtime, geometry, report)
            for angle in range(0, 128, 2):
                ux, uy = math.cos(angle*math.tau/128), math.sin(angle*math.tau/128)
                x, y = cx-ux*12, cy-uy*12
                if not ref.playable(geometry, x, y) or ref.clearance(monitor.segments, x, y) < 2.5:
                    continue
                runtime.bus[:] = snapshot
                place(runtime, x, y)
                runtime.put('ANGLE', angle)
                runtime.put('POWER', 32)
                runtime.call('start_shot')
                for frame in range(16):
                    monitor.tick(('inner', cx, cy, angle, frame))
                    if S['MAX_CONTACTS']-runtime.get('CONTACTS_LEFT') >= 2:
                        doubles += 1
        # The diagonal into the rectangle corner: both walls, straight back.
        rect, _ = scene([[[24, 24], [296, 24], [296, 160], [24, 160]]])
        place(rect, 40, 40)
        rect.put('ANGLE', 80)              # 225 degrees, up and left
        rect.put('POWER', 32)
        rect.call('start_shot')
        before = ref.kernel_state(rect)
        for _ in range(12):
            rect.call('physics_tick')
        after = ref.kernel_state(rect)
        self.assertLess(angle_between(after.ux, after.uy, -before.ux, -before.uy), 1)
        self.assertGreater(doubles, 5)
        assert_clean(self, report)


class PassageTests(unittest.TestCase):
    def test_ten_pixel_passage_is_passable_without_sticking(self):
        """A 10-pixel corridor between two chambers (SPEC minimum width)."""
        room = [[24, 40], [100, 40], [100, 86], [220, 86], [220, 40], [296, 40],
                [296, 140], [220, 140], [220, 96], [100, 96], [100, 140], [24, 140]]
        r, course = scene([room])
        snapshot = list(r.bus)
        report = Report()
        monitor = Monitor(r, course, report)
        through = 0
        starts = [(70, 91), (90, 80), (110, 91), (104, 88.5)]
        for x, y in starts:
            for angle in (0, 1, 3, 6, 10, 14, 117, 121, 125, 127, 32, 64):
                for power in (16, 32):
                    r.bus[:] = snapshot
                    place(r, x, y)
                    monitor.shot(angle, power, ('passage', x, y), limit=160, settle=False)
                    through += ref.kernel_state(r).x > 220
        self.assertGreater(through, 10)
        assert_clean(self, report)


class ContactLimitTests(unittest.TestCase):
    def test_exhausted_limit_is_counted_and_never_lets_the_ball_through(self):
        """A slot exactly as wide as the ball (illegal in courses) forces
        more than four contacts per frame: the limit drops the rest of the
        frame, the ball stays inside and loses speed."""
        room = [[24, 40], [100, 40], [100, 88], [220, 88], [220, 40], [296, 40],
                [296, 140], [220, 140], [220, 92], [100, 92], [100, 140], [24, 140]]
        r, course = scene([room])
        report = Report()
        monitor = Monitor(r, course, report, expect_limit=True)
        place(r, 150, 90)
        r.put('ANGLE', 3)
        r.put('POWER', 32)
        r.call('start_shot')
        hits = []
        for frame in range(80):
            if not r.get('ROLLING'):
                break
            monitor.tick(('slot', frame))
            hits.append(r.get('CONTACT_LIMIT_HITS'))
        self.assertGreater(hits[-1], 0)
        self.assertFalse(r.get('ROLLING'))
        assert_clean(self, report, allow=('reference-face', 'reference-vertex', 'contact-mismatch'))


class CupTests(unittest.TestCase):
    CUP = (160, 100)

    def roll_past(self, angle, impact, speed, start_back=4.0):
        r, course = scene([[[24, 24], [296, 24], [296, 160], [24, 160]]], cup=self.CUP)
        ux, uy = math.cos(angle*math.tau/128), math.sin(angle*math.tau/128)
        place(r, self.CUP[0]-ux*start_back-uy*impact, self.CUP[1]-uy*start_back+ux*impact)
        r.put('ANGLE', angle)
        r.put('POWER', 1)
        r.call('start_shot')
        r.word('SPEED', speed)
        frames = 0
        while r.get('ROLLING') and frames < 400:
            r.call('physics_tick')
            frames += 1
            state = ref.kernel_state(r)
            if (state.x-self.CUP[0])*ux+(state.y-self.CUP[1])*uy > 3.5 and not r.get('HOLED'):
                break                   # past the catch circle
        return r

    def test_slow_ball_is_caught_from_every_direction(self):
        for angle in range(0, 128, 4):
            for impact in (0, 0.9, 1.8, 2.7):
                for speed in (64, 120, 192):
                    r = self.roll_past(angle, impact, speed, start_back=3.1)
                    self.assertEqual(r.get('HOLED'), 1, (angle, impact, speed))
                    self.assertEqual(ref.kernel_state(r).x, self.CUP[0])

    def test_fast_ball_rolls_over_the_cup(self):
        for angle in range(0, 128, 8):
            for speed in (240, 400, 1024):          # still above 192 on the cup
                r = self.roll_past(angle, 0, speed, start_back=3.5)
                self.assertEqual(r.get('HOLED'), 0, (angle, speed))

    def test_chord_through_the_catch_circle_within_one_step(self):
        """Both frame ends lie outside the 3 px catch radius, only the
        middle of the step crosses it: the swept test still catches."""
        r, _ = scene([[[24, 24], [296, 24], [296, 160], [24, 160]]], cup=self.CUP)
        place(r, self.CUP[0]-0.375, self.CUP[1]-2.98)
        r.put('ANGLE', 0)
        r.put('POWER', 6)              # SPEED 192: exactly 0.75 px per frame
        r.call('start_shot')
        state = ref.kernel_state(r)
        self.assertGreater(math.hypot(state.x-self.CUP[0], state.y-self.CUP[1]), 3)
        self.assertGreater(math.hypot(state.x+0.75-self.CUP[0], state.y-self.CUP[1]), 3)
        r.call('physics_tick')
        self.assertEqual(r.get('HOLED'), 1)


class ReachTests(unittest.TestCase):
    """Free roll on an unbounded field (no wall candidates, cup far away)."""

    def setUp(self):
        from test_physics import isolate_segments
        self.r = Runtime()
        self.r.call('initialise_state')
        isolate_segments(self.r, [])
        self.r.put('COURSE_CUP_X_HI', 4)
        self.snapshot = list(self.r.bus)

    def roll(self, angle, power):
        r = self.r
        r.bus[:] = self.snapshot
        place(r, 30000, 128)
        r.put('ANGLE', angle)
        r.put('POWER', power)
        r.call('start_shot')
        x = y = 0
        last = ref.kernel_state(r)
        while r.get('ROLLING'):
            r.call('physics_tick')
            now = ref.kernel_state(r)
            x += now.x-last.x
            y += (now.y-last.y+128) % 256-128    # Q8.8 y wraps at 256 px
            last = now
        return math.hypot(x, y), math.degrees(abs((math.atan2(y, x)-angle*math.tau/128+math.pi) % math.tau-math.pi))

    def spread(self, angles, power):
        results = [self.roll(a, power) for a in angles]
        reach = [d for d, _ in results]
        return (max(reach)-min(reach))/max(reach), max(e for _, e in results)

    def test_axes_and_diagonals_match_within_two_percent_and_one_degree(self):
        for power in range(1, 33):
            spread, error = self.spread(range(0, 128, 16), power)
            self.assertLessEqual(spread, .02, power)
            self.assertLessEqual(error, 1, power)

    def test_all_128_directions_from_strength_two(self):
        for power in (2, 13, 32):
            spread, error = self.spread(range(128), power)
            self.assertLessEqual(spread, .02, power)
            self.assertLessEqual(error, 1, power)


class VertexNormalTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime()
        self.r.call('initialise_state')

    def normal(self, qx, qy):
        r = self.r
        r.word('NX', qx & 0xffff)
        r.word('NY', qy & 0xffff)
        r.call('vertex_normal')
        nx = r.get('NX')+256*r.bus[S['NX']+1]
        ny = r.get('NY')+256*r.bus[S['NY']+1]
        return nx-65536*(nx > 32767), ny-65536*(ny > 32767)

    def test_corner_normals_are_unit_radial_and_never_longer_than_one(self):
        for length in (512, 513, 516, 530, 550, 576, 590, 600, 700, 1000, 1790):
            for i in range(64):
                a = i*math.tau/64+0.01
                qx, qy = math.floor(length*math.cos(a)), math.floor(length*math.sin(a))
                nx, ny = self.normal(qx, qy)
                self.assertLessEqual(nx*nx+ny*ny, 65536, (qx, qy, nx, ny))
                if length <= 590:
                    self.assertGreaterEqual(math.hypot(nx, ny), 0.978*256, (qx, qy, nx, ny))
                    self.assertLess(angle_between(nx, ny, qx, qy), 0.6, (qx, qy, nx, ny))

    def test_corner_reflection_never_gains_effective_speed(self):
        r = self.r
        for i in range(32):
            a = i*math.tau/32+0.03
            length = 512+(i*7) % 70
            nx, ny = self.normal(math.floor(length*math.cos(a)), math.floor(length*math.sin(a)))
            for angle in range(128):
                r.call('initialise_state')
                r.put('ANGLE', angle)
                r.put('POWER', 32)
                r.call('start_shot')
                r.call('velocity_from_unit')
                before = ref.kernel_state(r)
                if before.ux*nx+before.uy*ny >= 0:
                    continue
                r.word('NX', nx & 0xffff)
                r.word('NY', ny & 0xffff)
                r.call('reflect_unit')
                after = ref.kernel_state(r)
                self.assertLessEqual(after.speed*math.hypot(after.ux, after.uy),
                                     before.speed*math.hypot(before.ux, before.uy), (nx, ny, angle))
                # |n| >= 0.98 reverses at least 96 % of the normal share:
                # within 2.5 degrees of the exact mirror about n/|n|.
                n = math.hypot(nx, ny)
                d = (before.ux*nx+before.uy*ny)/n
                mirror = (before.ux-2*d*nx/n, before.uy-2*d*ny/n)
                self.assertLess(angle_between(after.ux, after.uy, *mirror), 2.5, (nx, ny, angle))


class ReplayTests(unittest.TestCase):
    """Input replays through scan/debounce/controls/physics are bit-exact."""
    FIXTURE = json.loads((ROOT/'tests/fixtures/input-replays.json').read_text())

    def test_recorded_replays_reproduce_every_frame(self):
        from replay import play
        for case in self.FIXTURE:
            digest, state, frames, r = play(case['hole'], case['runs'])
            self.assertEqual(frames, case['frames'], case['hole'])
            self.assertEqual(digest, case['digest'], case['hole'])
            self.assertEqual(state, case['state'], case['hole'])
            self.assertEqual(r.get('HOLED'), 1, case['hole'])

    def test_same_input_twice_gives_identical_states(self):
        from replay import play
        for case in self.FIXTURE[:3]:
            self.assertEqual(play(case['hole'], case['runs'])[:3], play(case['hole'], case['runs'])[:3])


if __name__ == '__main__':
    unittest.main()
