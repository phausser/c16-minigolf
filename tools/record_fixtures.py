"""Re-record the physics regression fixtures after a deliberate physics change.

    python3 tools/record_fixtures.py corners   tests/fixtures/corner-replays.json
    python3 tools/record_fixtures.py replays   tests/fixtures/input-replays.json

`corners` replays three historical corner shots on the pre-grid test
geometry (tests/test_physics.py, test_corner_replays_match_recorded_states).
`replays` turns every recorded best line (tests/fixtures/course-solutions.json,
`make solve`) into joystick input and stores its per-frame digest
(tests/replay.py). Run `make solve` first when courses or physics changed.
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tests'), str(ROOT/'tools')]


def corners():
    from test_runtime import Runtime, S
    from test_physics import position
    from generate_assets import DIRECTIONS, orientation
    geometry = json.loads((ROOT/'tests/fixtures/course-before-cell-grid.json').read_text())
    encoded = []
    for ci, contour in enumerate([geometry['outline'], *geometry['obstacles']]):
        area = sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(contour, contour[1:]+contour[:1]))
        for i, a in enumerate(contour):
            b = contour[(i+1) % len(contour)]
            direction = DIRECTIONS.index(((b[0] > a[0])-(b[0] < a[0]), (b[1] > a[1])-(b[1] < a[1])))
            normal = (direction+(2 if (area > 0) == (ci == 0) else -2)) % 8
            turn = orientation(contour[i-1], a, b)
            hidden = turn == 0 or ((turn*area > 0) == (ci == 0))
            encoded += [a[0]//2, a[1]//2, b[0]//2, b[1]//2, normal | (128 if hidden else 0)]
    old = json.loads((ROOT/'tests/fixtures/corner-replays.json').read_text())
    cases = []
    for case in old:
        r = Runtime()
        r.call('initialise_state')
        r.bus[S['course_segments']:S['course_segments']+len(encoded)] = encoded
        r.put('SEGMENT_BYTES', len(encoded))
        position(r, case['x'], case['y'])
        r.put('ANGLE', case['angle'])
        r.put('POWER', 32)
        r.call('start_shot')
        states = []
        for _ in case['states']:
            r.call('physics_tick')
            states.append(r.bus[S['BALL_POS_X']:S['BALL_POS_X']+len(case['states'][0])])
        cases.append({**case, 'states': states})
    return cases


def replays():
    from replay import record, play
    solutions = json.loads((ROOT/'tests/fixtures/course-solutions.json').read_text())
    cases = []
    for solution in solutions:
        runs = record(solution['hole'], solution['shots'])
        digest, state, frames, r = play(solution['hole'], runs)
        if not r.get('HOLED'):
            raise SystemExit(f"hole {solution['hole']}: the replayed line does not hole out")
        cases.append({'hole': solution['hole'], 'shots': solution['shots'], 'runs': runs,
                      'frames': frames, 'digest': digest, 'state': state})
        print(f"hole {solution['hole']:2d}: {frames} frames")
    return cases


if __name__ == '__main__':
    kind, target = sys.argv[1], Path(sys.argv[2])
    data = {'corners': corners, 'replays': replays}[kind]()
    if kind == 'corners':
        text = json.dumps(data, indent=2)+'\n'
    else:
        text = json.dumps(data, indent=1)+'\n'
    target.write_text(text)
    print(f'{target}: {len(data)} cases')
