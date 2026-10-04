"""Lossless geometry export for the RAM budget; not yet the ACME decoder.

Coordinates use the existing 2px course grid. A run byte has a 3-bit
compass direction and a 5-bit length (zero means 32 grid units). Longer
edges use repeated runs; decoding merges them back into one segment.
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
    data = bytearray([1, *(v//2 for v in course['start']),
                      *(v//2 for v in course['cup']), len(contours)])
    for contour in contours:
        runs = bytearray()
        for a,b in zip(contour,contour[1:]+contour[:1]):
            dx,dy = b[0]-a[0],b[1]-a[1]
            direction = DIRECTIONS.index(((dx>0)-(dx<0),(dy>0)-(dy<0)))
            length = max(abs(dx),abs(dy))//2
            while length:
                chunk = min(length,32)
                runs.append(direction*32+(chunk & 31))
                length -= chunk
        data.extend([contour[0][0]//2,contour[0][1]//2,len(runs)])
        data.extend(runs)
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

    if byte() != 1:
        raise ValueError('unsupported course version')
    course = {'start':[byte()*2,byte()*2], 'cup':[byte()*2,byte()*2]}
    count = byte()
    if not 1 <= count <= 32:
        raise ValueError('invalid contour count')
    contours = []
    for _ in range(count):
        point = [byte()*2,byte()*2]
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
    validate(course)
    return course


def budget():
    course = json.loads((ROOT/'assets/test-course.json').read_text())
    data = encode(course)
    assert decode(data) == {key:course[key] for key in ('start','cup','outline','obstacles')}
    memory = json.loads((ROOT/'build/memory.json').read_text())
    directory_bytes = 18*2
    estimated = len(data)*18+directory_bytes
    free = memory['runtime_free_bytes']
    report = {'format_version':1, 'test_course_segments':len(validate(course)),
              'expanded_test_course_bytes':len(validate(course))*5,
              'packed_test_course_bytes':len(data), 'course_count':18,
              'directory_bytes':directory_bytes, 'estimated_geometry_bytes':estimated,
              'runtime_free_bytes':free, 'additional_bytes_needed':max(0,estimated-free),
              'fits_current_runtime':estimated <= free,
              'additional_geometry_only_capacity':free//(len(data)+2),
              'assumption':'18 courses with the measured test-course size; not 18 final exports',
              'not_included':['ACME run decoder','current-course fill edges/reserve',
                              'names/par','materials','score/effects']}
    (ROOT/'build/test-course.packed').write_bytes(data)
    (ROOT/'build/course-budget.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'Course geometry: {report["expanded_test_course_bytes"]} -> {len(data)} bytes; '
          f'18-course estimate + directory: {estimated} bytes; free: {free}.')
    print(f'Free RAM would hold at most {free//(len(data)+2)} additional packed geometries '
          'of this size with pointers; excludes decoder/current-course reserve and metadata.')
    if estimated > free:
        print('18-course RAM gate OPEN: geometry alone needs '
              f'{estimated-free} additional bytes, plus decoder and game metadata.')


if __name__ == '__main__':
    argparse.ArgumentParser(description=__doc__).parse_args()
    budget()
