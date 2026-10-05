"""Profile actual 6502 physics calls; CPU cycles exclude TED display stalls."""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests'))
from test_runtime import Runtime, S

ROUTINES = ('physics_tick', 'collect_candidates', 'find_first_contact', 'try_line',
            'try_circle', 'square_circle', 'square_q', 'square_small', 'multiply_signed',
            'multiply_unit', 'multiply_fraction', 'divide_fraction',
            'circle_at_trial', 'reflect_unit', 'reflect_speed_loss',
            'velocity_from_unit', 'displacement_at_t')
NAMES = {S[name]:name for name in ROUTINES}


def profile_call(r, label):
    cpu = r.cpu
    cpu.sp = 255
    cpu.stPushWord(0xefff)
    cpu.pc = S[label]
    begin = cpu.processorCycles
    stack = [(label, begin)]
    costs = defaultdict(lambda: dict(calls=0, inclusive_cycles=0, exclusive_cycles=0))
    for _ in range(1000000):
        if cpu.pc == 0xf000:
            assert not stack, 'unbalanced profile call stack'
            assert sum(cost['exclusive_cycles'] for cost in costs.values()) == cpu.processorCycles-begin
            return cpu.processorCycles-begin, dict(costs)
        pc = cpu.pc
        opcode = r.bus[pc]
        callee = None
        if opcode == 0x20:
            target = r.bus[pc+1] | r.bus[pc+2] << 8
            callee = NAMES.get(target, f'${target:04x}')
        before = cpu.processorCycles
        cpu.step()
        costs[stack[-1][0]]['exclusive_cycles'] += cpu.processorCycles-before
        if callee is not None:
            stack.append((callee, cpu.processorCycles))
        elif opcode == 0x60:
            name, start = stack.pop()
            costs[name]['calls'] += 1
            costs[name]['inclusive_cycles'] += cpu.processorCycles-start
    raise AssertionError('profile did not return')


def write(r, name, value, size=2):
    r.bus[S[name]:S[name]+size] = [(value >> (8*i)) & 255 for i in range(size)]


def main():
    report = dict(measurement='py65 CPU cycles; no TED stalls; inclusive totals overlap', cases={})
    for name, x, y, angle in (('rounded-corner',124,84,16),
                              ('oblique-corner',124,83,17),
                              ('shallow-corner',123,84,14)):
        r = Runtime()
        r.call('initialise_state')
        write(r, 'BALL_POS_X', round(x*256), 3)
        write(r, 'BALL_POS_Y', round(y*256))
        r.put('ANGLE', angle)
        r.put('POWER', 32)
        r.call('start_shot')
        frames = []
        for _ in range(7):
            cycles, routines = profile_call(r, 'physics_tick')
            frames.append(dict(cycles=cycles, routines=routines,
                               state=r.bus[S['BALL_POS_X']:S['STATE_END']]))
        report['cases'][name] = frames
        worst = max(frames, key=lambda frame:frame['cycles'])
        print(f"{name}: worst physics {worst['cycles']} CPU cycles")
        for routine, cost in sorted(worst['routines'].items(),
                                    key=lambda item:item[1]['inclusive_cycles'], reverse=True)[:8]:
            print(f"  {routine}: {cost['calls']} calls, {cost['inclusive_cycles']} inclusive, {cost['exclusive_cycles']} exclusive")
    (ROOT/'build/sweep-profile.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
