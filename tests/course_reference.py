"""Independent model of the static course picture (bitmap and colors).

Cells of rows 1..20 are whole floor, inner 45-degree edge (floor and solid)
or solid. Floor pixels are clear; the solid part of floor and edge cells is
black. Each edge cell repeats its floor pattern, as black pixels cut to
FRAME_WIDTH on the far side, in the solid neighbour towards its solid side
horizontally and vertically: the smooth outer frame edge. Such outer
cells also get the bands below towards orthogonal whole floor cells, so a
straight frame meets a slope closed. Other solid cells next to a whole floor cell
(8-neighbourhood) get a black band of FRAME_WIDTH pixels on each side that
faces such a cell, square at corners. The cup is a round 7-pixel
hole, shadowed inside at the top left. Cells with floor are gray with black
ink, other playfield cells black ink on the green checker, rows 0 and 21..23 equal checker colors, row 24
the HUD palette. Water areas are whole floor cells with black ink on a
blue checker. Row 24 is entirely the HUD palette.
"""

FRAME_WIDTH = 6


def bitmap_offset(x, y):
    return (y//8)*320+(x//8)*8+(y%8)


def attribute(foreground, background):
    return ((background & 0x70) + ((foreground & 0x70) >> 4),
            ((foreground & 15) << 4) + (background & 15))


def render(course, s):
    contours = [course['outline'], *course['obstacles']]

    def playable(x, y):
        inside = False
        for contour in contours:
            for a, b in zip(contour, contour[1:]+contour[:1]):
                if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                    if a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]) <= x:
                        inside = not inside
        return inside

    def pixels(row, col):
        return [(col*8+dx, row*8+dy) for dy in range(8) for dx in range(8)]

    black = set()
    classes = {}
    for row in range(1, 21):
        for col in range(40):
            cell = [playable(x, y) for x, y in pixels(row, col)]
            classes[row, col] = 'floor' if all(cell) else 'solid' if not any(cell) else 'edge'
            black |= {p for p, floor in zip(pixels(row, col), cell)
                      if not floor and any(cell)}
    for row in range(1, 21):
        for col in range(40):
            if classes[row, col] != 'edge':
                continue
            right = not playable(col*8+7, row*8+4)
            up = not playable(col*8+4, row*8)
            for dr, dc in ((0, 1 if right else -1), (-1 if up else 1, 0)):
                if classes.get((row+dr, col+dc)) in ('solid', 'outer'):
                    classes[row+dr, col+dc] = 'outer'
                    for x, y in pixels(row, col):
                        dx, dy = x-col*8, y-row*8
                        # Cut to the frame width on the side away from the floor.
                        far = (dc > 0 and dx >= FRAME_WIDTH) or (dc < 0 and dx < 8-FRAME_WIDTH) or \
                              (dr < 0 and dy < 8-FRAME_WIDTH) or (dr > 0 and dy >= FRAME_WIDTH)
                        if playable(x, y) and not far:
                            black.add((x+dc*8, y+dr*8))
    band = 8-FRAME_WIDTH
    for (row, col), kind in classes.items():
        if kind not in ('solid', 'outer'):
            continue
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if classes.get((row+dr, col+dc)) != 'floor' or (kind == 'outer' and dr and dc):
                    continue
                for x, y in pixels(row, col):
                    dx, dy = x-col*8, y-row*8
                    if ((dc < 0 and dx >= FRAME_WIDTH) or (dc > 0 and dx < band) or
                            (dr < 0 and dy >= FRAME_WIDTH) or (dr > 0 and dy < band)):
                        continue
                    black.add((x, y))
    bitmap = bytearray(8000)
    for x, y in black:
        bitmap[bitmap_offset(x, y)] |= 128 >> (x % 8)
    cx, cy = course['cup']
    for dy, row in zip(range(-3, 4), ('..###..', '.#####.', '####..#', '###...#',
                                      '##....#', '.#...#.', '..###..')):
        for dx, pixel in zip(range(-3, 4), row):
            if pixel == '#':
                bitmap[bitmap_offset(cx+dx, cy+dy)] |= 128 >> ((cx+dx) % 8)
    water = {(row, col) for x1, y1, x2, y2 in course.get('hazards', [])
             for row in range(y1//8, y2//8) for col in range(x1//8, x2//8)}
    hud = attribute(s['HUD_FOREGROUND_COLOR'], s['HUD_BACKGROUND_COLOR'])
    luminance, color = [hud[0]]*1024, [hud[1]]*1024
    for row in range(24):
        for col in range(40):
            checker = s['CHECKER_COLOR_ODD'] if (row+col) % 2 else s['CHECKER_COLOR_EVEN']
            kind = classes.get((row, col))
            if kind in ('floor', 'edge'):
                pair = attribute(s['COURSE_MARKER_COLOR'], s['COURSE_SURFACE_COLOR'])
            elif kind:
                pair = attribute(s['COURSE_FRAME_COLOR'], checker)
            else:
                pair = attribute(checker, checker)
            if (row, col) in water:
                pair = attribute(s['COURSE_MARKER_COLOR'],
                                 s['WATER_COLOR_ODD'] if (row+col) % 2 else s['WATER_COLOR_EVEN'])
            luminance[row*40+col], color[row*40+col] = pair
    return bitmap, luminance, color


def legacy_picture(bus, s):
    """Rebuild the old hi-res bitmap and split colour matrices from text mode.

    Rows 1..20 store inverted glyphs (set bit was black). Rows 0 and 21..23
    ignore the glyph and use one checker colour for both planes. Row 24 keeps
    the ROM/bar glyph and a black background. Floor and the hidden rows can
    share the solid glyph; the row number tells them apart.
    """
    bitmap = bytearray(8000)
    luminance, color = [0]*1024, [0]*1024
    for row in range(25):
        for col in range(40):
            cell = row*40+col
            code = bus[s['SCREEN_BASE']+cell]
            glyph = bytes(bus[s['CHARSET_BASE']+code*8:s['CHARSET_BASE']+code*8+8])
            ink = bus[s['ATTR_BASE']+cell] & 0x7f
            if row == 24:
                cell_bytes, fg, bg = glyph, ink, 0
            elif row == 0 or row >= 21:
                cell_bytes, fg, bg = bytes(8), ink, ink
            else:
                cell_bytes, fg, bg = bytes(b ^ 0xff for b in glyph), 0, ink
            bitmap[row*320+col*8:row*320+col*8+8] = cell_bytes
            luminance[cell], color[cell] = attribute(fg, bg)
    return bitmap, luminance, color


def static_patterns(course):
    """Unique text-mode glyphs of one course, including the solid checker cell."""
    dummy = {name: 0 for name in (
        'HUD_FOREGROUND_COLOR', 'HUD_BACKGROUND_COLOR', 'CHECKER_COLOR_ODD',
        'CHECKER_COLOR_EVEN', 'COURSE_MARKER_COLOR', 'COURSE_SURFACE_COLOR',
        'COURSE_FRAME_COLOR', 'WATER_COLOR_ODD', 'WATER_COLOR_EVEN')}
    bitmap, _, _ = render(course, dummy)
    patterns = {bytes([0xff]*8)}
    for row in range(1, 21):
        for col in range(40):
            base = row*320+col*8
            patterns.add(bytes(bitmap[base+i] ^ 0xff for i in range(8)))
    return patterns
