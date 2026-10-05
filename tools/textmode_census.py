"""Feasibility census for a TED text-mode renderer (docs/textmode-plan.md).

Renders every course with the real bitmap kernel (py65) and asks, per 8x8
cell of rows 0..23, whether it fits text mode with a global black
background: at most one non-black color. The non-black pixels form the
character pattern; the census counts distinct patterns per course.
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'tests')]
from course_codec import encode
from test_runtime import Runtime, S


def census(course):
    r = Runtime()
    data = encode(course)
    r.bus[S['course_table_lo']], r.bus[S['course_table_hi']] = 0x00, 0x80
    r.bus[0x8000:0x8000+len(data)] = list(data)
    r.call('initialise_state')
    r.call('initialise_video')
    r.call('draw_course')
    patterns, colors, conflicts = set(), set(), 0
    for cell in range(24*40):
        luminance, color = r.bus[0x1800+cell], r.bus[0x1c00+cell]
        fg = ((luminance & 7) << 4) | (color >> 4)
        bg = (luminance & 0x70) | (color & 15)
        base = 0x2000+(cell//40)*320+(cell % 40)*8
        rows = r.bus[base:base+8]
        if fg & 15 and bg & 15 and fg != bg:
            conflicts += 1
            continue
        if fg == bg:
            rows, ink = [255]*8, fg               # hidden rows: one color
        elif fg & 15 == 0:
            rows, ink = [b ^ 255 for b in rows], bg   # ink = the non-black background
        else:
            ink = fg
        patterns.add(tuple(rows))
        colors.add(ink)
    return len(patterns), len(colors), conflicts


def main():
    worst = 0
    for path in sorted((ROOT/'assets/courses').glob('*.json')):
        course = json.loads(path.read_text())
        count, inks, conflicts = census(course)
        worst = max(worst, count)
        print(f"{path.stem} {course['name']:28} {count:3} chars, {inks} inks, {conflicts} two-color cells")
    print(f'worst course: {worst} distinct static characters')


if __name__ == '__main__':
    main()
