"""Independent floating-point model of the SPEC physics, plus a 6502 probe.

The reference knows only the course geometry (the JSON contours) and the
rules written in SPEC.md: a ball of radius 2 px swept continuously against
finite segments and their end points, mirror reflection with the SPEC speed
loss, constant radial braking, the cup catch and the cup rim. It shares no
code and no fixed-point formats with the 6502 kernel.

`frame()` advances one 50 Hz step from a given state. Comparing it frame by
frame with the kernel (started from the kernel's own state) bounds the
kernel error per step without letting chaotic bounces amplify differences.
"""
from dataclasses import dataclass, field
import math

RADIUS = 2.0
ROLL_DECEL = 4            # SPEED units (1/256 px per frame) per frame
MAX_CONTACTS = 4
CATCH_RADIUS = 3.0
CATCH_SPEED = 192         # SPEED units: 0.75 px per frame
RIM_RADIUS = 5.5
RIM_TURN = 1/64           # radians per frame


@dataclass
class Segment:
    a: tuple
    b: tuple
    normal: tuple          # unit normal pointing into the playable side


def course_segments(course):
    """Segments with inward unit normals from the contours alone."""
    segments = []
    contours = [course['outline'], *course['obstacles']]
    for index, contour in enumerate(contours):
        area = sum(p[0]*q[1]-p[1]*q[0] for p, q in zip(contour, contour[1:]+contour[:1]))
        for a, b in zip(contour, contour[1:]+contour[:1]):
            dx, dy = b[0]-a[0], b[1]-a[1]
            length = math.hypot(dx, dy)
            # Screen y grows downwards. For the outline the playable side is
            # inside; for obstacles it is outside.
            nx, ny = -dy/length, dx/length
            if (area > 0) != (index == 0):
                nx, ny = -nx, -ny
            segments.append(Segment(tuple(a), tuple(b), (nx, ny)))
    return segments


def playable(course, x, y):
    """Even-odd point test against all contours (exact for the centre)."""
    inside = False
    for contour in [course['outline'], *course['obstacles']]:
        for a, b in zip(contour, contour[1:]+contour[:1]):
            if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                if a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]) <= x:
                    inside = not inside
    return inside


def closest_point(segment, x, y):
    (ax, ay), (bx, by) = segment.a, segment.b
    dx, dy = bx-ax, by-ay
    t = max(0.0, min(1.0, ((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
    return ax+t*dx, ay+t*dy


def clearance(segments, x, y):
    """Distance from the ball centre to the nearest wall point."""
    return min(math.dist((x, y), closest_point(s, x, y)) for s in segments)


@dataclass
class State:
    x: float
    y: float
    ux: float
    uy: float
    speed: float           # SPEED units, 256 = 1 px per frame
    rolling: bool = True
    holed: bool = False
    contacts: int = 0
    limit: bool = False
    events: list = field(default_factory=list)


def _earliest_contact(segments, x, y, vx, vy, horizon):
    """First time in [0, horizon] at which the swept circle touches a wall
    while approaching it. Returns (t, nx, ny, kind) or None.

    Simultaneous contacts (SPEC): two wall faces whose normals are 45
    degrees apart, reached in the same 1/256 step of the remaining motion,
    are one joint contact at the normal halfway between them."""
    contacts = _contacts(segments, x, y, vx, vy, horizon)
    if not contacts:
        return None
    first = min(contacts, key=lambda c: c[0])
    if first[3] == 'face':
        step = math.floor(256*first[0]/horizon) if horizon else 0
        for t, nx, ny, kind in contacts:
            if kind == 'face' and math.floor(256*t/horizon) == step and \
                    abs(nx*first[1]+ny*first[2]-math.sqrt(.5)) < 1e-9:
                jx, jy = nx+first[1], ny+first[2]
                length = math.hypot(jx, jy)
                return (first[0], jx/length, jy/length, 'joint')
    return first


def _contacts(segments, x, y, vx, vy, horizon):
    """All wall contacts within the horizon: (t, nx, ny, kind)."""
    found = []
    for s in segments:
        (ax, ay), (bx, by) = s.a, s.b
        nx, ny = s.normal
        # Face: distance to the line along the inward normal.
        approach = vx*nx+vy*ny
        if approach < 0:
            gap = (x-ax)*nx+(y-ay)*ny-RADIUS
            t = max(0.0, -gap/approach) if gap > -1e-6 else None
            if t is not None and t <= horizon:
                cx, cy = x+vx*t-nx*RADIUS, y+vy*t-ny*RADIUS
                dx, dy = bx-ax, by-ay
                along = ((cx-ax)*dx+(cy-ay)*dy)/(dx*dx+dy*dy)
                if 0 <= along <= 1:
                    found.append((t, nx, ny, 'face'))
        # End points as circles of radius RADIUS around the vertex.
        for px, py in (s.a, s.b):
            qx, qy = x-px, y-py
            a = vx*vx+vy*vy
            if a == 0:
                continue
            b = 2*(qx*vx+qy*vy)
            c = qx*qx+qy*qy-RADIUS*RADIUS
            if b >= 0:
                continue               # not approaching the vertex
            disc = b*b-4*a*c
            if disc < 0:
                continue
            t = max(0.0, (-b-math.sqrt(disc))/(2*a))
            if t <= horizon:
                ex, ey = qx+vx*t, qy+vy*t
                length = math.hypot(ex, ey)
                found.append((t, ex/length, ey/length, 'vertex'))
    return found


def _cup_on_path(cup, x, y, vx, vy, horizon):
    qx, qy = x-cup[0], y-cup[1]
    a = vx*vx+vy*vy
    t = 0.0 if a == 0 else max(0.0, min(horizon, -(qx*vx+qy*vy)/a))
    return math.hypot(qx+vx*t, qy+vy*t) < CATCH_RADIUS


def reflect(state, nx, ny):
    """SPEC reflection: mirror the unit direction, lose speed."""
    d = state.ux*nx+state.uy*ny
    state.ux -= 2*d*nx
    state.uy -= 2*d*ny
    state.speed -= state.speed*d*d*31/512+state.speed/128+1
    state.speed = max(state.speed, 0.0)


def frame(state, segments, cup):
    """One 50 Hz step of the SPEC rules. Mutates and returns state."""
    if not state.rolling or state.holed:
        return state
    state.events = []
    remaining = 1.0
    state.contacts = 0
    state.limit = False
    while True:
        vx, vy = state.ux*state.speed/256, state.uy*state.speed/256
        if vx == 0 and vy == 0:
            break
        hit = _earliest_contact(segments, state.x, state.y, vx, vy, remaining)
        horizon = hit[0] if hit else remaining
        if state.speed <= CATCH_SPEED and _cup_on_path(cup, state.x, state.y, vx, vy, horizon):
            state.x, state.y = float(cup[0]), float(cup[1])
            state.holed = True
            state.rolling = False
            state.speed = 0
            state.events.append('cup')
            return state
        if not hit:
            state.x += vx*remaining
            state.y += vy*remaining
            break
        t, nx, ny, kind = hit
        state.x += vx*t
        state.y += vy*t
        remaining -= t
        reflect(state, nx, ny)
        state.contacts += 1
        state.events.append(kind)
        if state.contacts == MAX_CONTACTS:
            state.limit = True
            break
    if state.contacts == 0:
        qx, qy = state.x-cup[0], state.y-cup[1]
        if math.hypot(qx, qy) < RIM_RADIUS:
            side = state.ux*qy-state.uy*qx
            if side:
                turn = RIM_TURN if side < 0 else -RIM_TURN
                c, s = math.cos(turn), math.sin(turn)
                state.ux, state.uy = c*state.ux-s*state.uy, s*state.ux+c*state.uy
            state.speed = max(0.0, state.speed-state.speed/128-1)
            state.events.append('rim')
    if state.speed <= ROLL_DECEL:
        state.speed = 0
        state.rolling = False
    else:
        state.speed -= ROLL_DECEL
    return state


# --- 6502 probe -----------------------------------------------------------

def kernel_state(r):
    S, bus = r.S, r.bus
    x = (bus[S['BALL_POS_X']]+256*bus[S['BALL_POS_X']+1]+65536*bus[S['BALL_POS_X']+2])/256
    y = (bus[S['BALL_POS_Y']]+256*bus[S['BALL_POS_Y']+1])/256

    def signed(name):
        v = bus[S[name]]+256*bus[S[name]+1]
        return v-65536 if v & 0x8000 else v
    return State(x, y, signed('UNIT_X')/256, signed('UNIT_Y')/256,
                 bus[S['SPEED']]+256*bus[S['SPEED']+1],
                 bool(r.get('ROLLING')), bool(r.get('HOLED')))


def kernel_bytes(r):
    """The physics state as raw bytes: position, velocity, speed, unit, flags."""
    S = r.S
    return bytes(r.bus[S['BALL_POS_X']:S['SHOTS']+1])
