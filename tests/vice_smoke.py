"""Real C16 PAL/16-KB ROM boot, bitmap, frame timing and control/render smoke.

Control events are injected AFTER the physical scan/debouncer. Keyboard-matrix
behavior is tested separately in py65; this is not a real hardware key test.
"""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from check_build import symbols


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare-only', action='store_true')
    mode.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    s = symbols()
    prefix = ROOT/'build/vice-pal'
    commands = ['delete 1', f"until ${s['frame_begin']:04x}",
                f"until ${s['frame_begin']:04x}",
                f"until ${s['frame_begin']:04x}",
                f'bsave "{prefix}-attributes.bin" 0 $1800 $1fff',
                f'bsave "{prefix}-video.bin" 0 $ff06 $ff14',
                f'bsave "{prefix}-bitmap.bin" 0 $2000 $3f3f',
                f'screenshot "{prefix}.png" 2',
                'stopwatch reset', f"until ${s['frame_begin']:04x}", 'stopwatch']
    events = [0,1,2,4,8,16,16,0,16]
    for index,event in enumerate(events):
        commands += [f"until ${s['apply_controls']:04x}",
                     f"> ${s['KEY_ACTIONS']:04x} {event:02x}",
                     f"> ${s['DIRTY']:04x} 01", 'stopwatch reset',
                     f"until ${s['frame_done']:04x}", 'stopwatch',
                     f'bsave "{prefix}-state-{index}.bin" 0 $0020 $002d',
                     f'bsave "{prefix}-frame-{index}.bin" 0 $2000 $3f3f']
    # Exhaustive dirty renders exercise both signs and all table entries.
    for angle in range(128):
        commands += [f"until ${s['frame_begin']:04x}",
                     f"> ${s['ANGLE']:04x} {angle:02x}",
                     f"> ${s['PAUSED']:04x} 00", f"> ${s['DIRTY']:04x} 01",
                     'stopwatch reset', f"until ${s['frame_done']:04x}", 'stopwatch']
    shot_cases = [
        ('straight',64,112,0), ('vertical-wall',18.5,112,64),
        ('diagonal-wall',292,40,0), ('rounded-corner',124,80,16),
        ('double-corner',18.5,26.5,80), ('neck',160,78,0),
        ('oblique-corner',124,79,17), ('shallow-corner',123,80,14),
    ]
    for index,(name,x,y,angle) in enumerate(shot_cases):
        commands += [f"until ${s['apply_controls']:04x}",
                     f"> ${s['BALL_POS_X']:04x} {round(x*256)&255:02x} {int(x)&255:02x} {int(x)>>8:02x}",
                     f"> ${s['BALL_POS_Y']:04x} {round(y*256)&255:02x} {int(y):02x}",
                     f"> ${s['ANGLE']:04x} {angle:02x}", f"> ${s['POWER']:04x} 20",
                     f"> ${s['ROLLING']:04x} 00 00", f"> ${s['PAUSED']:04x} 00",
                     f"> ${s['KEY_ACTIONS']:04x} 20", 'stopwatch reset',
                     f"until ${s['frame_done']:04x}", 'stopwatch',
                     f'bsave "{prefix}-shot-{index}.bin" 0 $0038 $004c']
        # Include sustained motion after the first contact and changing speed.
        for _ in range(6):
            commands += [f"until ${s['frame_begin']:04x}", 'stopwatch reset',
                         f"until ${s['frame_done']:04x}", 'stopwatch']
    commands += [f"until ${s['frame_begin']:04x}",
                 f"until ${s['frame_begin']:04x}",
                 f'screenshot "{prefix}-aim.png" 2', 'quit']
    script = prefix.with_suffix('.mon')
    log = prefix.with_suffix('.log')
    if not args.verify_only:
        script.write_text('\n'.join(commands)+'\n')
        log.write_text('')
    if args.prepare_only:
        return
    text = log.read_text(encoding='latin1')
    assert 'ERROR' not in text and 'not a valid checkpoint' not in text, log
    attrs = Path(f'{prefix}-attributes.bin').read_bytes()
    expected_attrs = bytearray(bytes([7])*1024+bytes([16])*1024)
    expected_attrs[840:880] = bytes(40)
    expected_attrs[1024+840:1024+880] = bytes(40)
    expected_attrs[920:960] = bytes(40)
    expected_attrs[1024+920:1024+960] = bytes(40)
    expected_attrs[:40] = bytes(40)
    expected_attrs[1024:1024+40] = bytes(40)
    # Cell shadows are independently checked against geometry in py65.
    # VICE checks the same RAM palette, with protected rows/HUD unchanged.
    expected_attrs[40:840] = attrs[40:840]
    expected_attrs[1024+40:1024+840] = bytes([1])*800
    assert set(attrs[40:840]) == {0x10,0x30}, 'gray surfaces and cell shadows'
    assert attrs == expected_attrs, 'hires colors/luminance/hidden code row'
    video = Path(f'{prefix}-video.bin').read_bytes()
    assert video[0] & 0x7f == 0x3b, 'bitmap/display/25-row configuration'
    assert video[1] & 0x7f == 8, 'PAL hires 40-column configuration'
    assert video[12] & 0x3c == 8, 'RAM bitmap at $2000'
    assert video[14] & 0xf8 == 0x18, 'attribute matrix at $1800'
    assert video[4] & 0x5e == 0, 'all TED interrupt sources disabled'
    initial = Path(f'{prefix}-bitmap.bin').read_bytes()
    # First 22 bitmap cell rows must be unchanged by power/pause/HUD updates.
    states = []
    for index in range(len(events)):
        states.append(Path(f'{prefix}-state-{index}.bin').read_bytes())
    expected = [(0,16,0),(127,16,0),(0,16,0),(0,17,0),(0,16,0),
                (0,16,1),(0,16,0),(0,16,0),(0,16,1)]
    assert [tuple(state[:3]) for state in states] == expected, states
    assert Path(f'{prefix}-frame-0.bin').read_bytes() == initial, 'redraw changed background'
    assert Path(f'{prefix}-frame-2.bin').read_bytes() == initial, 'angle restoration failed'
    assert Path(f'{prefix}-frame-4.bin').read_bytes() == initial, 'power restoration failed'
    assert Path(f'{prefix}-frame-6.bin').read_bytes() == initial, 'pause restoration failed'
    measurements = [int(v) for v in re.findall(r'Stopwatch:\s+(\d+)', text)]
    assert len(measurements) == 1+len(events)+128+len(shot_cases)*7, f'unexpected timing output: {measurements}'
    period, frames = measurements[0], measurements[1:]
    assert 35000 <= period <= 36000, f'PAL frame period: {period}'
    shot_times = frames[len(events)+128:]
    for index in range(len(shot_cases)):
        state = Path(f'{prefix}-shot-{index}.bin').read_bytes()
        assert state[19] == 0, (shot_cases[index][0], 'contact limit reached', state)
    budget = min(32000,period*9//10)
    timings = {'pal_frame_ticks':period, 'frame_budget_ticks':budget, 'worst_control_render_ticks':max(frames[:len(events)+128]),
               'worst_fraction_of_frame':round(max(frames)/period,4),
               'worst_physics_frame_ticks':max(shot_times),
               'shot_cases': {case[0]:max(shot_times[i*7:i*7+7]) for i,case in enumerate(shot_cases)},
               'frame_budget_passed':max(frames) <= budget, 'angles_measured':128, 'hardware':'VICE 3.x C16 PAL, 16 KB'}
    (ROOT/'build/timing.json').write_text(json.dumps(timings,indent=2)+'\n')
    assert max(frames) <= budget, f'frame budget exceeded: {max(frames)} > {budget} (PAL period {period}); measurements saved to build/timing.json'
    print(f'VICE C16 PAL/16 KB: ROM boot, hires, controls, pause and 128 dirty renders passed; '
          f'worst {max(frames)}/{period} ticks ({max(frames)/period:.1%})')
    print(f'Screenshot: {prefix}.png')


if __name__ == '__main__':
    main()
