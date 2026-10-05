"""Report the static character count of every draft, from the text-mode kernel."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'tests')]
from test_runtime import Runtime


def main():
    game = Runtime('minigolf')
    game.call('initialise_video')
    worst = 0
    for hole, path in enumerate(sorted((ROOT/'assets/courses').glob('*.json'))):
        course = json.loads(path.read_text())
        game.put('HOLE', hole)
        game.call('initialise_state')
        game.call('draw_course')
        count, overflow = game.get('pattern_count'), game.get('pattern_overflow')
        worst = max(worst, count)
        print(f"{path.stem} {course['name']:28} {count:3}/64  overflow {overflow}")
    print(f'worst course: {worst} distinct static characters')


if __name__ == '__main__':
    main()
