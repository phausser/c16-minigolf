"""Measure assembled arithmetic against integer references (CPU cycles, no TED)."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from test_runtime import Runtime, S


def write(r, name, value, size):
    value &= (1 << (size * 8)) - 1
    r.bus[S[name]:S[name]+size] = list(value.to_bytes(size, 'little'))


def read(r, name, size, signed=False, offset=0):
    return int.from_bytes(bytes(r.bus[S[name]+offset:S[name]+offset+size]),
                          'little', signed=signed)


def benchmark():
    r = Runtime()
    rows = []
    values = (-2048, -1024, -724, -257, -256, -1, 0, 1, 255, 256, 724, 1024, 2048)
    factors = (-256, -255, -181, -128, -1, 0, 1, 127, 128, 181, 255, 256)
    for a in values:
        for b in factors:
            for routine in ('multiply_signed', 'multiply_unit'):
                write(r, 'M_A', a, 2)
                write(r, 'M_B', b, 2)
                cycles = r.call(routine)
                actual = read(r, 'M_PRODUCT', 4, signed=True)
                assert actual == a*b, (routine, a, b, actual)
                rows.append(dict(routine=routine, a=a, b=b, cycles=cycles))
        for b in (0, 1, 127, 128, 181, 254, 255):
            write(r, 'M_A', a, 2)
            write(r, 'M_B', b, 2)
            cycles = r.call('multiply_fraction')
            actual = read(r, 'M_PRODUCT', 2, signed=True, offset=1)
            assert actual == a*b//256, ('multiply_fraction', a, b, actual)
            rows.append(dict(routine='multiply_fraction', a=a, b=b, cycles=cycles))
    # 24-bit doubling must not overflow: denominator <= 2**23.
    for denominator in (1, 255, 256, 724, 1024, 32767, 32768, 32769, 65535, 65536, 200000, 8388608):
        for numerator in sorted({0, denominator//4, denominator//2, denominator-1}):
            write(r, 'M_REM', numerator, 3)
            write(r, 'M_DEN', denominator, 3)
            cycles = r.call('divide_fraction')
            actual = read(r, 'M_QUOT', 2)
            assert actual == numerator*256//denominator, (numerator, denominator, actual)
            assert read(r, 'M_REM', 3) == numerator*256 % denominator
            rows.append(dict(routine='divide_fraction', numerator=numerator,
                             denominator=denominator, cycles=cycles))
    summary = {}
    for routine in sorted({row['routine'] for row in rows}):
        cases = [row for row in rows if row['routine'] == routine]
        summary[routine] = dict(cases=len(cases), min_cycles=min(x['cycles'] for x in cases),
                                max_cycles=max(x['cycles'] for x in cases),
                                slowest=max(cases, key=lambda x: x['cycles']))
    report = dict(measurement='py65 CPU cycles including RTS/internal JSR, excluding outer JSR and TED stalls',
                  scope='deterministic boundary/sample matrix; not an exhaustive worst-case proof',
                  summary=summary, samples=rows)
    (ROOT/'build/math-benchmark.json').write_text(json.dumps(report, indent=2)+'\n')
    for routine, result in summary.items():
        print(f"{routine}: {result['cases']} verified cases, {result['min_cycles']}..{result['max_cycles']} CPU cycles")
    return report


if __name__ == '__main__':
    benchmark()
