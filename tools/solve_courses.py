"""Play every course with the real 6502 physics (py65) and record the
shortest line found as a replay, with how forgiving its last shot is.

Beam search: from each resting spot try every 4th direction plus the
directions around the cup at seven strengths; water shots are discarded.
The spots kept for the next stroke are those with the shortest walking
distance to the cup around walls and water. The stroke count is an upper
bound on the true minimum, not a proof; it is the basis for par.
Writes tests/fixtures/course-solutions.json (replayed by the tests).
"""
import argparse
import heapq
import json
import math
from multiprocessing import Pool
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'tests')]
from course_codec import encode
from generate_assets import playable, hazard_cells
from test_runtime import Runtime, S

POWERS = (6, 10, 14, 18, 22, 26, 31)
BEAM = 10
MAX_STROKES = 7
GRID = 4
OUTPUT = ROOT/'tests/fixtures/course-solutions.json'


class Course:
    def __init__(self, course):
        self.course = course
        self.r = r = Runtime()
        data = encode(course)
        r.bus[S['course_table_lo']] = 0
        r.bus[S['course_table_hi']] = 0x80
        r.bus[0x8000:0x8000+len(data)] = list(data)
        r.call('initialise_video')
        r.call('initialise_state')
        r.call('draw_course')     # water is found by the cell colour
        self.start_state = bytes(r.bus[S['BALL_POS_X']:S['BALL_POS_X']+5])
        self.distance = walking_distance(course)

    def shot(self, state, angle, power):
        """'cup', None for water or a stuck ball, else the resting state."""
        r = self.r
        r.call('initialise_state')
        r.bus[S['BALL_POS_X']:S['BALL_POS_X']+5] = list(state)
        r.put('ANGLE', angle)
        r.put('POWER', power)
        r.call('start_shot')
        for _ in range(1000):
            r.call('physics_tick')
            if not r.get('ROLLING'):
                break
        else:
            return None
        if r.get('HOLED'):
            return 'cup'
        if r.get('SHOTS') != 1:
            return None
        return bytes(r.bus[S['BALL_POS_X']:S['BALL_POS_X']+5])

    def remaining(self, state):
        x, y = pixel(state)
        best = math.inf
        for dx in (0, -GRID, GRID):
            for dy in (0, -GRID, GRID):
                key = ((x+dx)//GRID, (y+dy)//GRID)
                if key in self.distance:
                    best = min(best, self.distance[key]+math.hypot(dx, dy))
        return best

    def angles(self, state):
        x, y = pixel(state)
        cx, cy = self.course['cup']
        towards = round(math.atan2(cy-y, cx-x)*64/math.pi)
        return sorted(set(range(0, 128, 4)) | {(towards+d) % 128 for d in range(-6, 7)})


def pixel(state):
    return state[1]+256*state[2], state[4]


def walking_distance(course):
    """Shortest path for the ball centre from every grid point to the cup."""
    contours = [course['outline'], *course['obstacles']]
    water = hazard_cells(course)
    ring = [(0, 0)]+[(2.5*math.cos(k*math.pi/4), 2.5*math.sin(k*math.pi/4)) for k in range(8)]

    def free(gx, gy):
        x, y = gx*GRID+GRID/2, gy*GRID+GRID/2
        return (int(y)//8, int(x)//8) not in water and \
            all(playable(contours, x+dx, y+dy) for dx, dy in ring)
    cup = (course['cup'][0]//GRID, course['cup'][1]//GRID)
    distance = {cup: 0}
    queue = [(0, cup)]
    while queue:
        d, (gx, gy) = heapq.heappop(queue)
        if d > distance[gx, gy]:
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (gx+dx, gy+dy)
                step = GRID*math.hypot(dx, dy)
                if step and d+step < distance.get(n, math.inf) and free(*n):
                    distance[n] = d+step
                    heapq.heappush(queue, (d+step, n))
    return distance


def solve(index):
    path = sorted((ROOT/'assets/courses').glob('*.json'))[index]
    course = json.loads(path.read_text())
    c = Course(course)
    frontier = [(c.start_state, [])]
    seen = {(pixel(c.start_state)[0]//GRID, pixel(c.start_state)[1]//GRID)}
    for strokes in range(1, MAX_STROKES+1):
        holed, spots = [], {}
        for state, line in frontier:
            for angle in c.angles(state):
                for power in POWERS:
                    result = c.shot(state, angle, power)
                    if result == 'cup':
                        holed.append((state, line+[[angle, power]]))
                    elif result:
                        key = (pixel(result)[0]//GRID, pixel(result)[1]//GRID)
                        if key not in seen:
                            seen.add(key)
                            spots[key] = (result, line+[[angle, power]])
        if holed:
            # Prefer the last shot whose neighbours (direction +-1,
            # strength +-2) also find the cup most often.
            def window(item):
                state, line = item
                angle, power = line[-1]
                return sum(c.shot(state, (angle+da) % 128, p) == 'cup'
                           for da in (-1, 0, 1) for p in (power-2, power, power+2)
                           if (da or p != power) and 1 <= p <= 31)
            scored = [(window(item), item) for item in holed]
            best_window, (_, line) = max(scored, key=lambda s: s[0])
            return dict(hole=index+1, name=course['name'], par=course.get('par'),
                        strokes=strokes, shots=line, last_shot_window=f'{best_window}/8',
                        holing_lines=len(holed))
        frontier = sorted(spots.values(), key=lambda s: c.remaining(s[0]))[:BEAM]
        if not frontier:
            break
        print(f'  Bahn {index+1}: {strokes} Schläge, {len(spots)} neue Lagen, '
              f'bester Rest {c.remaining(frontier[0][0]):.0f} px', flush=True)
    return dict(hole=index+1, name=course['name'], par=course.get('par'), strokes=None, shots=[])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('holes', nargs='*', type=int, help='holes 1..18 (default: all)')
    args = parser.parse_args()
    holes = args.holes or list(range(1, 19))
    with Pool(min(8, len(holes))) as pool:
        results = pool.map(solve, [h-1 for h in holes])
    known = {}
    if OUTPUT.exists():
        known = {s['hole']: s for s in json.loads(OUTPUT.read_text())}
    known.update({s['hole']: s for s in results})
    OUTPUT.write_text(json.dumps([known[h] for h in sorted(known)], indent=1, ensure_ascii=False)+'\n')
    for s in results:
        found = s['strokes'] or '—'
        print(f"{s['hole']:2} {s['name']:26} Par {s['par']}  gefunden {found}  "
              f"letzter Schlag {s.get('last_shot_window', '—')}")


if __name__ == '__main__':
    main()
