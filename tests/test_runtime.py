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
from course_reference import render

S = symbols()
PRG = (ROOT/'build/minigolf.prg').read_bytes()
COURSE = json.loads((ROOT/'assets/test-course.json').read_text())


class KeyboardBus(list):
    def __init__(self):
        super().__init__([0]*65536)
        self.pressed = set()
        self.joysticks = [0,0]
        self.row = 255
        self.latched = 255

    def __getitem__(self, key):
        if key == 0xff08:
            return self.latched
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
    def __init__(self):
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
        load = int.from_bytes(PRG[:2], 'little')
        self.bus[load:load+len(PRG)-2] = PRG[2:]
        self.cpu.pc = S['loader']
        self.run_until(S['start'])
        # Supply the startup-installed lookup row for isolated routine tests.
        # The actual copy/blanking path is checked separately and in VICE.
        self.bus[0x2000:0x2140] = self.bus[S['lookup_image']:S['lookup_image']+320]

    def run_until(self, address, limit=3000000):
        for _ in range(limit):
            if self.cpu.pc == address:
                return
            self.cpu.step()
        raise AssertionError(f'6502 did not reach ${address:04x}; PC=${self.cpu.pc:04x}')

    def call(self, label):
        self.cpu.sp = 255
        self.cpu.stPushWord(0xefff)
        self.cpu.pc = S[label]
        begin = self.cpu.processorCycles
        self.run_until(0xf000)
        return self.cpu.processorCycles-begin

    def get(self, name):
        return self.bus[S[name]]

    def put(self, name, value):
        self.bus[S[name]] = value & 255

    def word(self, name, value):
        self.put(name, value)
        self.bus[S[name]+1] = value >> 8


def bitmap_offset(x, y):
    return (y//8)*320+(x//8)*8+(y%8)


class HardwareTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime()
        self.r.call('initialise_state')

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
                            f'-DRELOCATION_TEST_PADDING={padding}', '--outfile',str(path),
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

    def test_video_registers_attributes_and_clear(self):
        hidden = self.r.bus[0x3a40:0x3e00]
        startup = self.r.bus[0x3f40:0x4000]
        lookup = self.r.bus[S['lookup_image']:S['lookup_image']+320]
        self.r.bus[0x1800:0x4000] = [255]*(0x4000-0x1800)
        self.r.bus[0x3a40:0x3e00] = hidden
        self.r.bus[0x3f40:0x4000] = startup
        self.r.bus[S['lookup_image']:S['lookup_image']+320] = lookup
        self.r.call('initialise_video')
        # HUD palette everywhere; draw_course colors rows 0..23 later.
        luma, colors = [7]*1024,[16]*1024
        self.assertEqual(self.r.bus[0x1800:0x1c00], luma)
        self.assertEqual(self.r.bus[0x1c00:0x2000], colors)
        self.assertEqual(self.r.bus[0x2000:0x2140],lookup)
        self.assertEqual(self.r.bus[0x2140:0x3a40], [0]*6400)
        self.assertEqual(self.r.bus[0x3e00:0x3f40], [0]*320)
        self.assertEqual(self.r.bus[0x3a40:0x3e00],hidden)
        self.assertEqual(self.r.bus[0x3f40:0x4000],startup)
        self.assertEqual(self.r.bus[0xff06], 0x0b)
        self.assertEqual(self.r.bus[0xff07], 8)
        self.assertEqual(self.r.bus[0xff12], 8)
        self.assertEqual(self.r.bus[0xff14], 0x18)

    def test_pixel_addressing_including_rightmost_column(self):
        for y in range(200):
            for x in (0,1,7,8,15,127,128,247,248,255,256,257,303,311,312,319):
                self.r.word('PIXEL_X', x)
                self.r.put('PIXEL_Y', y)
                self.r.call('point_pixel')
                pointer = self.r.get('BITMAP_PTR')+256*self.r.bus[S['BITMAP_PTR']+1]
                self.assertEqual(pointer, 0x2000+bitmap_offset(x,y), (x,y))
                self.assertEqual(self.r.get('PIXEL_MASK'), 128 >> (x%8))

    def test_rendered_course_matches_independent_pixels(self):
        self.r.call('initialise_video')
        self.r.call('draw_course')
        expected, luminance, color = render(COURSE, S)
        self.assertEqual(self.r.bus[0x1800:0x1800+960], luminance[:960])
        self.assertEqual(self.r.bus[0x1c00:0x1c00+960], color[:960])
        self.assertEqual(bytes(self.r.bus[0x2140:0x3a40]), expected[320:6720])
        self.assertEqual(bytes(self.r.bus[0x3e00:0x3f40]), expected[7680:])

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
        for course in courses:
            data = encode(course)
            self.r.call('initialise_video')
            self.r.bus[address:address+len(data)] = list(data)
            self.r.cpu.x = 0
            self.r.call('decode_course')
            self.r.call('draw_course')
            expected, luminance, color = render(course, S)
            self.assertEqual(bytes(self.r.bus[0x2140:0x3a40]), expected[320:6720])
            self.assertEqual(self.r.bus[0x1800:0x1800+960], luminance[:960])
            self.assertEqual(self.r.bus[0x1c00:0x1c00+960], color[:960])

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

    def test_water_cells_are_blue_floor_without_frame(self):
        self.load_course(self.WATER_COURSE)
        self.assertEqual(self.r.get('HAZARD_COUNT'), 2)
        self.r.call('initialise_video')
        self.r.call('draw_course')
        expected, luminance, color = render(self.WATER_COURSE, S)
        self.assertEqual(bytes(self.r.bus[0x2140:0x3a40]), expected[320:6720])
        self.assertEqual(self.r.bus[0x1800:0x1800+960], luminance[:960])
        self.assertEqual(self.r.bus[0x1c00:0x1c00+960], color[:960])
        self.assertEqual(color[10*40+17] & 15, S['WATER_HUE'])

    def test_ball_rolling_into_water_rests_where_it_fell_in(self):
        self.load_course(self.WATER_COURSE)
        self.r.call('initialise_video')
        self.r.call('draw_course')
        for angle, power in ((0, 24), (0, 32), (6, 20), (64-6, 28)):
            self.r.call('reset_ball')
            if angle > 32:   # roll left from the right of the pond
                self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0, 232, 0]
            self.r.put('ANGLE', angle)
            self.r.put('POWER', power)
            self.r.call('start_shot')
            for frame in range(400):
                before = self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+5]
                self.r.call('physics_tick')
                if not self.r.get('ROLLING'):
                    break
            self.assertFalse(self.r.get('ROLLING'))
            x = (self.r.bus[S['BALL_POS_X']+1] + 256*self.r.bus[S['BALL_POS_X']+2])
            y = self.r.bus[S['BALL_POS_Y']+1]
            # Back at the start of the entering frame: outside, near the edge.
            self.assertEqual(self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+5], before, angle)
            self.assertFalse(128 <= x < 176 and 64 <= y < 112, (angle, x, y))
            distance = max(128-x-1, x-176, 64-y-1, y-112)
            self.assertLessEqual(distance, 4, (angle, x, y))

    def test_markers_restore_floor_and_boundary_cells_without_recoloring(self):
        self.r.call('initialise_video')
        self.r.call('draw_course')
        background = self.r.bus[0x2000:0x3f40].copy()
        attrs = self.r.bus[0x1800:0x2000].copy()
        # Pure floor, across cell boundaries, straight edge at x=196 and diagonal.
        for x,y in ((64,112),(71,111),(194,88),(294,42),(299,49)):
            self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0,x&255,x>>8]
            self.r.bus[S['BALL_POS_Y']:S['BALL_POS_Y']+2] = [0,y]
            self.r.put('DYNAMIC_COUNT',0)
            self.r.put('PAUSED',0)
            self.r.put('ANGLE',17)
            self.r.call('draw_dynamic')
            self.assertEqual(self.r.bus[0x1800:0x2000],attrs,(x,y))
            self.r.call('restore_dynamic')
            self.assertEqual(self.r.bus[0x2000:0x3f40],background,(x,y))

    def test_byte_ball_renderer_matches_every_pixel_alignment(self):
        for x in [*range(18,26),254,255,256,257,317,318,319]:
            for y in (10,26,166):
                self.r.bus[0x2000:0x3f40] = [0]*8000
                self.r.bus[S['BALL_POS_X']:S['BALL_POS_X']+3] = [0,x&255,x>>8]
                self.r.bus[S['BALL_POS_Y']:S['BALL_POS_Y']+2] = [0,y]
                self.r.put('DYNAMIC_COUNT',0)
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
                self.assertEqual(bytes(self.r.bus[0x2000:0x3f40]),expected,(x,y))
                self.assertLessEqual(self.r.get('DYNAMIC_COUNT'),10)
                self.r.call('restore_dynamic')
                self.assertEqual(self.r.bus[0x2000:0x3f40],[0]*8000)

    def test_all_aim_directions_restore_background_exactly(self):
        pattern = [(i*73+19)%256 for i in range(8000)]
        self.r.bus[0x2000:0x3f40] = pattern
        for phase in range(4):
            self.r.put('AIM_PHASE', phase)
            for angle in range(128):
                self.r.put('ANGLE', angle)
                self.r.call('draw_dynamic')
                self.assertEqual(self.r.get('DYNAMIC_COUNT'), 17)
                self.assertNotEqual(self.r.bus[0x2000:0x3f40], pattern)
                self.r.call('restore_dynamic')
                self.assertEqual(self.r.bus[0x2000:0x3f40], pattern, (phase,angle))
        self.r.put('PAUSED', 1)
        self.r.call('draw_dynamic')
        self.assertEqual(self.r.get('DYNAMIC_COUNT'), 10)
        self.r.call('restore_dynamic')
        self.assertEqual(self.r.bus[0x2000:0x3f40], pattern)

    def test_aim_dots_walk_outwards_one_pixel_per_phase(self):
        for angle in (0, 16, 32, 45, 64, 100):
            self.r.call('initialise_state')
            self.r.put('ANGLE', angle)
            bx, by = self.r.get('COURSE_START_X'), self.r.get('COURSE_START_Y')
            distances = []
            for phase in range(4):
                self.r.put('AIM_PHASE', phase)
                self.r.put('DYNAMIC_COUNT', 0)
                self.r.call('draw_dynamic')
                dots = []
                for i in range(self.r.get('DYNAMIC_COUNT')-7, self.r.get('DYNAMIC_COUNT')):
                    address = self.r.bus[S['DYNAMIC_LO']+i]+256*self.r.bus[S['DYNAMIC_HI']+i]-0x2000
                    # Two dots can share a byte: the later save holds this dot's result.
                    count = self.r.get('DYNAMIC_COUNT')
                    later = [j for j in range(i+1, count)
                             if self.r.bus[S['DYNAMIC_LO']+j]+256*self.r.bus[S['DYNAMIC_HI']+j]-0x2000 == address]
                    after = self.r.bus[S['DYNAMIC_OLD']+later[0]] if later else self.r.bus[address+0x2000]
                    mask = after ^ self.r.bus[S['DYNAMIC_OLD']+i]
                    x = (address%320)//8*8 + 7-(mask.bit_length()-1)
                    y = address//320*8 + address%8
                    a = angle*math.pi/64
                    dots.append((x-bx)*math.cos(a)+(y-by)*math.sin(a))
                self.r.call('restore_dynamic')
                distances.append(dots)
            for phase in range(4):
                self.assertEqual(len(distances[phase]), 7)
                for k, d in enumerate(distances[phase]):
                    self.assertLessEqual(abs(d-(8+phase+4*k)), 2, (angle, phase, distances))

    def test_joystick_port_one_and_separate_pause_keyboard(self):
        for mask in range(32):
            for pause in (False,True):
                self.r.bus.joysticks = [mask,31]  # Port 2 must not leak in.
                self.r.bus.pressed = {(1,2),(2,2),(1,1),(1,5),(7,4)}
                if pause:
                    self.r.bus.pressed.add((5,1))
                self.r.call('scan_keyboard')
                expected = ((mask & 12) >> 2) | (32 if mask & 16 else 0) | (16 if pause else 0)
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

    def test_holed_fire_restarts_but_requires_release_before_charge(self):
        self.tick(0)
        self.tick(0)
        self.r.put('HOLED',1)
        self.tick(32)
        self.tick(32)
        self.assertEqual(self.r.get('HOLED'),0)
        self.assertEqual(self.r.get('FIRE_LOCK'),1)
        for _ in range(20):
            self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),0)
        self.tick(0)
        self.tick(0)
        self.tick(32)
        self.tick(32)
        self.assertEqual(self.r.get('CHARGING'),1)

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
        for label in ('initialise_video','draw_course','draw_static_hud',
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
        self.r.call('draw_static_hud')
        base = 0x3e00+S['BAR_COLUMN']*8
        for power in (0,1,2,3,7,32,31,16,0,32,0,5,6,5,32):
            self.r.put('POWER', power)
            self.r.call('draw_power')
            filled = 5*power//2
            for cell in range(S['BAR_CELLS']):
                n = max(0, min(8, filled-cell*8))
                byte = (0xff00 >> n) & 0xff
                address = base+cell*8
                self.assertEqual(self.r.bus[address:address+8], [0,byte,byte,0xff,byte,byte,0,0], (power,cell))

    def test_status_shows_hole_left_and_shots_right(self):
        self.r.call('initialise_video')
        def text(column, count):
            return [bytes(self.r.bus[0x3e00+c*8:0x3e00+c*8+8]) for c in range(column, column+count)]
        def glyph(char):
            code = ord(char) & 63
            return bytes(self.r.bus[0xd000+code*8:0xd000+code*8+8])
        for hole, shots, left, right in ((0,0,'BAHN 1 ',' PUNKTE 0'),(17,13,'BAHN 18','PUNKTE 13'),
                                         (8,9,'BAHN 9 ',' PUNKTE 9')):
            self.r.put('HOLE', hole)
            self.r.put('SHOTS', shots)
            self.r.call('draw_static_hud')
            self.assertEqual(text(0,7), [glyph(c) for c in left])
            self.assertEqual(text(31,9), [glyph(c) for c in right])

    def test_glyph_cell_above_255_and_hud_stays_outside_course(self):
        self.r.bus[0x2000:0x4000] = [0x55]*8192
        self.r.put('TEXT_ROW', 24)
        self.r.put('TEXT_COLUMN', 39)
        self.r.cpu.a = ord('A')
        self.r.call('draw_glyph')
        pointer = 0x2000+bitmap_offset(312,192)
        self.assertEqual(self.r.bus[pointer:pointer+8], [24,60,102,126,102,102,102,0])
        self.r.put('SHOTS', 13)               # widest count: no blank cell
        self.r.call('draw_static_hud')
        for power in range(33):
            self.r.put('POWER', power)
            self.r.call('draw_power')
        self.assertEqual(self.r.bus[0x2000:0x2000+22*320], [0x55]*(22*320))
        self.assertEqual(self.r.bus[0x3f40:0x4000], [0x55]*192)
        self.assertEqual(self.r.bus[0x3b80:0x3cc0], [0x55]*320)
        self.assertEqual(self.r.bus[pointer:pointer+8], self.r.bus[0xd000+ord('3')*8:0xd000+ord('3')*8+8])


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


if __name__ == '__main__':
    unittest.main()
