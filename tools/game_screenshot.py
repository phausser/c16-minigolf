"""README screenshot of the real game build in VICE (C16, PAL, 16 KB).

Starts build/minigolf.prg, switches to hole 18 before it is drawn, sets an
aim, a half-charged bar and two strokes, and saves preview.png at 2x size.
"""
import argparse
from pathlib import Path
import subprocess
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from check_build import symbols


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    s = symbols('minigolf')
    frame = f"until ${s['frame_begin']:04x}"
    raw = ROOT/'build/preview-raw.png'
    raw.unlink(missing_ok=True)
    commands = ['delete 1', f"until ${s['start_hole']:04x}", f"> ${s['HOLE']:04x} 11",
                *[frame]*4,
                f"> ${s['ANGLE']:04x} 7e", f"> ${s['POWER']:04x} 15", f"> ${s['SHOTS']:04x} 02",
                f"> ${s['HUD_DIRTY']:04x} 03", f"> ${s['DIRTY']:04x} 01",
                *[frame]*3, f'screenshot "{raw}" 2', 'quit']
    script = ROOT/'build/vice-preview.mon'
    script.write_text('\n'.join(commands)+'\n')
    subprocess.run(['xplus4', '-silent', '-default', '-console', '-model', 'c16', '-pal',
                    '-ramsize', '16', '-sounddev', 'dummy', '-warp', '-autostartprgmode', '1',
                    '-autostart', str(ROOT/'build/minigolf.prg'), '-initbreak', '0x0200',
                    '-moncommands', str(script), '-limitcycles', '30000000'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    image = Image.open(raw)
    image.resize((image.width*2, image.height*2), Image.NEAREST).save(ROOT/'preview.png')
    print(f'Screenshot: {ROOT/"preview.png"}')


if __name__ == '__main__':
    main()
