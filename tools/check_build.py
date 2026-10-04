"""Verify load/runtime memory contracts against the actual assembler output."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def symbols():
    return {n: int(v,16) for n,v in re.findall(
        r'^\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)',
        (ROOT/'build/minigolf.sym').read_text(), re.M)}


def check():
    s = symbols()
    prg = (ROOT/'build/minigolf.prg').read_bytes()
    load = int.from_bytes(prg[:2], 'little')
    assert load == 0x1001 and s['loader'] == 4109, 'BASIC SYS entry mismatch'
    assert s['RELOCATOR_BASE'] <= s['relocate'] < s['relocator_end'] <= s['RUNTIME_BASE']
    assert s['runtime_end'] <= s['RUNTIME_LIMIT'] <= s['DYNAMIC_LO']
    assert s['DYNAMIC_OLD']+32 <= s['SCRATCH_END'] == s['LUMINANCE_BASE']
    assert load+len(prg)-2 == s['load_end'] <= 0x4000
    assert s['payload_image'] >= s['RUNTIME_BASE']+s['relocator_end']-s['RELOCATOR_BASE']
    assert s['load_end']-s['payload_image'] == s['runtime_end']-s['RUNTIME_BASE']
    report = {
        'load_address': load, 'prg_bytes': len(prg),
        'runtime_start': s['RUNTIME_BASE'], 'runtime_end_exclusive': s['runtime_end'],
        'runtime_bytes': s['runtime_end']-s['RUNTIME_BASE'],
        'runtime_free_bytes': s['RUNTIME_LIMIT']-s['runtime_end'],
        'renderer_scratch_reserved_bytes': s['SCRATCH_END']-s['DYNAMIC_LO'],
        'attribute_bytes': 2048, 'bitmap_reserved_bytes': 8192,
    }
    (ROOT/'build/memory.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f"Runtime: {report['runtime_bytes']} bytes, {report['runtime_free_bytes']} bytes free before scratch; PRG: {len(prg)} bytes")


if __name__ == '__main__':
    check()
