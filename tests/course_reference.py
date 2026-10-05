"""Independent pixel model of the static course picture (bitmap and colors).

Floor pixels are clear. A non-floor pixel is set (black frame) when a floor
pixel lies within 4 pixels in x and y (9x9 square); all other pixels are
clear. Cells containing floor are gray with black ink; other playfield cells
show black ink on the green checker. Rows 0 and 21..23 use equal checker
colors so hidden data stays invisible; row 24 keeps the HUD palette.
"""
import math


def bitmap_offset(x, y):
    return (y//8)*320+(x//8)*8+(y%8)


def attribute(foreground, background):
    return ((background & 0x70) + ((foreground & 0x70) >> 4),
            ((foreground & 15) << 4) + (background & 15))


def render(course, s, frame=4):
    contours = [course['outline'], *course['obstacles']]

    def playable(x, y):
        inside = False
        for contour in contours:
            for a, b in zip(contour, contour[1:]+contour[:1]):
                if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                    if a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]) <= x:
                        inside = not inside
        return inside

    floor = {(x, y) for y in range(8, 168) for x in range(320) if playable(x, y)}
    near = {(x+dx, y+dy) for x, y in floor
            for dx in range(-frame, frame+1) for dy in range(-frame, frame+1)}
    bitmap = bytearray(8000)
    for x, y in near - floor:
        if 0 <= x < 320 and 8 <= y < 168:
            bitmap[bitmap_offset(x, y)] |= 128 >> (x % 8)
    cx, cy = course['cup']
    for i in range(32):
        x = cx+round(math.cos(i*math.tau/32)*5)
        y = cy+round(math.sin(i*math.tau/32)*5)
        bitmap[bitmap_offset(x, y)] |= 128 >> (x % 8)
    floor_cells = {(y//8, x//8) for x, y in floor}
    hud = attribute(s['HUD_FOREGROUND_COLOR'], s['HUD_BACKGROUND_COLOR'])
    luminance, color = [hud[0]]*1024, [hud[1]]*1024
    for row in range(24):
        for col in range(40):
            checker = s['CHECKER_COLOR_ODD'] if (row+col) % 2 else s['CHECKER_COLOR_EVEN']
            if (row, col) in floor_cells:
                pair = attribute(s['COURSE_MARKER_COLOR'], s['COURSE_SURFACE_COLOR'])
            elif 1 <= row <= 20:
                pair = attribute(s['COURSE_FRAME_COLOR'], checker)
            else:
                pair = attribute(checker, checker)
            luminance[row*40+col], color[row*40+col] = pair
    return bitmap, luminance, color
