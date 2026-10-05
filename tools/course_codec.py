"""Lossless packed course geometry, decoded at runtime by decode_course.

Version 2 stream: start x/2, start y/2, cup x/2, cup y/2, contour count,
then per contour: first vertex x/2, y/2 with bit 7 = normal side flag,
run count and runs. A run byte has a 3-bit compass direction and a 5-bit
length in 2px units (zero means 32). Longer edges use repeated runs;
decoding merges them back into one segment. The side flag is set when the
wall normal is direction+2 (outline: positive area, obstacle: negative).
Names, par and material data are deliberately outside this version.
"""
import argparse
import json
from pathlib import Path

from generate_assets import ROOT, DIRECTIONS, validate


def encode(course):
    validate(course)
    for key in ('start','cup'):
        point = course[key]
        if len(point) != 2 or any(type(v) is not int or v % 2 for v in point):
            raise ValueError(f'{key} must use the two-pixel integer grid')
        if not (0 <= point[0] < 320 and 0 <= point[1] < 168):
            raise ValueError(f'{key} outside playfield')
    contours = [course['outline'], *course['obstacles']]
    data = bytearray([*(v//2 for v in course['start']),
                      *(v//2 for v in course['cup']), len(contours)])
    for ci,contour in enumerate(contours):
        area = sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(contour,contour[1:]+contour[:1]))
        side = 128 if (area > 0) == (ci == 0) else 0
        runs = bytearray()
        for a,b in zip(contour,contour[1:]+contour[:1]):
            dx,dy = b[0]-a[0],b[1]-a[1]
            direction = DIRECTIONS.index(((dx>0)-(dx<0),(dy>0)-(dy<0)))
            length = max(abs(dx),abs(dy))//2
            while length:
                chunk = min(length,32)
                runs.append(direction*32+(chunk & 31))
                length -= chunk
        if len(runs) > 255:
            raise ValueError('contour has too many runs')
        data.extend([contour[0][0]//2,contour[0][1]//2 | side,len(runs)])
        data.extend(runs)
    if len(data) > 256:
        raise ValueError('packed course exceeds 256 bytes')
    return bytes(data)


def decode(data):
    index = 0

    def byte():
        nonlocal index
        if index >= len(data):
            raise ValueError('truncated course stream')
        result = data[index]
        index += 1
        return result

    course = {'start':[byte()*2,byte()*2], 'cup':[byte()*2,byte()*2]}
    count = byte()
    if not 1 <= count <= 32:
        raise ValueError('invalid contour count')
    contours = []
    for _ in range(count):
        point = [byte()*2,(byte() & 127)*2]
        contour = [point.copy()]
        run_count = byte()
        if not run_count:
            raise ValueError('empty contour')
        previous = None
        for _ in range(run_count):
            run = byte()
            direction,length = run >> 5,(run & 31) or 32
            if previous is not None and direction != previous:
                contour.append(point.copy())
            dx,dy = DIRECTIONS[direction]
            point[0] += dx*length*2
            point[1] += dy*length*2
            previous = direction
        if point != contour[0]:
            raise ValueError('open contour')
        contours.append(contour)
    if index != len(data):
        raise ValueError('trailing course data')
    course['outline'],course['obstacles'] = contours[0],contours[1:]
    if encode(course) != bytes(data):
        raise ValueError('non-canonical course stream or wrong side flag')
    return course


def budget():
    course = json.loads((ROOT/'assets/test-course.json').read_text())
    data = encode(course)
    assert decode(data) == {key:course[key] for key in ('start','cup','outline','obstacles')}
    memory = json.loads((ROOT/'build/memory.json').read_text())
    # One packed course and its two pointer bytes are already in the runtime,
    # together with decode_course and the current-course buffer.
    directory_bytes = 18*2  # lo/hi pointer tables
    estimated = len(data)*18+directory_bytes
    missing = (len(data)+2)*17
    free = memory['runtime_free_bytes']
    report = {'format_version':2, 'test_course_segments':len(validate(course)),
              'expanded_test_course_bytes':len(validate(course))*5,
              'packed_test_course_bytes':len(data), 'course_count':18,
              'directory_bytes':directory_bytes, 'estimated_geometry_bytes':estimated,
              'remaining_17_courses_bytes':missing,
              'runtime_free_bytes':free, 'additional_bytes_needed':max(0,missing-free),
              'fits_current_runtime':missing <= free,
              'additional_geometry_only_capacity':free//(len(data)+2),
              'assumption':'18 courses with the measured test-course size; not 18 final exports',
              'included':['decode_course','current-course buffer in stack page'],
              'not_included':['names/par','materials','score/effects']}
    (ROOT/'build/test-course.packed').write_bytes(data)
    (ROOT/'build/course-budget.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'Course geometry: {report["expanded_test_course_bytes"]} -> {len(data)} bytes; '
          f'18 courses + directory: {estimated} bytes, {missing} still to place; free: {free}.')
    print(f'Free RAM holds {free//(len(data)+2)} more packed geometries of this size with pointers; '
          'decoder and current-course buffer are already resident; metadata excluded.')
    if missing > free:
        print(f'18-course RAM gate OPEN: geometry needs {missing-free} additional bytes, plus game metadata.')


if __name__ == '__main__':
    argparse.ArgumentParser(description=__doc__).parse_args()
    budget()
