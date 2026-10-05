"""Render all course drafts with the assembled 6502 renderer (py65).

Each course is packed exactly as for the game, decoded and drawn by the real
kernel, then shown with the ball on the tee and its aim towards the cup.
Output: build/courses-preview.png (3 x 6 screens) and the packed sizes.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'tests')]
from course_codec import encode
from test_runtime import Runtime, S

# Approximate TED colors: hue -> RGB at full brightness, scaled by luminance.
HUES = {0: (0, 0, 0), 1: (1, 1, 1), 5: (.35, 1, .35), 6: (.45, .45, 1)}


def rgb(luminance, hue):
    if hue == 0:
        return (0, 0, 0)
    level = .12+luminance*.12
    return tuple(min(255, int(255*level*c)) for c in HUES.get(hue, (1, 0, 1)))


def screen(r):
    """Text mode: a set glyph bit is the cell foreground, a clear bit is black."""
    pixels = []
    for y in range(200):
        row = []
        for x in range(320):
            cell = (y//8)*40+x//8
            code = r.bus[S['SCREEN_BASE']+cell]
            byte = r.bus[S['CHARSET_BASE']+code*8+y % 8]
            ink = r.bus[S['ATTR_BASE']+cell]
            if (byte >> (7-x % 8)) & 1:
                row.append(rgb((ink >> 4) & 7, ink & 15))
            else:
                row.append((0, 0, 0))
        pixels.append(row)
    return pixels


def render(index, course):
    r = Runtime()
    data = encode(course)
    address = 0x8000                 # outside the 16 KB RAM; py65 bus only
    r.bus[S['course_table_lo']] = address & 255
    r.bus[S['course_table_hi']] = address >> 8
    r.bus[address:address+len(data)] = list(data)
    r.call('initialise_state')
    r.call('initialise_video')
    r.call('draw_course')
    r.put('HOLE', index)
    r.call('draw_status')
    dx = course['cup'][0]-course['start'][0]
    dy = course['cup'][1]-course['start'][1]
    r.put('ANGLE', round(math.atan2(dy, dx)/math.tau*128) % 128)
    r.put('DYNAMIC_COUNT', 0)
    r.call('draw_dynamic')
    if r.get('pattern_overflow'):
        raise SystemExit(f'course {index+1} exceeds the 64-character budget')
    return screen(r), len(data), r.get('pattern_count')


def write_png(path, pixels):
    height, width = len(pixels), len(pixels[0])
    raw = b''.join(b'\0'+bytes(c for p in row for c in p) for row in pixels)

    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(raw))+chunk(b'IEND', b''))


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    files = sorted((ROOT/'assets/courses').glob('*.json'))
    gap, columns = 4, 3
    rows = (len(files)+columns-1)//columns
    sheet = [[(40, 40, 40)]*(columns*(320+gap)) for _ in range(rows*(200+gap))]
    total = 0
    for i, path in enumerate(files):
        course = json.loads(path.read_text())
        pixels, size, chars = render(i, course)
        total += size
        print(f"{i+1:2} {course['name']:28} par {course['par']}  {size:3} bytes  {chars:2}/64 Zeichen")
        top, left = (i//columns)*(200+gap), (i % columns)*(320+gap)
        for y, row in enumerate(pixels):
            sheet[top+y][left:left+320] = row
    output = ROOT/'build/courses-preview.png'
    write_png(output, sheet)
    print(f'{len(files)} courses, {total} packed bytes; preview: {output}')


if __name__ == '__main__':
    main()
