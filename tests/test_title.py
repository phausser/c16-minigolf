"""Title menu, hole previews and the start of a round in the game build."""
import json
import unittest

from test_runtime import ROOT, Runtime

COURSES = [json.loads(p.read_text()) for p in sorted((ROOT/'assets/courses').glob('*.json'))]
UP, DOWN, LEFT, RIGHT, FIRE = 1, 2, 4, 8, 16


def preview_quantize(pixel, axis):
    """2px units / 10. Y starts at the playfield edge, pixel 8."""
    unit = pixel // 2
    if axis == 'y':
        if unit < 4:
            return 0
        unit -= 4
        limit = 7
    else:
        limit = 15
    return min(unit // 10, limit)


def preview_line(x0, y0, x1, y1):
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    while True:
        yield x0, y0
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def preview_bitmap(course):
    """16x8 picture as src/title.asm draws it: outline only, playable
    interior cleared (black), set bits left at $ff (the cell's floor
    colour). Crossings are the first pixel of each edge row except ymax;
    each row is filled between sorted pairs, including both ends."""
    stroke = set()
    crossings = [[] for _ in range(8)]
    outline = course['outline']
    for a, b in zip(outline, outline[1:] + outline[:1]):
        x0, y0 = preview_quantize(a[0], 'x'), preview_quantize(a[1], 'y')
        x1, y1 = preview_quantize(b[0], 'x'), preview_quantize(b[1], 'y')
        ymax = max(y0, y1)
        seen = None
        for x, y in preview_line(x0, y0, x1, y1):
            stroke.add((x, y))
            if y != ymax and y != seen:
                crossings[y].append(x)
                seen = y
    bitmap = [0xff] * 16

    def clear(x, y):
        bitmap[(x // 8) * 8 + y] &= 0xff ^ (0x80 >> (x % 8))

    for x, y in stroke:
        clear(x, y)
    for y, row in enumerate(crossings):
        row.sort()
        for index in range(0, len(row) - 1, 2):
            for x in range(row[index], row[index + 1] + 1):
                clear(x, y)
    return bitmap


class TitleTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime('minigolf')
        self.S = self.r.S
        self.r.call('initialise_video')
        self.assertEqual(self.r.call_until('title_screen', 'title_loop'), self.S['title_loop'])
        self.floor = self.r.get('solid_code')

    def press(self, mask, times=1):
        for _ in range(times):
            self.r.frames(mask, 2)
            self.r.frames(0, 2)

    def block(self, hole):
        blocks = self.S['PREVIEW_BLOCKS']
        base = self.S['CHARSET_BASE']+(self.S['PREVIEW_CHAR']+(hole % blocks)*2)*8
        return self.r.bus[base:base+16]

    def code(self, row, column):
        return self.r.bus[self.S['SCREEN_BASE']+row*40+column]

    def holes_text(self):
        """Row 16 from column 6 is the course line. A gap left as floor
        reads as a space. Row 18 from column 19 is the arrows and the four
        pictures (each two cells, shown as ?)."""
        names = {0: ' ', self.floor: ' ', self.S['DASH_CHAR']: '-'}
        names.update({self.S['DIGIT_CHAR'] + digit: str(digit) for digit in range(10)})
        base = self.S['SCREEN_BASE'] + 16 * 40 + 6
        label = ''.join(names.get(code, '?') for code in self.r.bus[base:base + 26])
        return label, self.r.screen_text(18, 19, 15, self.floor)

    @staticmethod
    def holes_expected(first):
        label = '1-18 1-9 10-18' + ''.join(
            f' {first + slot + 1:2d}' for slot in range(4))
        picture = [' '] * 15
        picture[0] = '<' if first else ' '
        picture[14] = '>' if first + 4 < len(COURSES) else ' '
        for slot in range(4):
            start = 2 + 3 * slot          # picture's left cell, from column 19
            picture[start:start + 2] = '??'
        return label, ''.join(picture)

    def text(self, row, column, count):
        letters = 'MINGOLFPAYRCTESUBD'
        names = {self.S[f'LETTER_{c}']: c for c in letters}
        names[self.S['DASH_CHAR']] = '-'
        names.update({self.S['DIGIT_CHAR']+digit: str(digit) for digit in range(10)})
        names[0] = ' '
        base = self.S['SCREEN_BASE']+row*40+column
        return ''.join(names.get(code, '?') for code in self.r.bus[base:base+count])

    def test_picture_header_figures_and_first_holes(self):
        S = self.S
        self.assertEqual(self.text(4, 16, 8), 'MINIGOLF')
        self.assertEqual(self.text(13, 8, 24), 'BETON  GRAS  ERDE  GUMMI')
        self.assertEqual(self.holes_text()[0], '1-18 1-9 10-18  1  2  3  4')
        self.assertEqual(self.text(20, 18, 4), 'PLAY')
        # Bits 7-6 are the ECM paper: black, red, blue, yellow per seat.
        papers = {13: 0, 15: 0, 16: 1, 18: 0, 19: 1, 20: 2, 22: 0, 23: 1, 24: 2, 25: 3}
        floor = (7 << 4) + 5
        for column in range(6, 34):
            self.assertEqual(self.r.bus[S['ATTR_BASE']+16*40+column], floor, column)
            self.assertEqual(self.r.bus[S['ATTR_BASE']+18*40+column], floor, column)
        for column in range(40):
            got = (self.code(9, column), self.code(10, column))
            if column in papers:
                base = (papers[column] << 6) | S['FIGURE_CHAR']
                self.assertEqual(got, (base, base+1), column)
                attr = S['ATTR_BASE']+column
                self.assertEqual(self.r.bus[attr+9*40], floor, column)
                self.assertEqual(self.r.bus[attr+10*40], floor, column)
            else:
                self.assertTrue(all(code < 64 for code in got), (column, got))
                glyphs = [code & 0x3f for code in got]
                self.assertNotIn(S['FIGURE_CHAR'], glyphs, column)
                self.assertNotIn(S['FIGURE_CHAR']+1, glyphs, column)
        # Row 11 between the walls (columns 5 to 33). Row 15 is the gap
        # between the surface and the course line.
        self.assertEqual(self.r.screen_text(11, 5, 29, self.floor), ' '*8+'*'+' '*20)
        self.assertEqual(self.r.screen_text(15, 5, 29, self.floor), ' '*29)
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        # Defaults stay marked: hollow cursor under one golfer, filled
        # balls under Gras and 1-18.
        self.assertEqual(self.code(11, 13), S['BALL_CHAR'])
        self.assertEqual(self.code(14, 16), S['PICK_CHAR'])
        self.assertEqual(self.code(17, 7), S['PICK_CHAR'])
        pick = S['CHARSET_BASE']+S['PICK_CHAR']*8
        filled = [0b00111000, 0b01111100, 0b01111100, 0b01111100, 0b00111000]
        self.assertEqual(self.r.bus[pick:pick+8],
                         [255]+[bits ^ 255 for bits in filled]+[255, 255])
        self.assertEqual(self.r.get('pattern_overflow'), 0)
        for slot in range(4):
            for column in range(2):
                column_x = 21+3*slot+column
                self.assertEqual(self.code(18, column_x),
                                 S['PREVIEW_CHAR']+slot*2+column)
                self.assertEqual(self.r.bus[S['ATTR_BASE']+18*40+column_x], floor)
        for hole in range(5):                  # four shown, the next one ready
            self.assertEqual(self.block(hole), preview_bitmap(COURSES[hole]), hole)
        # The title glyphs are black on the light green floor.
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], (7 << 4) + 5)
        self.assertEqual(self.r.bus[S['ATTR_BASE']] & 0x7f, (3 << 4) + 5)
        glyph = S['CHARSET_BASE']+(S['DIGIT_CHAR']+1)*8
        image = S['font_image']+(S['DIGIT_CHAR']+1)*5-5
        self.assertEqual(self.r.bus[glyph:glyph+8],
                         [255]+[b ^ 255 for b in self.r.bus[image:image+5]]+[255, 255])

    def test_ecm_covers_only_the_figure_rows(self):
        """The raster mock advances one line per read. ECM goes on at
        ECM_ON_LINE. Papers are black until SHIRT_LINE, then the three
        figure colours, then black again at LEGS_LINE. A call that
        already passed ECM_ON_LINE waits for the next frame instead of
        enabling ECM mid-screen. The legs wait consumes its line, so
        when LEGS_LINE and ECM_OFF_LINE are the same the off wait's
        read is the next mock line."""
        bus = self.r.bus
        inks = [bus[self.S['player_inks'] + 1 + index] for index in range(3)]
        on, shirt, legs, off = (self.S['ECM_ON_LINE'], self.S['SHIRT_LINE'],
                                self.S['LEGS_LINE'], self.S['ECM_OFF_LINE'])
        off_line = off if off != legs else (legs + 1) % 312 & 255

        def papers(line, values):
            return [(0xff16 + index, values[index], line) for index in range(3)]

        expected = ([(0xff06, 0x5b, on)] + papers(on, (0, 0, 0))
                    + papers(shirt, inks) + papers(legs, (0, 0, 0))
                    + [(0xff06, 0x1b, off_line)] + papers(off_line, inks))
        bus.watch = []
        self.r.call('title_figure_colors')
        writes = [(addr, value, line) for addr, value, line in bus.watch
                  if addr in (0xff06, 0xff16, 0xff17, 0xff18)]
        self.assertEqual(writes, expected)
        self.assertEqual(bus[0xff06], 0x1b)
        self.assertEqual([bus[0xff16], bus[0xff17], bus[0xff18]], inks)
        bus.raster = 99                 # the next read returns line 100
        bus.watch = []
        self.r.call('title_figure_colors')
        writes = [(addr, value, line) for addr, value, line in bus.watch
                  if addr in (0xff06, 0xff16, 0xff17, 0xff18)]
        self.assertEqual(writes, expected)
        self.assertEqual(bus[0xff06], 0x1b)

    def test_a_choice_keeps_its_filled_ball(self):
        """Leaving a row turns the cursor into a filled ball. A surface
        repaint draws the pictures again and has to put that ball back,
        including one parked under a hole number."""
        S = self.S
        self.press(RIGHT)                     # two players
        self.press(DOWN)
        self.assertEqual(self.code(11, 15), S['PICK_CHAR'])
        self.assertEqual(self.code(11, 13), S['BLANK_CHAR'])
        self.assertEqual(self.code(14, 16), S['BALL_CHAR'])
        self.press(DOWN)
        self.press(RIGHT, 4)                  # hole 2, still in the first window
        self.assertEqual(self.r.get('course_pick'), 4)
        self.assertEqual(self.code(17, 25), S['BALL_CHAR'])
        self.assertEqual(self.code(17, 7), S['BLANK_CHAR'])
        self.press(UP)
        self.assertEqual(self.code(17, 25), S['PICK_CHAR'])
        self.assertEqual(self.code(14, 16), S['BALL_CHAR'])
        self.press(RIGHT)                     # Erde, whole title redrawn
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], (7 << 4) + 9)
        self.assertEqual(self.code(17, 25), S['PICK_CHAR'])
        self.assertEqual(self.code(11, 15), S['PICK_CHAR'])
        self.assertEqual(self.code(14, 22), S['BALL_CHAR'])
        self.assertEqual(self.code(16, 25), S['DIGIT_CHAR'] + 2)
        self.press(UP)
        self.assertEqual(self.code(11, 15), S['BALL_CHAR'])
        self.assertEqual(self.code(14, 22), S['PICK_CHAR'])
        self.assertEqual(self.code(17, 25), S['PICK_CHAR'])

    def test_ball_moves_and_holes_slide_without_redrawing_shown_ones(self):
        S = self.S
        grass = (7 << 4) + 5
        self.press(RIGHT, 5)
        self.assertEqual(self.r.get('menu_players'), 3)
        self.assertEqual(self.code(11, 23), S['BALL_CHAR'])
        self.assertEqual(self.code(11, 13), S['BLANK_CHAR'])
        self.press(DOWN)
        self.assertEqual(self.r.get('menu_row'), 1)
        self.assertEqual(self.code(14, 16), S['BALL_CHAR'])
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], grass)
        self.press(RIGHT)
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], (7 << 4) + 9)
        self.press(RIGHT)
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], (7 << 4) + 2)
        self.press(LEFT, 2)
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], grass)
        self.press(LEFT)
        self.assertEqual(self.r.bus[S['ATTR_BASE']+4*40+16], (5 << 4) + 1)
        self.press(RIGHT)
        self.press(DOWN)
        self.assertEqual(self.r.get('course_pick'), 0)
        self.assertEqual(self.code(17, 7), S['BALL_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        # 1-18, 1-9, 10-18, then holes 1 to 4. Three more steps reach hole 4,
        # still inside the first window. The next step slides.
        self.press(RIGHT, 3)
        self.assertEqual(self.code(17, 22), S['BALL_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        self.press(RIGHT, 3)
        self.assertEqual(self.r.get('window_first'), 0)
        self.assertEqual(self.r.get('practice_hole'), 3)
        shown = [self.block(hole) for hole in (1, 2, 3)]
        self.press(RIGHT)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (4, 1))
        self.assertEqual([self.block(hole) for hole in (1, 2, 3)], shown)
        self.assertEqual(self.block(5), preview_bitmap(COURSES[5]))   # ready ahead
        self.assertEqual(self.holes_text(), self.holes_expected(1))
        self.assertEqual(self.code(17, 31), S['BALL_CHAR'])
        self.press(RIGHT, 20)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (17, 14))
        self.assertEqual(self.holes_text(), self.holes_expected(14))
        for hole in range(14, 18):
            self.assertEqual(self.block(hole), preview_bitmap(COURSES[hole]), hole)
        # Turning round: the hole left of the row is drawn into a block that
        # is not shown, the shown ones stay as they are.
        self.press(LEFT, 3)
        shown = [self.block(hole) for hole in (15, 16)]
        self.press(LEFT)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (13, 13))
        self.assertEqual([self.block(hole) for hole in (15, 16)], shown)
        self.assertEqual(self.block(13), preview_bitmap(COURSES[13]))
        self.assertEqual(self.block(12), preview_bitmap(COURSES[12]))  # ready ahead
        self.assertEqual(self.holes_text(), self.holes_expected(13))
        self.press(LEFT, 13)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (0, 0))
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        self.press(LEFT)
        self.assertEqual(self.r.get('course_pick'), 2)
        self.assertEqual(self.code(17, 17), S['BALL_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        self.press(UP)
        self.press(UP)
        self.press(UP)
        self.assertEqual(self.r.get('menu_row'), 0)
        self.assertEqual(self.code(11, 23), S['BALL_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0))

    def start(self):
        self.r.bus.joysticks = [FIRE, 0]
        for _ in range(20000000):
            if self.r.cpu.pc == self.S['main_loop']:
                return
            self.r.cpu.step()
        self.fail('the round did not start')

    def test_fire_on_play_starts_the_round_with_the_game_charset(self):
        S = self.S
        self.press(RIGHT)
        self.press(DOWN, 3)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('player_count', 'player', 'HOLE', 'hole_last')],
                         [2, 0, 0, 18])
        self.assertEqual((self.r.get('intern_base'), self.r.get('intern_limit')),
                         (S['COURSE_CHAR'], S['COURSE_CHAR_LIMIT']))
        blank = S['CHARSET_BASE']+S['BLANK_CHAR']*8
        self.assertEqual(self.r.bus[blank:blank+8], [0]*8)
        self.r.call('draw_status')
        self.r.assert_status(self, 1, 0, COURSES[0]['par'], 1)
        self.assertEqual(self.r.bus[0xff06], 0x1b)

    def test_preview_ignores_obstacles(self):
        """Contour 0 is the outline. A hole with an obstacle keeps a
        shorter prefix; a hole without one uses every segment."""
        self.r.cpu.x = 0
        self.r.call('decode_course')
        self.assertEqual(self.r.get('outline_bytes'), self.r.get('SEGMENT_BYTES'))
        self.assertGreater(self.r.get('outline_bytes'), 0)
        self.r.cpu.x = 8
        self.r.call('decode_course')
        self.assertGreater(self.r.get('SEGMENT_BYTES'), self.r.get('outline_bytes'))
        self.assertGreater(self.r.get('outline_bytes'), 0)

    def test_fire_away_from_play_stays_on_the_menu(self):
        self.press(FIRE)
        self.assertEqual(self.r.cpu.pc, self.S['title_loop'])
        self.assertEqual(self.r.get('menu_row'), 0)

    def test_ranges_and_one_hole_set_the_round(self):
        self.press(DOWN, 2)
        self.press(RIGHT)
        self.press(DOWN)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('HOLE', 'hole_last', 'player_count')], [0, 9, 1])

    def test_back_nine_starts_at_hole_ten(self):
        self.press(DOWN, 2)
        self.press(RIGHT, 2)
        self.press(DOWN)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('HOLE', 'hole_last')], [9, 18])

    def test_fire_on_a_hole_plays_only_that_hole(self):
        self.press(DOWN, 2)
        self.press(RIGHT, 9)          # three ranges, then hole 7 (index 6)
        self.press(DOWN)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('player_count', 'HOLE', 'hole_last')], [1, 6, 7])


if __name__ == '__main__':
    unittest.main()
