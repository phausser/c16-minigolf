"""Deterministic input replays through the real input path.

A replay is a list of joystick runs [mask, frames] for port 1 (4 = left,
8 = right, 16 = fire). Each frame runs scan_keyboard, debounce_keyboard,
apply_controls and physics_tick of the game build, as the main loop does
(drawing does not feed back into physics). The digest is SHA-256 over the
physics state bytes BALL_POS_X..SHOTS after every frame.

`record()` derives the runs from a recorded best line: turn to the angle,
charge to the strength, release and wait until the ball rests.
"""
import hashlib

from test_runtime import Runtime

FRAME = ('scan_keyboard', 'debounce_keyboard', 'apply_controls', 'physics_tick')
LEFT, RIGHT, FIRE = 4, 8, 16


def new_runtime(hole):
    r = Runtime('minigolf')
    r.put('HOLE', hole-1)
    r.call('initialise_video')
    r.call('initialise_state')
    r.call('draw_course')          # water is found by the cell colour
    return r


def step(r, mask):
    r.bus.joysticks = [mask, 0]
    for label in FRAME:
        r.call(label)
    return bytes(r.bus[r.S['BALL_POS_X']:r.S['SHOTS']+1])


def play(hole, runs):
    """Replay the runs; returns (digest, final state bytes, frames)."""
    r = new_runtime(hole)
    digest = hashlib.sha256()
    frames = 0
    state = b''
    for mask, count in runs:
        for _ in range(count):
            state = step(r, mask)
            digest.update(state)
            frames += 1
    return digest.hexdigest(), state.hex(), frames, r


def record(hole, shots, limit=2000):
    """Runs that play `shots` ([angle, power] pairs) like a player would."""
    r = new_runtime(hole)
    runs = []

    def push(mask):
        step(r, mask)
        if runs and runs[-1][0] == mask:
            runs[-1][1] += 1
        else:
            runs.append([mask, 1])

    for angle, power in shots:
        for _ in range(limit):
            if r.get('ANGLE') == angle:
                break
            turn = (angle-r.get('ANGLE')) % 128
            push(RIGHT if turn < 64 else LEFT)
        else:
            raise RuntimeError('aim never reached')
        for _ in range(4):
            push(0)                    # release: the turn must not repeat
        for _ in range(limit):
            if r.get('ANGLE') == angle:
                break
            push(RIGHT if (angle-r.get('ANGLE')) % 128 < 64 else LEFT)
            push(0)
            push(0)
        shots = r.get('SHOTS')
        while r.get('POWER') < power or not r.get('CHARGING'):
            push(FIRE)
        while r.get('SHOTS') == shots:   # may hole out in the shot's own frame
            push(0)
        while r.get('ROLLING'):
            push(0)
        for _ in range(2):
            push(0)
    return runs
