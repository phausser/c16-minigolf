"""Independent pixel model of the static course picture (bitmap and colors).

Floor pixels are clear, everything else set. Cells: floor, inner 45-degree
edge (floor and solid), solid. An inner edge repeats its pattern one cell
further out towards its solid side, horizontally and vertically: the outer
frame edge (black/green). Remaining solid cells touching a floor cell
(8-neighbourhood) form the black frame; all other cells of rows 0..23 show
the green checker. Row 24 keeps the HUD palette.
"""
import math


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

    bitmap = bytearray(8000)
    for y in range(8, 168):
        for x in range(320):
            if not playable(x, y):
                bitmap[bitmap_offset(x, y)] |= 128 >> (x % 8)
    classes = {}
    for row in range(1, 21):
        for col in range(40):
            cell = [playable(x, y) for y in range(row*8, row*8+8)
                    for x in range(col*8, col*8+8)]
            classes[row, col] = 'floor' if all(cell) else 'solid' if not any(cell) else 'edge'
    for row in range(1, 21):
        for col in range(40):
            if classes[row, col] != 'edge':
                continue
            right = not playable(col*8+7, row*8+4)
            up = not playable(col*8+4, row*8)
            for target in ((row, col+(1 if right else -1)), (row+(-1 if up else 1), col)):
                if classes.get(target) == 'solid':
                    classes[target] = 'outer'
                    source = bitmap_offset(col*8, row*8)
                    dest = bitmap_offset(target[1]*8, target[0]*8)
                    bitmap[dest:dest+8] = bitmap[source:source+8]
    for (row, col), kind in list(classes.items()):
        if kind == 'solid' and any(classes.get((row+dy, col+dx)) == 'floor'
                                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
            classes[row, col] = 'frame'
    cx, cy = course['cup']
    for i in range(32):
        x = cx+round(math.cos(i*math.tau/32)*5)
        y = cy+round(math.sin(i*math.tau/32)*5)
        bitmap[bitmap_offset(x, y)] |= 128 >> (x % 8)
    hud = attribute(s['HUD_FOREGROUND_COLOR'], s['HUD_BACKGROUND_COLOR'])
    luminance, color = [hud[0]]*1024, [hud[1]]*1024
    for row in range(24):
        for col in range(40):
            checker = s['CHECKER_COLOR_ODD'] if (row+col) % 2 else s['CHECKER_COLOR_EVEN']
            kind = classes.get((row, col), 'solid')
            if kind in ('floor', 'edge'):
                pair = attribute(s['COURSE_MARKER_COLOR'], s['COURSE_SURFACE_COLOR'])
            elif kind == 'frame':
                pair = attribute(s['COURSE_FRAME_COLOR'], s['COURSE_FRAME_COLOR'])
            elif kind == 'outer':
                pair = attribute(checker, s['COURSE_FRAME_COLOR'])
            else:
                pair = attribute(checker, checker)
            luminance[row*40+col], color[row*40+col] = pair
    return bitmap, luminance, color
