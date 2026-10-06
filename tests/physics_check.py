"""Automatic physics checks of the real 6502 kernel, frame by frame.

A Monitor watches every physics_tick of a Runtime and records
- violations: wall penetration or tunneling (centre outside the course),
  speed or energy gain, an exhausted contact limit, jitter and a ball
  stuck against walls;
- the deviation from the independent reference (physics_reference.frame)
  started from the kernel's own state, by frame class.

Tolerances follow from the kernel's documented approximations:
- free roll: VELOCITY = floor(SPEED * UNIT) per axis, < 1/256 px each;
- rim: the 1/64 rad turn is rounded per component (Q1.8) and the drag
  floors once;
- wall faces: the exact mirror, but the frame remainder after an axis or
  45-degree contact keeps the old speed (at most 4 px * 7 % = 0.28 px);
- vertices: contact time to 1/16 frame (CIRCLE_MIN_BIT), the normal taken
  at the last outside point up to 0.25 px before the contact (compared
  against the reference ball shifted across by up to 1/4 px); its length
  0.98..1 changes the speed loss by up to 4 % of 6 % of SPEED plus floors.
  Next to adjacent faces (a V notch) the shifted path may hit the face
  instead, so the direction tolerance stays 5 degrees (measured: 4.4);
- joint: two faces 45 degrees apart touched in the same 1/256 step are
  reflected at the halfway normal, stored as 255/256 truncated;
- rim-centre: the cup lies dead ahead (side test within 2/256 px); kernel
  and reference may turn to opposite sides by 1/64 rad each;
- border: kernel and reference disagree whether the ball touches a wall
  at the very end of the frame or grazes it (path within 1/32 px of the
  touching distance); the bounce then happens one frame later in one of
  the two, positions differ by at most the face tolerance.
"""
from dataclasses import dataclass, field
import copy
import math

import physics_reference as ref

TOLERANCE = {
    # class: (position px, direction degrees, speed units)
    'free': (1.5/256, 0.01, 0),
    'rim': (2/256, 0.2, 1),
    'face': (0.31, 0.05, 3.5),
    'joint': (0.3, 1.0, 4),      # halfway normal scaled by 255/256, truncated
    'vertex': (0.75, 5.0, 5),    # after the shift, see VERTEX_SHIFT
    'rim-centre': (2/256, 2.0, 1),   # turned the other way: 2 * 0.9 degrees
    'border': (0.3, None, None),
}
PENETRATION = 3/256       # wall epsilon (2/256) plus rounding of a frame
# A grazing vertex hit turns the ball by up to 3.2 rad per pixel of impact
# offset. The kernel reflects at the last outside offset Q (1/16 frame,
# up to 1/4 px early): that is the exact reflection of the same ball with
# its path shifted across by |Q| - 2 <= 1/4 px. It passes when it matches
# the exact physics of the ball shifted by at most that much.
VERTEX_SHIFT = 1/4
JITTER_WINDOW = 16        # frames
STUCK_SPEED = 64          # SPEED units: 1/4 px per frame


@dataclass
class Report:
    frames: int = 0
    shots: int = 0
    counts: dict = field(default_factory=dict)
    worst: dict = field(default_factory=dict)      # class -> (pos, dir, speed)
    violations: list = field(default_factory=list)
    peak_cycles: tuple = (0, None)
    contacts: dict = field(default_factory=dict)   # contacts per frame -> count

    def merge(self, other):
        self.frames += other.frames
        self.shots += other.shots
        for k, v in other.counts.items():
            self.counts[k] = self.counts.get(k, 0)+v
        for k, v in other.contacts.items():
            self.contacts[k] = self.contacts.get(k, 0)+v
        for k, v in other.worst.items():
            mine = self.worst.get(k, (0, 0, 0))
            self.worst[k] = tuple(max(a, b) for a, b in zip(mine, v))
        self.violations += other.violations
        if other.peak_cycles[0] > self.peak_cycles[0]:
            self.peak_cycles = other.peak_cycles


def angle_between(ax, ay, bx, by):
    return math.degrees(abs((math.atan2(ay, ax)-math.atan2(by, bx)+math.pi) % math.tau-math.pi))


class Monitor:
    """Steps the kernel and checks each frame. `course` gives the geometry
    for the reference; `playable` (x, y) -> bool defaults to its contours."""

    def __init__(self, runtime, course, report=None, expect_limit=False):
        self.r = runtime
        self.course = course
        self.segments = ref.course_segments(course)
        self.cup = tuple(course['cup'])
        self.report = report or Report()
        self.expect_limit = expect_limit

    def violation(self, kind, info):
        self.report.violations.append((kind, info))

    def tick(self, label):
        """One physics_tick with all checks. Returns the kernel state."""
        r, S = self.r, self.r.S
        before = ref.kernel_state(r)
        shots, limit = r.get('SHOTS'), r.get('CONTACT_LIMIT_HITS')
        cycles = r.call('physics_tick')
        after = ref.kernel_state(r)
        report = self.report
        report.frames += 1
        if cycles > report.peak_cycles[0]:
            report.peak_cycles = (cycles, label)
        if not before.rolling or before.holed:
            return after
        contacts = S['MAX_CONTACTS']-r.get('CONTACTS_LEFT')
        report.contacts[contacts] = report.contacts.get(contacts, 0)+1
        info = (label, round(before.x, 4), round(before.y, 4), before.ux, before.uy, before.speed)
        if r.get('CONTACT_LIMIT_HITS') != limit and not self.expect_limit:
            self.violation('contact-limit', info)
        if not after.holed:
            gap = ref.clearance(self.segments, after.x, after.y)
            if gap < ref.RADIUS-PENETRATION:
                self.violation('penetration', info+(round(gap, 4),))
            if not ref.playable(self.course, after.x, after.y):
                self.violation('tunneling', info+(after.x, after.y))
        if after.speed > before.speed:
            self.violation('speed-gain', info+(after.speed,))
        if after.speed*math.hypot(after.ux, after.uy) > before.speed*math.hypot(before.ux, before.uy):
            self.violation('energy-gain', info+(after.speed, after.ux, after.uy))
        if r.get('SHOTS') != shots:
            # Water: back ashore and at rest, the centre on dry floor
            # (the exact three-pixel gap: test_runtime water tests).
            report.counts['water'] = report.counts.get('water', 0)+1
            wet = any(x1 <= after.x < x2 and y1 <= after.y < y2
                      for x1, y1, x2, y2 in self.course.get('hazards', []))
            if wet or after.rolling:
                self.violation('water', info+(after.x, after.y))
            return after
        self.compare(before, after, contacts, info)
        return after

    def path_clearance(self, before, end):
        """Smallest wall distance along the straight path before -> end."""
        from generate_assets import segment_distance
        a, b = (before.x, before.y), (end.x, end.y)
        if a == b:
            return ref.clearance(self.segments, *a)
        return min(math.dist(*segment_distance(a, b, s.a, s.b)) for s in self.segments)

    def compare(self, before, after, contacts, info):
        predicted = ref.frame(copy.deepcopy(before), self.segments, self.cup)
        report = self.report
        if predicted.holed != after.holed:
            # The catch circle is touched at its very edge: the ball (or its
            # path in this frame) passes within 1/16 px of 3 px.
            end = predicted if after.holed else after   # the path not cut short by the catch
            path = ref.Segment((before.x, before.y), (end.x, end.y), (0, 0))
            near = math.dist(self.cup, ref.closest_point(path, *self.cup)) \
                if path.a != path.b else math.dist(self.cup, path.a)
            if abs(near-ref.CATCH_RADIUS) > 1/16:
                self.violation('cup', info+(predicted.holed, after.holed))
            report.counts['cup-border'] = report.counts.get('cup-border', 0)+1
            return
        if after.holed:
            report.counts['holed'] = report.counts.get('holed', 0)+1
            return
        if predicted.contacts != contacts:
            # Touching at the frame end or grazing within 1/32 px: one of the
            # two sees the contact, the other one a frame later or never.
            kind = 'border'
            if predicted.contacts == 0:
                gap = self.path_clearance(before, predicted)
            else:
                gap = min(ref.clearance(self.segments, predicted.x, predicted.y),
                          ref.clearance(self.segments, after.x, after.y), self.path_clearance(before, after))
            if gap > ref.RADIUS+1/32:
                self.violation('contact-mismatch', info+(predicted.events, contacts))
                return
        elif contacts and self.r.get('BEST_VERTEX'):
            kind = 'vertex'           # the kernel took a vertex (also at an end point)
        elif 'vertex' in predicted.events:
            kind = 'vertex'
        elif 'joint' in predicted.events:
            kind = 'joint'
        elif contacts:
            kind = 'face'
        else:
            # The kernel turns at the rim when its own end point is within
            # 5.5 px of the cup, towards the side the cup lies on. At the
            # very edge, or with the cup dead ahead, the two may disagree.
            qx, qy = after.x-self.cup[0], after.y-self.cup[1]
            near = math.hypot(qx, qy)
            side = before.ux*qy-before.uy*qx
            if (near < ref.RIM_RADIUS) != ('rim' in predicted.events):
                kind = 'border'
                if abs(near-ref.RIM_RADIUS) > 1/32:
                    self.violation('rim-mismatch', info+(round(near, 4),))
                    return
            elif 'rim' in predicted.events and abs(side) < 2/256:
                kind = 'rim-centre'   # cup dead ahead: either turn is right
            elif 'rim' in predicted.events:
                kind = 'rim'
            else:
                kind = 'free'
        report.counts[kind] = report.counts.get(kind, 0)+1
        if kind == 'vertex':
            predicted = self.nearest_shift(before, after, predicted)
        position = math.hypot(predicted.x-after.x, predicted.y-after.y)
        direction = speed = 0
        if kind != 'border':
            speed = abs(predicted.speed-after.speed)
            if after.rolling and predicted.rolling:
                direction = angle_between(predicted.ux, predicted.uy, after.ux, after.uy)
        worst = report.worst.get(kind, (0, 0, 0))
        report.worst[kind] = (max(worst[0], position), max(worst[1], direction), max(worst[2], speed))
        limit_pos, limit_dir, limit_speed = TOLERANCE[kind]
        if position > limit_pos or (limit_dir is not None and direction > limit_dir) or \
                (limit_speed is not None and speed > limit_speed):
            self.violation('reference-'+kind, info+(round(position, 4), round(direction, 3), speed))

    def nearest_shift(self, before, after, predicted):
        """The reference frame for the ball shifted across its path by up to
        VERTEX_SHIFT that best matches the kernel's outgoing direction."""
        best = predicted
        error = angle_between(predicted.ux, predicted.uy, after.ux, after.uy)
        length = math.hypot(before.ux, before.uy)
        px, py = -before.uy/length, before.ux/length
        for k in range(-32, 33):
            shift = k*VERTEX_SHIFT/32
            trial = copy.deepcopy(before)
            trial.x += px*shift
            trial.y += py*shift
            trial = ref.frame(trial, self.segments, self.cup)
            if trial.rolling and 'vertex' in trial.events:
                e = angle_between(trial.ux, trial.uy, after.ux, after.uy)
                if e < error:
                    best, error = trial, e
        return best

    def shot(self, angle, power, label, limit=600, settle=True):
        """Strike from the current ball position and roll to rest (or watch
        only `limit` frames when settle is False)."""
        r = self.r
        r.put('ANGLE', angle)
        r.put('POWER', power)
        r.call('start_shot')
        self.report.shots += 1
        pixels = []
        path = []
        for frame in range(limit):
            if not r.get('ROLLING'):
                return frame
            before = ref.kernel_state(r)
            state = self.tick((label, angle, power, frame))
            pixels.append((round(state.x), round(state.y)))
            path.append((math.dist((before.x, before.y), (state.x, state.y)), state.speed))
            self.jitter_and_stuck(pixels, path, (label, angle, power, frame))
        if settle:
            self.violation('never-stops', (label, angle, power))
        return limit

    def jitter_and_stuck(self, pixels, path, info):
        """Jitter: the drawn pixel turns back on an axis at least three times
        within 16 frames with at most one pixel between the turns. Stuck: a
        ball still faster than 1/4 px per frame whose path over 16 frames is
        shorter than one pixel."""
        if len(pixels) < JITTER_WINDOW:
            return
        window = pixels[-JITTER_WINDOW:]
        for axis in (0, 1):
            turns = []
            direction = 0
            for a, b in zip(window, window[1:]):
                step = (b[axis] > a[axis])-(b[axis] < a[axis])
                if step and direction and step != direction:
                    turns.append(a[axis])
                if step:
                    direction = step
            small = sum(1 for p, q in zip(turns, turns[1:]) if abs(p-q) <= 1)
            if small >= 2:
                self.violation('jitter', info+(axis, turns))
                return
        if path[-1][1] > STUCK_SPEED and sum(d for d, _ in path[-JITTER_WINDOW:]) < 1:
            self.violation('stuck', info)


def start_points(course, spacing=12, margin=3.0):
    """Floor points on a grid: centre playable, wall clearance >= margin,
    not in water and away from the cup."""
    segments = ref.course_segments(course)
    xs = [p[0] for p in course['outline']]
    ys = [p[1] for p in course['outline']]
    water = [tuple(a) for a in course.get('hazards', [])]
    points = []
    for y in range(min(ys)+spacing//2, max(ys), spacing):
        for x in range(min(xs)+spacing//2, max(xs), spacing):
            if not ref.playable(course, x, y) or ref.clearance(segments, x, y) < margin:
                continue
            if any(x1-3 <= x < x2+3 and y1-3 <= y < y2+3 for x1, y1, x2, y2 in water):
                continue
            if math.dist((x, y), course['cup']) < 8:
                continue
            points.append((x, y))
    return points


def place(r, x, y):
    S = r.S
    xv, yv = round(x*256), round(y*256)
    r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [xv & 255, (xv >> 8) & 255, xv >> 16]
    r.bus[S['BALL_POS_Y']:S['BALL_POS_Y']+2] = [yv & 255, yv >> 8]
