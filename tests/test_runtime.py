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

S = symbols()
PRG = (ROOT/'build/minigolf.prg').read_bytes()
COURSE = json.loads((ROOT/'assets/test-course.json').read_text())


class KeyboardBus(list):
    def __init__(self):
        super().__init__([0]*65536)
        self.pressed = set()
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

    def run_until(self, address, limit=1000000):
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
        renderer = self.r.bus[0x3a40:0x3b80]
        wide = self.r.bus[0x3cc0:0x3e00]
        startup = self.r.bus[0x3f40:0x4000]
        lookup = self.r.bus[S['lookup_image']:S['lookup_image']+320]
        self.r.bus[0x1800:0x4000] = [255]*(0x4000-0x1800)
        self.r.bus[0x3a40:0x3b80] = renderer
        self.r.bus[0x3cc0:0x3e00] = wide
        self.r.bus[0x3f40:0x4000] = startup
        self.r.bus[S['lookup_image']:S['lookup_image']+320] = lookup
        self.r.call('initialise_video')
        luma, colors = [7]*1024,[16]*1024
        colors[40:840] = [1]*800
        luma[840:880] = colors[840:880] = [0]*40
        luma[:40] = colors[:40] = [0]*40
        luma[920:960] = colors[920:960] = [0]*40
        self.assertEqual(self.r.bus[0x1800:0x1c00], luma)
        self.assertEqual(self.r.bus[0x1c00:0x2000], colors)
        self.assertEqual(self.r.bus[0x2000:0x2140],lookup)
        self.assertEqual(self.r.bus[0x2140:0x3a40], [255]*6400)
        self.assertEqual(self.r.bus[0x3b80:0x3cc0], [0]*320)
        self.assertEqual(self.r.bus[0x3e00:0x3f40], [0]*320)
        self.assertEqual(self.r.bus[0x3cc0:0x3e00],wide)
        self.assertEqual(self.r.bus[0x3a40:0x3b80],renderer)
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
        expected = bytearray(8000)
        contours = [COURSE['outline'], *COURSE['obstacles']]
        # Independent point-in-polygon reference, not the scanline export.
        def playable(x, y):
            inside = False
            for contour in contours:
                for a,b in zip(contour, contour[1:]+contour[:1]):
                    if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                        crossing = a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1])
                        if crossing <= x:
                            inside = not inside
            return inside
        for y in range(8,168):
            for x in range(320):
                if not playable(x,y):
                    expected[bitmap_offset(x,y)] |= 128 >> (x%8)
        # Check cell colors before the black cup ring is overlaid: its pixels
        # must not cast a shadow. Hidden code rows stay black/black.
        for row in range(1,21):
            for col in range(40):
                x,y = col*8,row*8
                dark = (not playable(x,y) or not playable(x,y-8) or
                        col == 0 or not playable(x-8,y))
                self.assertEqual(self.r.bus[0x1800+row*40+col],
                                 0x10 if dark else 0x30, (x,y))
                self.assertEqual(self.r.bus[0x1c00+row*40+col],1)
        cx,cy = COURSE['cup']
        for i in range(32):
            x = cx+round(math.cos(i*math.tau/32)*5)
            y = cy+round(math.sin(i*math.tau/32)*5)
            expected[bitmap_offset(x,y)] |= 128 >> (x%8)
        self.assertEqual(bytes(self.r.bus[0x2140:0x3a40]), expected[320:6720])
        self.assertEqual(bytes(self.r.bus[0x3b80:0x3cc0]), expected[7040:7360])
        self.assertEqual(bytes(self.r.bus[0x3e00:0x3f40]), expected[7680:])

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
                        if dx*dx+dy*dy <= 5 and 0 <= x+dx < 320 and 8 <= y+dy < 168:
                            expected[bitmap_offset(x+dx,y+dy)] |= 128 >> ((x+dx)%8)
                self.assertEqual(bytes(self.r.bus[0x2000:0x3f40]),expected,(x,y))
                self.assertLessEqual(self.r.get('DYNAMIC_COUNT'),10)
                self.r.call('restore_dynamic')
                self.assertEqual(self.r.bus[0x2000:0x3f40],[0]*8000)

    def test_all_aim_directions_restore_background_exactly(self):
        pattern = [(i*73+19)%256 for i in range(8000)]
        self.r.bus[0x2000:0x3f40] = pattern
        for angle in range(128):
            self.r.put('ANGLE', angle)
            self.r.call('draw_dynamic')
            self.assertEqual(self.r.get('DYNAMIC_COUNT'), 18)
            self.assertNotEqual(self.r.bus[0x2000:0x3f40], pattern)
            self.r.call('restore_dynamic')
            self.assertEqual(self.r.bus[0x2000:0x3f40], pattern, angle)
        self.r.put('PAUSED', 1)
        self.r.call('draw_dynamic')
        self.assertEqual(self.r.get('DYNAMIC_COUNT'), 10)
        self.r.call('restore_dynamic')
        self.assertEqual(self.r.bus[0x2000:0x3f40], pattern)

    def test_keyboard_rows_and_simultaneous_keys(self):
        keys = [((1,2),1), ((2,2),2), ((1,1),4), ((1,5),8), ((5,1),16), ((7,4),32)]
        for mask in range(64):
            self.r.bus.pressed = {position for position,bit in keys if mask & bit}
            self.r.call('scan_keyboard')
            self.assertEqual(self.r.get('KEY_CURRENT'), mask)
            self.assertEqual(self.r.bus.row, 255)

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

    def test_power_limits_and_opposing_keys(self):
        for power in (1,16,32):
            self.r.put('POWER', power)
            self.r.put('KEY_ACTIONS', 12)
            self.r.call('apply_controls')
            self.assertEqual(self.r.get('POWER'), power)
        for actions, power, expected in [(8,1,1),(4,32,32),(4,1,2),(8,32,31)]:
            self.r.put('POWER', power)
            self.r.put('KEY_ACTIONS', actions)
            self.r.call('apply_controls')
            self.assertEqual(self.r.get('POWER'), expected)
        self.r.put('KEY_ACTIONS', 3)
        self.r.call('apply_controls')
        self.assertEqual(self.r.get('ANGLE'), 0)

    def test_glyph_cell_above_255_and_hud_stays_outside_course(self):
        self.r.bus[0x2000:0x4000] = [0x55]*8192
        self.r.put('TEXT_ROW', 24)
        self.r.put('TEXT_COLUMN', 39)
        self.r.cpu.a = ord('A')
        self.r.call('draw_glyph')
        pointer = 0x2000+bitmap_offset(312,192)
        self.assertEqual(self.r.bus[pointer:pointer+8], [24,60,102,126,102,102,102,0])
        self.r.call('draw_static_hud')
        for power in range(1,33):
            self.r.put('POWER', power)
            self.r.call('draw_power')
        self.assertEqual(self.r.bus[0x2000:0x2000+22*320], [0x55]*(22*320))
        self.assertEqual(self.r.bus[0x3f40:0x4000], [0x55]*192)


class CourseValidationTests(unittest.TestCase):
    def test_valid_test_course(self):
        self.assertEqual(len(validate(COURSE)), 17)

    def test_rejects_invalid_geometry(self):
        cases = [
            [[16,24],[128,25],[128,152],[16,152]],
            [[16,24],[128,24],[128,24],[16,152]],
            [[16,24],[128,24],[100,60],[16,152]],
            [[16,24],[128,136],[16,136],[128,24]],
            [[16,24],[128,24],[64,24],[64,152],[16,152]],
        ]
        for outline in cases:
            course = copy.deepcopy(COURSE)
            course['outline'] = outline
            with self.assertRaises(ValueError):
                validate(course)


if __name__ == '__main__':
    unittest.main()
