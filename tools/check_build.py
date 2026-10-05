"""Verify load/runtime memory contracts against the actual assembler output."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


# Tests, smoke runs and profiles use the test-course build.
TEST_BUILD = 'minigolf-test'


def symbols(name=TEST_BUILD):
    return {n: int(v,16) for n,v in re.findall(
        r'^\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)',
        (ROOT/f'build/{name}.sym').read_text(), re.M)}


def check(name='minigolf'):
    s = symbols(name)
    prg = (ROOT/f'build/{name}.prg').read_bytes()
    load = int.from_bytes(prg[:2], 'little')
    assert load == 0x1001 and s['loader'] == 4109, 'BASIC SYS entry mismatch'
    assert s['RELOCATOR_BASE'] <= s['relocate'] < s['relocator_end'] <= s['RUNTIME_BASE']
    assert s['runtime_end'] <= s['RUNTIME_LIMIT'] == s['CLASS_SENTINEL']
    assert s['relocator_end'] <= s['STACK_FLOOR']
    assert s['DYNAMIC_OLD']+s['MAX_DYNAMIC_CELLS'] <= s['STACK_FLOOR']
    assert load+len(prg)-2 == s['load_end'] <= 0x4000
    assert s['payload_image'] >= s['RUNTIME_BASE']+s['relocator_end']-s['RELOCATOR_BASE']
    assert s['payload_end']-s['payload_image'] == s['runtime_end']-s['RUNTIME_BASE']
    report = {
        'load_address': load, 'prg_bytes': len(prg),
        'runtime_start': s['RUNTIME_BASE'], 'runtime_end_exclusive': s['runtime_end'],
        'runtime_bytes': s['runtime_end']-s['RUNTIME_BASE'],
        'runtime_free_bytes': s['RUNTIME_LIMIT']-s['runtime_end'],
        'stack_page_buffer_bytes': s['DYNAMIC_OLD']+s['MAX_DYNAMIC_CELLS']-s['DYNAMIC_LO'],
        'stack_page_free_bytes': s['STACK_FLOOR']-s['DYNAMIC_OLD']-s['MAX_DYNAMIC_CELLS'],
        'stack_reserved_bytes': 0x200-s['STACK_FLOOR'],
        'attribute_bytes': 1024,
        'screen_bytes': 1024,
        'charset_bytes': 1024,
        'scratch_bytes': s['SCRATCH_END']-s['SCRATCH_BASE'],
    }
    suffix = '' if name == 'minigolf' else '-test'
    (ROOT/f'build/memory{suffix}.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f"{name} runtime: {report['runtime_bytes']} bytes, {report['runtime_free_bytes']} bytes free before attributes; PRG: {len(prg)} bytes")


if __name__ == '__main__':
    import sys
    check(*sys.argv[1:])
