"""Validate the hardware course and emit compact ACME data; no bitmap assets."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DIRECTIONS = [(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)]


def orientation(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])


def intersects(a, b, c, d):
    def on(p, q, r):
        return (min(p[0],q[0]) <= r[0] <= max(p[0],q[0]) and
                min(p[1],q[1]) <= r[1] <= max(p[1],q[1]))
    values = orientation(a,b,c), orientation(a,b,d), orientation(c,d,a), orientation(c,d,b)
    if values[0]*values[1] < 0 and values[2]*values[3] < 0:
        return True
    return any(v == 0 and on(p,q,r) for v,p,q,r in (
        (values[0],a,b,c), (values[1],a,b,d), (values[2],c,d,a), (values[3],c,d,b)))


def playable(contours, x, y):
    """Even-odd rule with half-open y intervals, as the renderer fills."""
    inside = False
    for contour in contours:
        for a, b in zip(contour, contour[1:]+contour[:1]):
            if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                if a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]) <= x:
                    inside = not inside
    return inside


def hazard_cells(course):
    """Cells (row, col) of the water areas: [x1, y1, x2, y2), cell aligned."""
    cells = set()
    for area in course.get('hazards', []):
        x1, y1, x2, y2 = area
        if any(type(v) is not int or v % 8 for v in area) or x1 >= x2 or y1 >= y2:
            raise ValueError('water areas must be nonempty cell-aligned rectangles')
        cells |= {(row, col) for row in range(y1//8, y2//8) for col in range(x1//8, x2//8)}
    return cells


def validate_hazards(course):
    if len(course.get('hazards', [])) > 3:
        raise ValueError('at most three water areas')
    contours = [course['outline'], *course['obstacles']]
    cells = hazard_cells(course)
    for row, col in cells:
        if not all(playable(contours, col*8+dx, row*8+dy) for dy in range(8) for dx in range(8)):
            raise ValueError('water areas must cover whole floor cells')
    for key in ('start', 'cup'):
        x, y = course[key]
        if (y//8, x//8) in cells:
            raise ValueError(f'{key} lies in water')


def validate(course):
    contours = [course['outline'], *course['obstacles']]
    segments = []
    for contour_index, contour in enumerate(contours):
        if len(contour) < 3:
            raise ValueError('contour needs at least 3 distinct vertices')
        area = sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(contour, contour[1:]+contour[:1]))
        if not area:
            raise ValueError('contour has zero area')
        for i, a in enumerate(contour):
            b = contour[(i+1) % len(contour)]
            if any(not isinstance(n, int) or n % 2 for n in a):
                raise ValueError('vertices must use the two-pixel integer grid')
            if not (8 <= a[0] <= 310 and 8 <= a[1] <= 166):
                raise ValueError('vertex outside safe playfield')
            dx,dy = b[0]-a[0], b[1]-a[1]
            if any(n % 8 for n in a):
                raise ValueError('vertices must use the 8x8 cell grid')
            if not (dx or dy) or (dx and dy and abs(dx) != abs(dy)):
                raise ValueError('only nonzero axis-aligned or 45 degree edges supported')
            segments.append((a,b,contour_index,i,len(contour)))
    if len(segments) > 32:
        raise ValueError('course exceeds 32-segment budget')
    if len(contours) > 63:
        raise ValueError('too many contours')
    for i,(a,b,ci,ei,ni) in enumerate(segments):
        for c,d,cj,ej,nj in segments[i+1:]:
            if ci == cj and ((ei-ej) % ni in (1,ni-1)):
                # Adjacent edges may share an endpoint, but may not backtrack.
                if orientation(a,b,c) == orientation(a,b,d) == 0:
                    ux,uy = b[0]-a[0], b[1]-a[1]
                    vx,vy = d[0]-c[0], d[1]-c[1]
                    if ux*vx+uy*vy < 0:
                        raise ValueError('adjacent edges overlap')
                continue
            if intersects(a,b,c,d):
                raise ValueError('nonadjacent edges intersect')
    return segments


def bytes_section(name, values):
    lines = [name + ':']
    values = [v & 255 for v in values]
    for i in range(0,len(values),16):
        lines.append('!byte ' + ','.join(f'${v:02x}' for v in values[i:i+16]))
    return '\n'.join(lines)


def expanded_segments(course):
    """Reference of decode_course's RAM output: x1/2, y1/2, x2/2, y2/2, flags."""
    segments = validate(course)
    encoded = []
    for a,b,ci,*_ in segments:
        dx,dy = b[0]-a[0], b[1]-a[1]
        direction = DIRECTIONS.index(((dx>0)-(dx<0), (dy>0)-(dy<0)))
        contour = [course['outline'], *course['obstacles']][ci]
        area = sum(p[0]*q[1]-p[1]*q[0] for p,q in zip(contour,contour[1:]+contour[:1]))
        normal = (direction + (2 if (area > 0) == (ci == 0) else -2)) % 8
        turn = orientation(contour[contour.index(a)-1], a, b)
        # At a convex playable corner, the two finite walls always contact
        # before the vertex circle. Only exposed solid corners need caps.
        hidden_cap = turn == 0 or ((turn*area > 0) == (ci == 0))
        encoded += [a[0]//2, a[1]//2, b[0]//2, b[1]//2,
                    normal | (0x80 if hidden_cap else 0)]
    return encoded


def generate(test=False):
    import sys
    sys.path.insert(0, str(ROOT/'tests'))
    from course_codec import encode
    from course_reference import static_patterns
    if test:
        courses = [json.loads((ROOT/'assets/test-course.json').read_text())]
    else:
        courses = [json.loads(p.read_text()) for p in sorted((ROOT/'assets/courses').glob('*.json'))]
    packed = [encode(c) for c in courses]
    counts = [len(static_patterns(c)) for c in courses]
    if max(counts) > 64:
        raise SystemExit(f'character budget exceeded: {max(counts)} > 64')
    total_par = sum(c.get('par', 0) for c in courses)
    lines = ['; Generated by tools/generate_assets.py. Do not edit.',
             f'COURSE_COUNT = {len(courses)}', f'TOTAL_PAR = {total_par}']
    for i, data in enumerate(packed):
        lines.append(bytes_section(f'course_data_{i}', data))
    lines.append('course_table_lo:\n!byte ' + ','.join(f'<course_data_{i}' for i in range(len(courses))))
    lines.append('course_table_hi:\n!byte ' + ','.join(f'>course_data_{i}' for i in range(len(courses))))
    lines.append(f'hud_par_text:\n!text "PAR {total_par:<3}",0')
    quarter = [round(math.cos(i*math.tau/128)*256) for i in range(33)]
    lines += [bytes_section('unit_cos_lo',quarter), bytes_section('unit_cos_hi',[v>>8 for v in quarter])]
    ball = [(x,y) for y in range(-2,3) for x in range(-2,3) if x*x+y*y <= 5]
    lines += [f'BALL_POINTS = {len(ball)}']
    suffix = '-test' if test else ''
    (ROOT/'build').mkdir(exist_ok=True)
    (ROOT/f'build/assets{suffix}.inc').write_text('\n\n'.join(lines)+'\n')
    print(f'Assets{suffix}: {len(courses)} packed course(s), {sum(map(len,packed))} bytes, '
          f'characters {min(counts)}..{max(counts)}/64')


if __name__ == '__main__':
    import sys
    generate(test='--test' in sys.argv)
