"""Execute actual 6502 routines; this bus models keyboard I/O, not TED timing."""
import copy
import json
import math
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from py65.devices.mpu6502 import MPU

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from check_build import symbols
from generate_assets import validate
from course_reference import render, legacy_picture, static_patterns

S = symbols()
PRG = (ROOT/'build/minigolf-test.prg').read_bytes()
COURSE = json.loads((ROOT/'assets/test-course.json').read_text())


class KeyboardBus(list):
    def __init__(self):
        super().__init__([0]*65536)
        self.pressed = set()
        self.joysticks = [0,0]
        self.row = 255
        self.latched = 255
        self.raster = 0

    def __getitem__(self, key):
        if key == 0xff08:
            return self.latched
        if key == 0xff1d:              # every read a line later: frames pass
            self.raster = (self.raster+1) % 312
            return self.raster & 255
        return super().__getitem__(key)

    def __setitem__(self, key, value):
        if key == 0xfd30:
            self.row = value
        if key == 0xff08:
            self.latched = 255
            for row, column in self.pressed:
                if not self.row & (1 << row):
                    self.latched &= ~(1 << column)
            for port,select,fire in ((0,4,64),(1,2,128)):
                if not value & select:
                    pressed = self.joysticks[port]
                    self.latched &= ~(pressed & 15)
                    if pressed & 16:
                        self.latched &= ~fire
        super().__setitem__(key, value)


class Runtime:
    def __init__(self, build='minigolf-test'):
        self.S = S if build == 'minigolf-test' else symbols(build)
        prg = PRG if build == 'minigolf-test' else (ROOT/f'build/{build}.prg').read_bytes()
        self.bus = KeyboardBus()
        executable = Path(shutil.which('xplus4') or '/usr/bin/xplus4').resolve()
        candidates = [Path(os.environ.get('C16_KERNAL', '/nonexistent')),
                      executable.parent.parent/'share/vice/PLUS4/kernal-318004-05.bin',
                      Path('/opt/homebrew/share/vice/PLUS4/kernal-318004-05.bin'),
                      Path('/usr/share/vice/PLUS4/kernal-318004-05.bin')]
        rom_path = next((path for path in candidates if path.is_file()), None)
        if rom_path is None:
            raise FileNotFoundError('C16 KERNAL fehlt: C16_KERNAL auf kernal-318004-05.bin setzen')
        rom = rom_path.read_bytes()
        if len(rom) != 16384:
            raise ValueError(f'C16 KERNAL muss 16384 Bytes haben: {rom_path}')
        self.bus[0xc000:0x10000] = rom
        self.cpu = MPU(memory=self.bus)
        load = int.from_bytes(prg[:2], 'little')
        self.bus[load:load+len(prg)-2] = prg[2:]
        self.cpu.pc = self.S['loader']
        self.run_until(self.S['start'])
        self.call('copy_font_image')   # as start does first

    def run_until(self, address, limit=20000000):
        for _ in range(limit):
            if self.cpu.pc == address:
                return
            self.cpu.step()
        raise AssertionError(f'6502 did not reach ${address:04x}; PC=${self.cpu.pc:04x}')

    def call(self, label):
        self.cpu.sp = 255
        self.cpu.stPushWord(0xefff)
        self.cpu.pc = self.S[label]
        begin = self.cpu.processorCycles
        self.run_until(0xf000)
        return self.cpu.processorCycles-begin

    def get(self, name):
        return self.bus[self.S[name]]

    GLYPHS = {'F': 'FLAG_CHAR', 'C': 'CLUB_CHAR', '/': 'SLASH_CHAR', 'P': 'PLAYER_CHAR',
              '*': 'BALL_CHAR', '<': 'ARROW_LEFT_CHAR', '>': 'ARROW_RIGHT_CHAR', ' ': 'BLANK_CHAR'}

    def screen_text(self, row, column=0, count=40, floor=None):
        """Font codes of a screen row as text: digits, F flag, C club, '/',
        P player, * ball, < > arrows, ' ' blank (and the floor code, if
        given); '?' for anything else."""
        names = {self.S[name]: char for char, name in self.GLYPHS.items()}
        if floor is not None:
            names[floor] = ' '
        names.update({self.S['DIGIT_CHAR']+d: str(d) for d in range(10)})
        base = self.S['SCREEN_BASE']+row*40+column
        return ''.join(names.get(code, '?') for code in self.bus[base:base+count])

    def status_expected(self, hole, shots, par, player=None):
        """Left text from column 0 and the right text in columns 33..39."""
        left = f'F{hole:>2}' + (f' P{player}' if player else '')
        return left, f'C {shots:>2}/{par} '

    def assert_status(self, test, hole, shots, par, player=None, message=None):
        left, right = self.status_expected(hole, shots, par, player)
        test.assertEqual((self.screen_text(24, 0, len(left)), self.screen_text(24, 33, 7)),
                         (left, right), message)

    def call_until(self, label, stop, limit=20000000):
        """Calls label and runs until it returns or reaches stop. Returns PC."""
        self.cpu.sp = 255
        self.cpu.stPushWord(0xefff)
        self.cpu.pc = self.S[label]
        for _ in range(limit):
            if self.cpu.pc in (0xf000, self.S[stop]):
                return self.cpu.pc
            self.cpu.step()
        raise AssertionError(f'{label} neither returned nor reached {stop}')

    def frames(self, joystick, count):
        """Menu frames with joystick port 1 held: runs to title_loop or
        summary_loop count times."""
        self.bus.joysticks = [joystick, 0]
        loops = (self.S['title_loop'], self.S['summary_loop'])
        for _ in range(count):
            self.cpu.step()
            for _ in range(20000000):
                if self.cpu.pc in loops:
                    break
                self.cpu.step()
            else:
                raise AssertionError('no menu frame')

    def put(self, name, value):
        self.bus[self.S[name]] = value & 255

    def word(self, name, value):
        self.put(name, value)
        self.bus[self.S[name]+1] = value >> 8


def bitmap_offset(x, y):
    return (y//8)*320+(x//8)*8+(y%8)


class HardwareTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime()
        self.r.call('initialise_state')

    def picture(self):
        return legacy_picture(self.r.bus, self.r.S)

    def assert_picture(self, course):
        got = self.picture()
        expected, luminance, color = render(course, self.r.S)
        self.assertEqual(bytes(got[0]), bytes(expected))
        self.assertEqual(got[1][:1000], luminance[:1000])
        self.assertEqual(got[2][:1000], color[:1000])
        self.assertEqual(self.r.get('pattern_overflow'), 0)
        self.assertLessEqual(self.r.get('pattern_count'), self.r.S['COURSE_CHAR_LIMIT'])
        self.assertEqual(self.r.get('pattern_count'), len(static_patterns(course)))

    def install_floor(self):
        code = self.r.S['COURSE_CHAR']
        base = self.r.S['CHARSET_BASE']+code*8
        self.r.bus[base:base+8] = [0xff]*8
        for cell in range(40, 21*40):
            self.r.bus[self.r.S['SCREEN_BASE']+cell] = code
            self.r.bus[self.r.S['ATTR_BASE']+cell] = self.r.S['COURSE_SURFACE_COLOR']
        self.r.put('DYNAMIC_COUNT', 0)

    def test_actual_loader_relocates_runtime(self):
        payload = S['payload_image']-0x1001+2
        self.assertEqual(self.r.bus[S['RUNTIME_BASE']:S['runtime_end']], list(PRG[payload:payload+S['runtime_end']-S['RUNTIME_BASE']]))
        self.assertEqual(self.r.cpu.sp, 255)
        self.assertTrue(self.r.cpu.p & self.r.cpu.INTERRUPT)
        self.assertFalse(self.r.cpu.p & self.r.cpu.DECIMAL)

    def test_loader_survives_overwritten_sys_and_overlapping_source(self):
        padding = S['RUNTIME_LIMIT']-S['runtime_end']
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'stress.prg'
            subprocess.run(['acme','--cpu','6502','--format','cbm',
                            '-DTEST_BUILD=1', f'-DRELOCATION_TEST_PADDING={padding}', '--outfile',str(path),
                            'src/main.asm'], cwd=ROOT, check=True, capture_output=True)
            prg = path.read_bytes()
        bus = [0]*65536
        bus[0x1001:0x1001+len(prg)-2] = prg[2:]
        cpu = MPU(memory=bus, pc=S['loader'])
        for _ in range(100000):
            if cpu.pc == S['start']:
                break
            cpu.step()
        else:
            self.fail('overlapping relocation never reached start')
        payload = S['payload_image']-0x1001+2
        expected = prg[payload:payload+S['runtime_end']-S['RUNTIME_BASE']+padding]
        self.assertGreater(S['RUNTIME_BASE']+len(expected), S['payload_image'])
        self.assertEqual(bus[S['RUNTIME_BASE']:S['RUNTIME_BASE']+len(expected)], list(expected))

    def test_video_registers_charset_and_screen(self):
        self.r.bus[S['ATTR_BASE']:S['FONT_STORE']] = [0x55]*(S['FONT_STORE']-S['ATTR_BASE'])
        font = self.r.bus[S['FONT_STORE']:S['CHARSET_BASE']+1024].copy()
        self.r.call('initialise_video')
        self.assertEqual(self.r.bus[0xff06], 0x0b)
        self.assertEqual(self.r.bus[0xff07], 0x08)
        self.assertEqual(self.r.bus[0xff12], 0x00)
        self.assertEqual(self.r.bus[0xff13] & 0xfc, 0x38)
        self.assertEqual(self.r.bus[0xff14] & 0xf8, 0x30)
        self.assertEqual(self.r.bus[0xff15] & 0x7f, 0)
        self.assertEqual(self.r.bus[0xff19] & 0x7f, S['BORDER_COLOR'])
        row = [S['BLANK_CHAR']]*40
        self.assertEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1024], [32]*960+row+[32]*24)
        self.assertEqual(self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+1024], [S['HUD_FOREGROUND_COLOR']]*1024)
        self.assertEqual(self.r.bus[S['CHARSET_BASE']+32*8:S['CHARSET_BASE']+33*8], [0]*8)
        # The font image survives; its glyphs are white on black, rows 1..5.
        self.assertEqual(self.r.bus[S['FONT_STORE']:S['CHARSET_BASE']+1024], font)
        image = S['font_image']
        for code in range(1, S['FONT_GLYPHS']):
            address = S['CHARSET_BASE']+code*8
            self.assertEqual(self.r.bus[address:address+8],
                             [0]+self.r.bus[image+code*5-5:image+code*5]+[0, 0], code)
        figure = S['CHARSET_BASE']+S['FIGURE_CHAR']*8
        rows = image+(S['FONT_GLYPHS']-1)*5
        self.assertEqual(self.r.bus[figure:figure+16], self.r.bus[rows:rows+16])
        self.assertEqual(self.r.bus[S['CHARSET_BASE']:S['CHARSET_BASE']+8], [0]*8)
        for n, inner in enumerate((0x00, 0x80, 0x08, 0x01, 0xff)):
            address = S['CHARSET_BASE']+(S['BAR_CHAR']+n)*8
            self.assertEqual(self.r.bus[address:address+8], [0, 0xff, inner, inner, inner, 0xff, 0, 0])
        self.r.bus[S['SCREEN_BASE']] = 99
        self.r.call('clear_playfield')
        self.assertEqual(self.r.bus[S['SCREEN_BASE']], 99)

    def test_pixel_addressing_including_rightmost_column(self):
        for y in range(200):
            self.r.put('window_row', y//8)
            for x in (0, 1, 7, 8, 15, 127, 128, 247, 248, 255, 256, 257, 303, 311, 312, 319):
                self.r.word('PIXEL_X', x)
                self.r.put('PIXEL_Y', y)
                self.r.call('point_pixel')
                pointer = self.r.get('BITMAP_PTR')+256*self.r.bus[S['BITMAP_PTR']+1]
                self.assertEqual(pointer, S['SCRATCH_BASE']+(x & ~7)+(y & 7), (x, y))
                self.assertEqual(self.r.get('PIXEL_MASK'), 128 >> (x % 8))
        self.r.put('window_row', 3)
        self.r.word('PIXEL_X', 256)
        self.r.put('PIXEL_Y', 8*4+3)
        self.r.call('point_pixel')
        pointer = self.r.get('BITMAP_PTR')+256*self.r.bus[S['BITMAP_PTR']+1]
        self.assertEqual(pointer, S['SCRATCH_BASE']+320+256+3)

    def test_rendered_course_matches_independent_pixels(self):
        self.r.call('initialise_video')
        self.r.call('draw_course')
        self.assert_picture(COURSE)

    def test_frame_and_outer_edges_for_all_diagonal_directions(self):
        from course_codec import encode
        courses = [
            # Convex cuts in all four corners and a diamond obstacle.
            {'start':[40,80],'cup':[200,96],'obstacles':[[[120,64],[152,96],[120,128],[88,96]]],
             'outline':[[40,24],[280,24],[304,48],[304,128],[280,152],[40,152],[16,128],[16,48]]},
            # Concave diagonals: playable bays reaching into the solid area.
            {'start':[40,80],'cup':[200,96],'obstacles':[],
             'outline':[[16,24],[120,24],[144,48],[168,24],[304,24],[304,152],
                        [168,152],[144,128],[120,152],[16,152]]},
        ]
        address = 0x8000             # outside the 16 KB RAM; test bus only
        self.r.bus[S['course_table_lo']] = address & 255
        self.r.bus[S['course_table_hi']] = address >> 8
        self.r.call('initialise_video')
        for course in courses:
            data = encode(course)
            self.r.call('clear_playfield')    # as start_hole: startup runs once
            self.r.bus[address:address+len(data)] = list(data)
            self.r.cpu.x = 0
            self.r.call('decode_course')
            self.r.call('draw_course')
            self.assert_picture(course)

    def load_course(self, course, address=0x8000):
        from course_codec import encode
        data = encode(course)
        self.r.bus[S['course_table_lo']] = address & 255
        self.r.bus[S['course_table_hi']] = address >> 8
        self.r.bus[address:address+len(data)] = list(data)
        self.r.call('initialise_state')

    WATER_COURSE = {'start':[64,88],'cup':[272,88],'obstacles':[],
                    'outline':[[16,24],[304,24],[304,152],[16,152]],
                    'hazards':[[128,64,176,112],[16,128,64,152]]}

    def test_course_sets_the_initial_aim(self):
        for direction in (0, 40, 127):
            self.load_course({**self.WATER_COURSE, 'aim': direction})
            self.assertEqual(self.r.get('ANGLE'), direction)

    def test_water_cells_are_blue_floor_without_frame(self):
        self.load_course(self.WATER_COURSE)
        self.assertEqual(self.r.get('HAZARD_COUNT'), 2)
        self.r.call('initialise_video')
        self.r.call('draw_course')
        self.assert_picture(self.WATER_COURSE)
        self.assertEqual(self.r.bus[S['ATTR_BASE']+10*40+17] & 15, S['WATER_HUE'])

    def test_ball_rolling_into_water_rests_three_pixels_ashore(self):
        self.load_course(self.WATER_COURSE)
        self.r.call('initialise_video')
        self.r.call('draw_course')
        for angle, power in ((0, 24), (0, 32), (6, 20), (64-6, 28), (64+6, 28)):
            self.r.call('initialise_state')
            if angle > 32:   # roll left from the right of the pond
                self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0, 232, 0]
            self.r.put('ANGLE', angle)
            self.r.put('POWER', power)
            self.r.call('start_shot')
            shots = self.r.get('SHOTS')
            for frame in range(400):
                self.r.call('physics_tick')
                if not self.r.get('ROLLING'):
                    break
            self.assertFalse(self.r.get('ROLLING'))
            self.assertEqual(self.r.get('SHOTS'), shots+1, angle)   # penalty stroke
            x = (self.r.bus[S['BALL_POS_X']+1] + 256*self.r.bus[S['BALL_POS_X']+2])
            y = self.r.bus[S['BALL_POS_Y']+1]
            # Pond [128, 176) x [64, 112): three free pixels to the ball's edge.
            gap = max(125-x, x-178, 61-y, y-114)
            self.assertEqual(gap, 3, (angle, x, y))

    def test_markers_restore_floor_and_boundary_cells_without_recoloring(self):
        self.r.call('initialise_video')
        self.r.call('draw_course')
        screen = self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000].copy()
        attrs = self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+1000].copy()
        # Pure floor, across cell boundaries, straight edge at x=196 and diagonal.
        for x,y in ((64,112),(71,111),(194,88),(294,42),(299,49)):
            self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0,x&255,x>>8]
            self.r.bus[S['BALL_POS_Y']:S['BALL_POS_Y']+2] = [0,y]
            self.r.put('DYNAMIC_COUNT',0)
            self.r.put('PAUSED',0)
            self.r.put('ROLLING',0)
            self.r.put('ANGLE',17)
            self.r.call('draw_dynamic')
            self.assertEqual(self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+1000], attrs, (x,y))
            self.assertNotEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen)
            self.r.call('restore_dynamic')
            self.assertEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen, (x,y))

    def test_byte_ball_renderer_matches_every_pixel_alignment(self):
        self.r.call('initialise_video')
        for x in [*range(18,26),254,255,256,257,*range(262,270),313,314,315,316,317,318,319]:
            for y in (10,26,166):
                self.install_floor()
                self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0,x&255,x>>8]
                self.r.bus[S['BALL_POS_Y']:S['BALL_POS_Y']+2] = [0,y]
                self.r.put('PAUSED',1)
                self.r.call('draw_dynamic')
                expected = bytearray(8000)
                for dy in range(-2,3):
                    for dx in range(-2,3):
                        # 5x5 disc minus the highlight pixel at the top left.
                        if (dx,dy) == (-1,-1):
                            continue
                        if dx*dx+dy*dy <= 5 and 0 <= x+dx < 320 and 8 <= y+dy < 168:
                            expected[bitmap_offset(x+dx,y+dy)] |= 128 >> ((x+dx)%8)
                self.assertEqual(bytes(self.picture()[0]), expected, (x,y))
                self.assertLessEqual(self.r.get('DYNAMIC_COUNT'), 4)
                self.r.call('restore_dynamic')
                self.assertEqual(bytes(self.picture()[0]), bytes(8000))

    def test_all_aim_directions_restore_background_exactly(self):
        self.r.call('initialise_video')
        self.r.call('draw_course')
        screen = self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000].copy()
        attrs = self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+1000].copy()
        course_chars = self.r.bus[S['CHARSET_BASE']+S['COURSE_CHAR']*8:S['CHARSET_BASE']+1024].copy()
        for phase in range(4):
            self.r.put('AIM_PHASE', phase)
            for angle in range(128):
                self.r.put('ANGLE', angle)
                self.r.put('PAUSED', 0)
                self.r.put('ROLLING', 0)
                self.r.call('draw_dynamic')
                self.assertNotEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen)
                self.assertEqual(self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+1000], attrs)
                self.assertLessEqual(self.r.get('DYNAMIC_COUNT'), S['MAX_DYNAMIC_CELLS'])
                self.r.call('restore_dynamic')
                self.assertEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen, (phase, angle))
                self.assertEqual(self.r.bus[S['CHARSET_BASE']+S['COURSE_CHAR']*8:S['CHARSET_BASE']+1024], course_chars)
        self.r.put('PAUSED', 1)
        self.r.call('draw_dynamic')
        self.assertNotEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen)
        self.assertLessEqual(self.r.get('DYNAMIC_COUNT'), 4)
        self.r.call('restore_dynamic')
        self.assertEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+1000], screen)

    def test_aim_dots_walk_outwards_one_pixel_per_phase(self):
        self.r.call('initialise_video')
        bx = self.r.get('COURSE_START_X')+256*self.r.get('COURSE_START_X_HI')
        by = self.r.get('COURSE_START_Y')
        for angle in (0, 16, 32, 45, 64, 100):
            self.r.put('ANGLE', angle)
            self.r.put('PAUSED', 0)
            self.r.put('ROLLING', 0)
            for phase in range(4):
                self.install_floor()
                self.r.put('AIM_PHASE', phase)
                self.r.call('draw_dynamic')
                bitmap = self.picture()[0]
                dots = []
                for y in range(8, 168):
                    for x in range(320):
                        if bitmap[bitmap_offset(x, y)] & (128 >> (x % 8)):
                            if (x-bx)*(x-bx)+(y-by)*(y-by) > 25:
                                a = angle*math.pi/64
                                dots.append((x-bx)*math.cos(a)+(y-by)*math.sin(a))
                self.r.call('restore_dynamic')
                dots.sort()
                self.assertEqual(len(dots), 7, (angle, phase, dots))
                for k, d in enumerate(dots):
                    self.assertLessEqual(abs(d-(8+phase+4*k)), 2, (angle, phase, dots))

    def test_joystick_port_one_and_separate_pause_keyboard(self):
        for mask in range(32):
            for pause in (False,True):
                self.r.bus.joysticks = [mask,31]  # Port 2 must not leak in.
                self.r.bus.pressed = {(1,2),(2,2),(1,1),(1,5),(7,4)}
                if pause:
                    self.r.bus.pressed.add((5,1))
                self.r.call('scan_keyboard')
                expected = ((mask & 12) >> 2) | ((mask & 3) << 2) | (32 if mask & 16 else 0) | (16 if pause else 0)
                self.assertEqual(self.r.get('KEY_CURRENT'),expected)
                self.assertEqual(self.r.bus.row,255)

    def tick(self, keys):
        self.r.put('KEY_CURRENT', keys)
        self.r.call('debounce_keyboard')
        actions = self.r.get('KEY_ACTIONS')
        self.r.call('apply_controls')
        return actions

    def test_debounce_wrap_repeat_and_pause_edge(self):
        self.assertEqual(self.tick(1), 0)
        self.assertEqual(self.tick(0), 0)  # a bouncing one-frame press is rejected
        self.assertEqual(self.tick(0), 0)
        self.assertEqual(self.tick(1), 0)
        self.assertEqual(self.tick(1), 1)
        self.assertEqual(self.r.get('ANGLE'), 127)
        for _ in range(14):
            self.assertEqual(self.tick(1), 0)
        self.assertEqual(self.tick(1), 1)
        self.assertEqual(self.r.get('ANGLE'), 126)
        self.assertEqual([self.tick(1) for _ in range(3)], [0,0,1])
        self.tick(16)
        self.tick(16)
        self.assertEqual(self.r.get('PAUSED'), 1)
        for _ in range(50):
            self.assertEqual(self.tick(16), 0)
        self.tick(18)
        self.tick(18)
        self.assertEqual(self.r.get('ANGLE'), 125)  # rotation while paused ignored
        self.tick(0)
        self.tick(0)
        self.tick(16)
        self.tick(16)
        self.assertEqual(self.r.get('PAUSED'), 0)

    def test_fire_charges_saturates_and_fires_only_on_debounced_release(self):
        self.tick(0)
        self.tick(0)
        self.assertEqual(self.r.get('POWER'),0)
        self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.tick(32)
        self.assertEqual(self.r.get('POWER'),1)
        for power in range(2,33):
            self.tick(32)
            self.assertEqual(self.r.get('POWER'),power-1)
            self.tick(32)
            self.assertEqual(self.r.get('POWER'),power)
            self.assertEqual(self.r.get('SHOTS'),0)
        for _ in range(20):
            self.tick(32)
        self.assertEqual(self.r.get('POWER'),32)
        self.tick(0)
        self.assertEqual(self.r.get('SHOTS'),0)
        self.tick(0)
        self.assertEqual(self.r.get('SHOTS'),1)
        self.assertEqual(self.r.get('ROLLING'),1)
        self.assertEqual(self.r.get('POWER'),0)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.assertEqual(self.r.get('SPEED')+256*self.r.bus[S['SPEED']+1],1024)

    def test_charge_duration_selects_strength_and_ignores_ws_and_opposing_directions(self):
        for frames in (2,12,32,64):
            self.r.call('initialise_state')
            self.tick(0)
            self.tick(0)
            for _ in range(frames):
                self.tick(32)
            self.tick(0)
            self.tick(0)
            # First release sample remains held and advances the timer.
            expected = min(32,1+(frames-1)//2)
            self.assertEqual(self.r.get('SPEED')+256*self.r.bus[S['SPEED']+1],expected*32)
        self.r.call('initialise_state')
        self.tick(0)
        self.tick(0)
        self.tick(12)
        self.tick(12)
        self.assertEqual(self.r.get('POWER'),0)
        self.tick(3)
        self.tick(3)
        self.assertEqual(self.r.get('ANGLE'),0)

    def test_pause_cancels_charge_and_held_fire_never_restarts_after_pause_or_roll(self):
        self.tick(0)
        self.tick(0)
        for _ in range(10):
            self.tick(32)
        self.tick(48)
        self.tick(48)
        self.assertEqual(self.r.get('PAUSED'),1)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.assertEqual(self.r.get('POWER'),0)
        self.tick(32)
        self.tick(32)
        self.tick(48)
        self.tick(48)
        self.assertEqual(self.r.get('PAUSED'),0)
        for _ in range(20):
            self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.assertEqual(self.r.get('SHOTS'),0)
        self.tick(0)
        self.tick(0)
        self.tick(32)
        self.tick(32)
        self.tick(0)
        self.tick(0)
        self.assertEqual(self.r.get('SHOTS'),1)
        for _ in range(10):
            self.tick(32)
        self.r.put('ROLLING',0)
        for _ in range(10):
            self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.assertEqual(self.r.get('SHOTS'),1)

    def hole_out(self, shots):
        """Holes with shots strokes and fires: runs next_hole through the
        real control path. Returns where it went: 'game', 'summary' or 'title'."""
        self.r.put('HOLED', 1)
        self.r.put('SHOTS', shots)
        self.r.put('FIRE_LOCK', 0)
        self.r.put('KEY_PREVIOUS', 32)
        pc = self.r.call_until('apply_controls', 'summary_screen')
        if pc == S['summary_screen']:
            return 'summary'
        return 'game'

    def totals(self):
        return self.r.bus[S['totals']:S['totals']+4]

    def test_players_finish_each_hole_in_turn_then_the_summary(self):
        self.r.call('initialise_video')
        self.r.bus[S['totals']:S['totals']+4] = [0]*4
        self.r.put('player_count', 3)
        self.r.put('player', 0)
        self.r.put('practice', 0)
        self.r.put('HOLE', 0)
        self.r.call('initialise_state')
        self.assertEqual(self.hole_out(3), 'game')
        # Player 2 on the same hole: state cleared, ball back on the tee.
        self.assertEqual((self.r.get('player'), self.r.get('HOLE'), self.r.get('HOLED'),
                          self.r.get('SHOTS'), self.r.get('FIRE_LOCK')), (1, 0, 0, 0, 1))
        self.assertEqual(self.r.bus[S['BALL_POS_X']+1], self.r.get('COURSE_START_X'))
        self.assertEqual(self.totals(), [3, 0, 0, 0])
        self.r.call('draw_status')
        self.r.assert_status(self, 1, 0, self.r.bus[S['course_par']], 2)
        self.assertEqual(self.hole_out(5), 'game')
        # The test build has one hole: the last player's fire ends the round.
        self.assertEqual(self.hole_out(13), 'summary')
        self.assertEqual(self.totals(), [3, 5, 13, 0])
        self.assertEqual(self.r.get('HOLE'), S['COURSE_COUNT'])

    def test_practice_returns_to_the_menu_without_scoring(self):
        self.r.call('initialise_video')
        self.r.bus[S['totals']:S['totals']+4] = [0]*4
        self.r.put('player_count', 1)
        self.r.put('practice', 1)
        self.r.put('HOLED', 1)
        self.r.put('FIRE_LOCK', 0)
        self.r.put('KEY_PREVIOUS', 32)
        self.assertEqual(self.r.call_until('apply_controls', 'title_screen'), S['title_screen'])
        self.assertEqual(self.totals(), [0]*4)

    def test_holed_fire_waits_for_release_on_the_next_player(self):
        self.r.call('initialise_video')
        self.r.put('player_count', 2)
        self.r.put('player', 0)
        self.r.put('practice', 0)
        self.tick(0)
        self.tick(0)
        self.r.put('HOLED',1)
        self.r.put('SHOTS',3)
        self.tick(32)
        self.tick(32)
        self.assertEqual((self.r.get('player'), self.r.get('HOLED'), self.r.get('FIRE_LOCK')), (1, 0, 1))
        for _ in range(20):
            self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.tick(0)
        self.tick(0)
        self.tick(32)
        self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),1)

    def test_sound_effects_follow_the_catalog_and_switch_off(self):
        # c16-sound-fx steps: frames, voice 1 Hz, voice 2 Hz, $FF11 control.
        def hz(f):
            return 1024-(110840+f//2)//f
        def step():
            n1 = self.r.bus[0xff0e]+256*(self.r.bus[0xff12] & 3)
            n2 = self.r.bus[0xff0f]+256*(self.r.bus[0xff10] & 3)
            return n1, n2, self.r.bus[0xff11]
        expected = {
            'SOUND_SHOT': [(1, 320, 110, 0x14), (1, 320, 110, 0x12), (1, 320, 110, 0x11)],
            'SOUND_WALL': [(2, 110, 2000, 0x44)],
            'SOUND_CUP': [(2, 330, 660, 0x34), (2, 440, 880, 0x35), (2, 660, 1320, 0x35),
                          (2, 440, 880, 0x34), (2, 880, 1760, 0x34), (3, 1320, 2640, 0x32)],
            'SOUND_WATER': [(1, 110, 2000, 0x43), (2, 110, 1200, 0x42), (2, 110, 110, 0x00), (1, 110, 1700, 0x44), (2, 110, 850, 0x42), (2, 110, 450, 0x41), (6, 110, 110, 0x00)],
            'SOUND_ACE': [(2, 392, 110, 0x14), (2, 523, 110, 0x15), (2, 659, 110, 0x15), (2, 440, 110, 0x14), (2, 587, 110, 0x15), (2, 740, 110, 0x15), (2, 494, 110, 0x14), (2, 659, 110, 0x15), (2, 831, 110, 0x15), (2, 523, 110, 0x14), (2, 698, 110, 0x15), (2, 880, 110, 0x15), (2, 587, 110, 0x14), (2, 784, 110, 0x14), (2, 988, 110, 0x13)]}
        for name, steps in expected.items():
            self.r.bus[0xff12] = 0xc4           # charset bit and unused bits must survive
            self.r.bus[0xff10] = 0xfc
            self.r.cpu.x = S[name]
            self.r.call('play_sound')
            heard = []
            for _ in range(60):
                if not self.r.get('SOUND_TIME'):
                    break
                current = step()
                if heard and heard[-1][1] == current:
                    heard[-1][0] += 1
                else:
                    heard.append([1, current])
                self.r.call('sound_tick')
            want = [[frames, (hz(f1), hz(f2), control)] for frames, f1, f2, control in steps]
            self.assertEqual(heard, want, name)
            self.assertEqual(self.r.bus[0xff11] & 0x7f, 0, name)   # voices off
            self.assertEqual(self.r.bus[0xff12] & 0xfc, 0xc4, name)
            self.assertEqual(self.r.bus[0xff10] & 0xfc, 0xfc, name)

    def test_hole_in_one_has_its_own_sound(self):
        for shots, sound in ((1, 'SOUND_ACE'), (2, 'SOUND_CUP'), (5, 'SOUND_CUP')):
            self.r.call('initialise_state')
            self.r.put('SHOTS', shots)
            self.r.call('finish_hole')
            self.assertEqual(self.r.get('SOUND_TONE'), S[sound], shots)

    def test_twelfth_stroke_without_holing_counts_thirteen(self):
        for shots, holed, expected in ((11, 0, (11, 0)), (12, 0, (13, 13)), (12, 1, (12, 1))):
            self.r.put('SHOTS', shots)
            self.r.put('HOLED', holed)
            self.r.call('stop_ball')
            self.assertEqual((self.r.get('SHOTS'), self.r.get('HOLED')), expected)

    def screen_codes(self, column, count, row=24):
        base = S['SCREEN_BASE']+row*40+column
        return self.r.bus[base:base+count]

    def test_summary_lists_each_player_with_a_ball_beside_the_best(self):
        self.r.call('initialise_video')
        par = json.loads((ROOT/'assets/test-course.json').read_text()).get('par', 0)
        self.assertEqual(S['TOTAL_PAR'], par)
        for totals in ([61, 0, 0, 0], [123, 7, 234, 7]):
            count = 1 if totals[1] == 0 else 4
            self.r.bus[S['totals']:S['totals']+4] = totals
            self.r.put('player_count', count)
            self.assertEqual(self.r.call_until('summary_screen', 'summary_loop'), S['summary_loop'])
            floor = self.r.get('solid_code')
            best = min(totals[:count])
            for p in range(count):
                mark = '*' if totals[p] == best else ' '
                self.assertEqual(self.r.screen_text(10+2*p, 13, 12, floor),
                                 f'{mark}P{p+1} C{totals[p]:>4}/{par:>2}', totals)
            self.assertEqual(self.r.screen_text(10+2*count, 13, 12, floor), ' '*12)

    def test_game_build_plays_the_18_drafts_in_order(self):
        from course_codec import encode
        game = Runtime('minigolf')
        self.assertEqual(game.S['COURSE_COUNT'], 18)
        game.call('initialise_video')
        for hole, path in enumerate(sorted((ROOT/'assets/courses').glob('*.json'))):
            course = json.loads(path.read_text())
            address = game.bus[game.S['course_table_lo']+hole]+256*game.bus[game.S['course_table_hi']+hole]
            data = encode(course)
            self.assertEqual(game.bus[address:address+len(data)], list(data), hole)
            game.put('HOLE', hole)
            game.call('initialise_state')
            self.assertEqual(game.get('COURSE_START_Y'), course['start'][1], hole)
            self.assertEqual(game.get('COURSE_CUP_Y'), course['cup'][1], hole)

    def test_decoder_matches_host_reference_segments(self):
        from generate_assets import expanded_segments
        expected = expanded_segments(COURSE)
        self.assertEqual(self.r.get('SEGMENT_BYTES'), len(expected))
        self.assertEqual(self.r.bus[S['course_segments']:S['course_segments']+len(expected)], expected)
        self.assertEqual(self.r.get('COURSE_START_X')+256*self.r.get('COURSE_START_X_HI'), COURSE['start'][0])
        self.assertEqual(self.r.get('COURSE_START_Y'), COURSE['start'][1])
        self.assertEqual(self.r.get('COURSE_CUP_X')+256*self.r.get('COURSE_CUP_X_HI'), COURSE['cup'][0])
        self.assertEqual(self.r.get('COURSE_CUP_Y'), COURSE['cup'][1])

    def test_decoder_flags_for_varied_contours(self):
        from course_codec import encode
        from generate_assets import expanded_segments
        courses = [
            {'start':[40,40],'cup':[272,112],'obstacles':[],
             'outline':[[16,24],[304,24],[304,152],[16,152]]},
            {'start':[40,40],'cup':[200,120],'obstacles':[[[96,64],[128,96],[96,128],[64,96]]],
             'outline':[[16,152],[304,152],[304,48],[280,24],[16,24]]},
            {'start':[40,40],'cup':[200,120],
             'obstacles':[[[160,64],[160,96],[192,96],[192,64]]],
             'outline':[[16,24],[64,24],[96,56],[136,56],[136,24],[304,24],
                        [304,152],[200,152],[168,120],[128,120],[96,152],[16,152]]},
        ]
        address = 0x8000             # outside the 16 KB RAM; test bus only
        self.r.bus[S['course_table_lo']] = address & 255
        self.r.bus[S['course_table_hi']] = address >> 8
        for course in courses:
            data = encode(course)
            self.r.bus[address:address+len(data)] = list(data)
            self.r.cpu.x = 0
            self.r.call('decode_course')
            expected = expanded_segments(course)
            self.assertEqual(self.r.get('SEGMENT_BYTES'), len(expected))
            self.assertEqual(self.r.bus[S['course_segments']:S['course_segments']+len(expected)], expected)

    def test_frame_stack_stays_above_volatile_buffers(self):
        # Each call pushes the return address exactly like main_loop's JSR.
        lowest = [255]
        step = self.r.cpu.step
        def tracked_step():
            step()
            lowest[0] = min(lowest[0], self.r.cpu.sp)
        self.r.cpu.step = tracked_step
        for label in ('initialise_video','draw_course','draw_status',
                      'draw_dynamic','draw_power'):
            self.r.call(label)
        frame = ('scan_keyboard','debounce_keyboard','apply_controls',
                 'physics_tick','restore_dynamic','draw_dynamic','draw_power')
        for angle in (0,40,88):
            self.r.call('initialise_state')
            self.r.put('ANGLE', angle)
            self.r.put('POWER', 32)
            self.r.call('start_shot')
            for _ in range(60):
                for label in frame:
                    self.r.call(label)
        depth = 255-lowest[0]
        self.assertLessEqual(depth, 24, depth)
        self.assertGreaterEqual(0x100+lowest[0]-16, S['STACK_FLOOR'])

    def test_power_bar_grows_pixel_by_pixel(self):
        self.r.call('initialise_video')
        # Outline 80 x 5 pixels, ticks at 25, 50 and 75 %.
        inner = {0, 20, 40, 60, 79}
        for power in (0,1,2,3,7,8,16,24,32,31,16,0,32,0,5,6,5,32):
            self.r.put('POWER', power)
            self.r.call('draw_power')
            filled = 5*power//2
            for cell in range(S['BAR_CELLS']):
                code = self.r.bus[S['SCREEN_BASE']+24*40+S['BAR_COLUMN']+cell]
                self.assertIn(code, range(S['BAR_CHAR'], S['BAR_CHAR']+S['BAR_GLYPHS']), (power, cell))
                address = S['CHARSET_BASE']+code*8
                glyph = self.r.bus[address:address+8]
                for row in range(8):
                    for bit in range(8):
                        x = cell*8+bit
                        if row in (0, 6, 7):
                            want = False
                        elif x < filled or row in (1, 5):
                            want = True
                        else:
                            want = x in inner
                        self.assertEqual(bool(glyph[row] & (0x80 >> bit)), want, (power, cell, row, bit))

    def test_status_shows_flag_and_hole_left_club_shots_and_par_right(self):
        self.r.call('initialise_video')
        # One course in the test build: other holes read past course_par.
        self.r.put('player_count', 1)
        for hole, shots in ((0, 0), (17, 13), (8, 9), (98, 10), (3, 1)):
            par = self.r.bus[S['course_par']+hole] % 10
            self.r.bus[S['course_par']+hole] = par
            self.r.put('HOLE', hole)
            self.r.put('SHOTS', shots)
            self.r.call('draw_status')
            self.r.assert_status(self, hole+1, shots, par, None, (hole, shots))
        self.r.put('player_count', 4)
        self.r.put('player', 3)
        self.r.call('draw_status')
        self.r.assert_status(self, 4, 1, self.r.bus[S['course_par']+3], 4)

    def test_hud_stays_outside_course_and_bar(self):
        self.r.call('initialise_video')
        playfield = self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+24*40].copy()
        attrs = self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+24*40].copy()
        charset = self.r.bus[S['CHARSET_BASE']:S['CHARSET_BASE']+1024].copy()
        bar = range(S['BAR_PARTIAL_GLYPH']-S['CHARSET_BASE'], S['BAR_PARTIAL_GLYPH']-S['CHARSET_BASE']+8)
        self.r.put('HOLE', 17)
        self.r.put('SHOTS', 13)
        for players in (1, 4):
            self.r.put('player_count', players)
            self.r.put('player', players-1)
            self.r.call('draw_status')
            for power in range(33):
                self.r.put('POWER', power)
                self.r.call('draw_power')
        self.assertEqual(self.r.bus[S['SCREEN_BASE']:S['SCREEN_BASE']+24*40], playfield)
        self.assertEqual(self.r.bus[S['ATTR_BASE']:S['ATTR_BASE']+24*40], attrs)
        after = self.r.bus[S['CHARSET_BASE']:S['CHARSET_BASE']+1024]
        self.assertEqual([i for i in range(1024) if after[i] != charset[i] and i not in bar], [])

    def test_drafts_match_reference_within_character_budget(self):
        game = Runtime('minigolf')
        game.call('initialise_video')
        for hole, path in enumerate(sorted((ROOT/'assets/courses').glob('*.json'))):
            course = json.loads(path.read_text())
            game.put('HOLE', hole)
            game.call('initialise_state')
            game.call('draw_course')
            got = legacy_picture(game.bus, game.S)
            expected, luminance, color = render(course, game.S)
            self.assertEqual(bytes(got[0]), bytes(expected), hole)
            self.assertEqual(got[1][:1000], luminance[:1000], hole)
            self.assertEqual(got[2][:1000], color[:1000], hole)
            self.assertEqual(game.get('pattern_overflow'), 0, hole)
            self.assertEqual(game.get('pattern_count'), len(static_patterns(course)), hole)
            self.assertLessEqual(game.get('pattern_count'), game.S['COURSE_CHAR_LIMIT'], hole)


class CourseValidationTests(unittest.TestCase):
    def test_valid_test_course(self):
        self.assertEqual(len(validate(COURSE)), 17)

    def test_rejects_invalid_geometry(self):
        cases = [
            [[16,24],[130,24],[130,152],[16,152]],
            [[16,24],[128,25],[128,152],[16,152]],
            [[16,24],[128,24],[128,24],[16,152]],
            [[16,24],[128,24],[100,60],[16,152]],
            [[16,24],[128,136],[16,136],[128,24]],
            [[16,24],[128,24],[64,24],[64,152],[16,152]],
            # 45-degree corner off the cell grid (format 3 stores cells).
            [[16,24],[122,24],[128,30],[128,152],[16,152]],
        ]
        for outline in cases:
            course = copy.deepcopy(COURSE)
            course['outline'] = outline
            with self.assertRaises(ValueError):
                validate(course)

    def test_rejects_passages_narrower_than_ten_pixels(self):
        room = {'start':[40,40],'cup':[200,120],'outline':[[16,24],[304,24],[304,152],[16,152]]}
        narrow = [[[96,32],[200,32],[200,96],[96,96]],          # 8 px below the top wall
                  [[96,40],[104,32],[200,32],[200,96],[96,96]]] # 45-degree corner, 8 px
        for obstacle in narrow:
            with self.assertRaises(ValueError):
                validate({**room, 'obstacles':[obstacle]})
        validate({**room, 'obstacles':[[[96,40],[200,40],[200,96],[96,96]]]})   # 16 px


if __name__ == '__main__':
    unittest.main()
