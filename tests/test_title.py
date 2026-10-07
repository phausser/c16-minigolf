"""Title menu, hole previews and the start of a round in the game build."""
import json
import unittest

from test_runtime import ROOT, Runtime

COURSES = [json.loads(p.read_text()) for p in sorted((ROOT/'assets/courses').glob('*.json'))]
UP, DOWN, LEFT, RIGHT, FIRE = 1, 2, 4, 8, 16


def preview_bitmap(course):
    """A block as src/title.asm draws it: 1:8, column by column, black
    (cleared) outline and cup on white."""
    points = set()
    for contour in [course['outline'], *course['obstacles']]:
        for a, b in zip(contour, contour[1:]+contour[:1]):
            x, y = a[0]//8-1, a[1]//8-1
            dx, dy = b[0]//8-1-x, b[1]//8-1-y
            for i in range(max(abs(dx), abs(dy))):
                points.add((x+i*((dx > 0)-(dx < 0)), y+i*((dy > 0)-(dy < 0))))
    points.add((course['cup'][0]//8-1, course['cup'][1]//8-1))
    bitmap = [0xff]*120
    for x, y in points:
        bitmap[(x//8)*24+y] &= 0xff ^ (0x80 >> (x % 8))
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
        base = self.S['CHARSET_BASE']+(self.S['PREVIEW_CHAR']+hole % 4*15)*8
        return self.r.bus[base:base+120]

    def code(self, row, column):
        return self.r.bus[self.S['SCREEN_BASE']+row*40+column]

    def holes_text(self):
        """From column 9: rows 15 and 16 (arrows, outline cells as ?) and
        row 18 (ball and numbers)."""
        return tuple(self.r.screen_text(row, 9, 21, self.floor) for row in (15, 16, 18))

    @staticmethod
    def holes_expected(first, ball=None):
        top, middle, below = [' ']*21, [' ']*21, [' ']*21
        middle[0] = '<' if first else ' '
        middle[20] = '>' if first+3 < len(COURSES) else ' '
        for slot in range(3):
            start = 2+6*slot              # the outline's first cell
            top[start:start+5] = middle[start:start+5] = '?????'
            number = str(first+slot+1)
            below[start+5-len(number):start+5] = number
            if ball == first+slot:
                below[start+4-len(number)] = '*'
        return ''.join(top), ''.join(middle), ''.join(below)

    def text(self, row, column, count):
        letters = 'MINGOLFPAYRCTSE'
        names = {self.S[f'LETTER_{c}']: c for c in letters}
        base = self.S['SCREEN_BASE']+row*40+column
        return ''.join(names.get(code, '?') for code in self.r.bus[base:base+count])

    def test_picture_header_figures_and_first_holes(self):
        S = self.S
        self.assertEqual(self.text(4, 16, 8), 'MINIGOLF')
        self.assertEqual(self.text(6, 18, 4), 'PLAY')
        self.assertEqual(self.text(13, 16, 8), 'PRACTISE')
        figures = [13, 15, 16, 18, 19, 20, 22, 23, 24, 25]
        for column in range(40):
            want = (S['FIGURE_CHAR'], S['FIGURE_CHAR']+1) if column in figures else None
            got = (self.code(8, column), self.code(9, column))
            if want:
                self.assertEqual(got, want, column)
            else:
                self.assertNotIn(S['FIGURE_CHAR'], got, column)
        self.assertEqual(self.r.screen_text(10, 2, 36, self.floor), ' '*11+'*'+' '*24)
        self.assertEqual(self.holes_text(), self.holes_expected(0))
        self.assertEqual(self.r.get('pattern_overflow'), 0)
        for slot in range(3):
            for column in range(5):
                for row in range(3):
                    self.assertEqual(self.code(15+row, 11+6*slot+column),
                                     S['PREVIEW_CHAR']+slot*15+column*3+row)
        for hole in range(4):                  # three shown, the next one ready
            self.assertEqual(self.block(hole), preview_bitmap(COURSES[hole]), hole)
        # The title glyphs are black on the white floor.
        glyph = S['CHARSET_BASE']+(S['DIGIT_CHAR']+1)*8
        image = S['FONT_STORE']+(S['DIGIT_CHAR']+1)*5-5   # the load image is gone
        self.assertEqual(self.r.bus[glyph:glyph+8],
                         [255]+[b ^ 255 for b in self.r.bus[image:image+5]]+[255, 255])

    def test_ball_moves_and_holes_slide_without_redrawing_shown_ones(self):
        S = self.S
        self.press(RIGHT, 5)
        self.assertEqual(self.r.get('menu_players'), 3)
        self.assertEqual(self.code(10, 23), S['BALL_CHAR'])
        self.assertEqual(self.code(10, 13), S['BLANK_CHAR'])
        self.press(DOWN)
        self.assertEqual(self.r.get('menu_row'), 1)
        self.assertEqual(self.code(10, 23), S['BLANK_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0, 0))
        self.press(RIGHT, 2)
        self.assertEqual(self.r.get('window_first'), 0)
        shown = [self.block(hole) for hole in (1, 2, 3)]
        self.press(RIGHT)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (3, 1))
        self.assertEqual([self.block(hole) for hole in (1, 2, 3)], shown)
        self.assertEqual(self.block(4), preview_bitmap(COURSES[4]))   # ready ahead
        self.assertEqual(self.holes_text(), self.holes_expected(1, 3))
        self.press(RIGHT, 20)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (17, 15))
        self.assertEqual(self.holes_text(), self.holes_expected(15, 17))
        for hole in range(14, 18):
            self.assertEqual(self.block(hole), preview_bitmap(COURSES[hole]), hole)
        # Turning round: the hole left of the row is drawn into a block that
        # is not shown, the shown ones stay as they are.
        self.press(LEFT, 2)
        shown = [self.block(hole) for hole in (15, 16)]
        self.press(LEFT)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (14, 14))
        self.assertEqual([self.block(hole) for hole in (15, 16)], shown)
        self.assertEqual(self.block(14), preview_bitmap(COURSES[14]))
        self.assertEqual(self.block(13), preview_bitmap(COURSES[13]))  # ready ahead
        self.assertEqual(self.holes_text(), self.holes_expected(14, 14))
        self.press(LEFT, 20)
        self.assertEqual((self.r.get('practice_hole'), self.r.get('window_first')), (0, 0))
        self.assertEqual(self.holes_text(), self.holes_expected(0, 0))
        self.press(UP)
        self.assertEqual(self.r.get('menu_row'), 0)
        self.assertEqual(self.code(10, 23), S['BALL_CHAR'])
        self.assertEqual(self.holes_text(), self.holes_expected(0))

    def start(self):
        self.r.bus.joysticks = [FIRE, 0]
        for _ in range(20000000):
            if self.r.cpu.pc == self.S['main_loop']:
                return
            self.r.cpu.step()
        self.fail('the round did not start')

    def test_fire_on_players_starts_the_round_with_the_game_charset(self):
        S = self.S
        self.press(RIGHT)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('player_count', 'player', 'practice', 'HOLE')], [2, 0, 0, 0])
        self.assertEqual((self.r.get('intern_base'), self.r.get('intern_limit')),
                         (S['COURSE_CHAR'], S['COURSE_CHAR_LIMIT']))
        blank = S['CHARSET_BASE']+S['BLANK_CHAR']*8
        self.assertEqual(self.r.bus[blank:blank+8], [0]*8)
        self.r.call('draw_status')
        self.r.assert_status(self, 1, 0, COURSES[0]['par'], 1)

    def test_fire_on_a_hole_starts_practice(self):
        self.press(DOWN)
        self.press(RIGHT, 6)
        self.start()
        self.assertEqual([self.r.get(n) for n in ('player_count', 'practice', 'HOLE')], [1, 1, 6])


if __name__ == '__main__':
    unittest.main()
