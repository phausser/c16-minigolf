"""Exhaustive physics sweep of the real 6502 kernel on all 18 courses.

`make physics` (optional HOLES="3 7", STRIDE=4, SPACING=16) strikes the ball
from the course start and from a grid of floor points in every STRIDE-th
of the 128 directions at several strengths, with the game build in py65.
Every frame goes through tests/physics_check.Monitor: wall penetration,
tunneling, speed/energy gain, contact limit, jitter, stuck balls, and the
per-frame deviation from the independent reference model.

Writes build/physics-sweep.json and fails when any violation is found.
"""
import json
import multiprocessing
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tests'), str(ROOT/'tools')]

POWERS = (4, 12, 22, 32)


def course(hole):
    return json.loads(sorted((ROOT/'assets/courses').glob('*.json'))[hole].read_text())


def starts(hole, spacing):
    from physics_check import start_points
    geometry = course(hole)
    return [tuple(geometry['start'])]+start_points(geometry, spacing)


def sweep(job):
    """One hole and a slice of its start points (keeps all cores busy)."""
    hole, stride, spacing, first, last = job
    from test_runtime import Runtime
    from physics_check import Monitor, Report, place
    geometry = course(hole)
    r = Runtime('minigolf')
    r.put('HOLE', hole)
    r.call('initialise_video')
    r.call('initialise_state')
    r.call('draw_course')          # water is found by the cell colour
    snapshot = list(r.bus)
    report = Report()
    monitor = Monitor(r, geometry, report)
    for x, y in starts(hole, spacing)[first:last]:
        for angle in range(0, 128, stride):
            for power in POWERS:
                r.bus[:] = snapshot
                place(r, x, y)
                monitor.shot(angle, power, (hole+1, x, y))
    return hole, report, last-first


def main():
    holes = [int(h)-1 for h in os.environ.get('HOLES', '').split()] or list(range(18))
    stride = int(os.environ.get('STRIDE', 4))
    spacing = int(os.environ.get('SPACING', 16))
    jobs = []
    for hole in holes:
        count = len(starts(hole, spacing))
        jobs += [(hole, stride, spacing, first, min(count, first+8)) for first in range(0, count, 8)]
    from physics_check import Report
    by_hole = {}
    with multiprocessing.Pool() as pool:
        for done, (hole, report, count) in enumerate(pool.imap_unordered(sweep, jobs), 1):
            merged, total_starts = by_hole.get(hole, (Report(), 0))
            merged.merge(report)
            by_hole[hole] = (merged, total_starts+count)
            print(f'  {done}/{len(jobs)} slices', end='\r', flush=True)
    print()
    total = Report()
    per_hole = {}
    for hole, (report, count) in sorted(by_hole.items()):
        total.merge(report)
        per_hole[hole+1] = {'starts': count, 'shots': report.shots, 'frames': report.frames,
                            'peak_cycles': report.peak_cycles[0], 'violations': len(report.violations)}
        print(f'hole {hole+1:2d}: {count:3d} starts, {report.shots:6d} shots, {report.frames:8d} frames, '
              f'peak {report.peak_cycles[0]} cycles, {len(report.violations)} violations')
    kinds = {}
    for kind, _ in total.violations:
        kinds[kind] = kinds.get(kind, 0)+1
    result = {
        'stride': stride, 'spacing': spacing, 'powers': POWERS,
        'shots': total.shots, 'frames': total.frames,
        'frame_classes': total.counts,
        'contacts_per_frame': {str(k): v for k, v in sorted(total.contacts.items())},
        'worst_deviation': {k: {'position_px': round(v[0], 4), 'direction_deg': round(v[1], 3),
                                'speed_units': round(v[2], 3)} for k, v in sorted(total.worst.items())},
        'peak_cycles': total.peak_cycles[0], 'peak_case': repr(total.peak_cycles[1]),
        'violations_by_kind': kinds, 'violations': [repr(v) for v in total.violations[:200]],
        'holes': per_hole,
    }
    (ROOT/'build').mkdir(exist_ok=True)
    (ROOT/'build/physics-sweep.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f"{total.shots} shots, {total.frames} frames; worst deviation by class:")
    for k, v in result['worst_deviation'].items():
        print(f'  {k:7s} {v}')
    print(f'peak physics frame {total.peak_cycles[0]} cycles at {total.peak_cycles[1]}')
    if total.violations:
        print(f'VIOLATIONS {kinds}; first: {total.violations[:5]}')
        raise SystemExit(1)
    print('no violations')


if __name__ == '__main__':
    main()
