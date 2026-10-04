"""Behavioral tests of the assembled kernel against independent arithmetic
and geometric expectations. py65 is not the hardware timing authority.
"""
import math
import random
import unittest

from test_runtime import Runtime, S


def unsigned(r, name, size=2):
    return sum(r.bus[S[name]+i] << (8*i) for i in range(size))


def signed(r, name, size=2):
    n = unsigned(r,name,size)
    return n-(1 << (8*size)) if n & (1 << (8*size-1)) else n


def put(r, name, value, size=2):
    for i in range(size):
        r.bus[S[name]+i] = (value >> (8*i)) & 255


def position(r, x, y):
    put(r,'BALL_POS_X',round(x*256),3)
    put(r,'BALL_POS_Y',round(y*256))


def point(r):
    return unsigned(r,'BALL_POS_X',3)/256, unsigned(r,'BALL_POS_Y')/256


def isolate_segments(r, segments):
    """Keep the real narrowphase; patch only the broadphase to a fixed list."""
    address = S['collect_candidates']
    code = [0xa5,S['BALL_POS_X']+2,0x4a,0xa5,S['BALL_POS_X']+1,0x6a,0x85,S['BOUNDS_X'],
            0xa5,S['BALL_POS_Y']+1,0x4a,0x85,S['BOUNDS_Y'],
            0xa9,len(segments),0x85,S['CANDIDATE_COUNT'],0x60]
    r.bus[address:address+len(code)] = code
    for i,(a,b,normal) in enumerate(segments):
        r.bus[S['CANDIDATES']+i] = i*5
        r.bus[S['course_segments']+i*5:S['course_segments']+i*5+5] = [a[0]//2,a[1]//2,b[0]//2,b[1]//2,normal]


class ArithmeticTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime()
        self.r.call('initialise_state')

    def test_signed_multiply_matches_integer_reference(self):
        rng = random.Random(16)
        pairs = [(a,b) for a in (-32768,-1024,-1,0,1,256,32767)
                 for b in (-32768,-256,-1,0,1,256,32767)]
        pairs += [(rng.randrange(-32768,32768),rng.randrange(-32768,32768)) for _ in range(100)]
        for a,b in pairs:
            put(self.r,'M_A',a)
            put(self.r,'M_B',b)
            self.r.call('multiply_signed')
            self.assertEqual(signed(self.r,'M_PRODUCT',4), a*b, (a,b))

    def test_optimized_unit_multiply_is_bit_exact(self):
        rng = random.Random(7360)
        pairs = [(a,b) for a in (-2048,-1024,-1,0,1,1024,2048)
                 for b in (-256,-181,-1,0,1,181,256)]
        pairs += [(rng.randrange(-2048,2049),rng.randrange(-256,257)) for _ in range(200)]
        for a,b in pairs:
            put(self.r,'M_A',a)
            put(self.r,'M_B',b)
            self.r.call('multiply_unit')
            self.assertEqual(signed(self.r,'M_PRODUCT',4),a*b,(a,b))

    def test_optimized_speed_root_is_exact(self):
        rng = random.Random(264)
        values = [0,1,65536,1048576,2097152,4194303]
        values += [rng.randrange(4194304) for _ in range(200)]
        for value in values:
            put(self.r,'M_PRODUCT',value,4)
            self.r.call('sqrt_speed')
            self.assertEqual(unsigned(self.r,'M_QUOT'),math.isqrt(value),value)

    def test_diagonal_normalization_error_is_bounded_without_energy_gain(self):
        for value in range(1,725):
            for sx,sy in ((1,1),(-1,1),(1,-1),(-1,-1)):
                put(self.r,'VELOCITY_X',sx*value)
                put(self.r,'VELOCITY_Y',sy*value)
                self.r.call('normalize_velocity')
                exact = math.isqrt(2*value*value)
                speed = unsigned(self.r,'SPEED')
                self.assertLessEqual(speed,exact)
                self.assertLessEqual(exact-speed,1)
                self.assertEqual(signed(self.r,'UNIT_X'),sx*181)
                self.assertEqual(signed(self.r,'UNIT_Y'),sy*181)

    def test_fraction_matches_exact_division(self):
        rng = random.Random(18)
        for den in [1,2,3,256,511,32767,32768,32769,65535,65536,0x600000,0x800000]+[rng.randrange(1,0x700000) for _ in range(60)]:
            for num in (0, den//2, den-1):
                put(self.r,'M_DEN',den,3)
                put(self.r,'M_REM',num,3)
                self.r.call('divide_fraction')
                self.assertEqual(unsigned(self.r,'M_QUOT'),num*256//den,(num,den))
                self.assertEqual(unsigned(self.r,'M_REM',3),num*256 % den,(num,den))

    def test_lookup_squares_are_exact_for_all_bounded_inputs(self):
        for value in range(-2048,2049):
            put(self.r,'M_A',value)
            self.r.call('square_small')
            self.assertEqual(unsigned(self.r,'M_PRODUCT',4),value*value,value)

    def test_short_circle_predicate_matches_exact_integer_squares(self):
        rng = random.Random(7360)
        for radius in (512, 768):
            put(self.r, 'RADIUS_SQUARED', radius*radius, 4)
            cases = [(x,y) for x in (-radius-1,-radius,-radius+1,-1,0,1,radius-1,radius,radius+1)
                     for y in (-radius,-1,0,1,radius)]
            cases += [(rng.randrange(-2815,2816),rng.randrange(-2815,2816)) for _ in range(500)]
            for x,y in cases:
                put(self.r, 'QX', x)
                put(self.r, 'QY', y)
                self.r.call('square_circle')
                self.assertEqual(bool(self.r.cpu.p & 1), x*x+y*y < radius*radius, (radius,x,y))
                self.assertEqual(signed(self.r,'QX'),x)
                self.assertEqual(signed(self.r,'QY'),y)

    def test_cardinal_normalization_and_axis_restitution(self):
        for axis, other, unit, other_unit, normal in (
            ('VELOCITY_X', 'VELOCITY_Y', 'UNIT_X', 'UNIT_Y', 'NX'),
            ('VELOCITY_Y', 'VELOCITY_X', 'UNIT_Y', 'UNIT_X', 'NY')):
            for velocity in (-1024, -257, -256, -1, 1, 255, 256, 1024):
                put(self.r, axis, velocity)
                put(self.r, other, 0)
                put(self.r, 'UNIT_X', 123)
                put(self.r, 'UNIT_Y', 456)
                self.r.call('normalize_velocity')
                self.assertEqual(unsigned(self.r, 'SPEED'), abs(velocity))
                self.assertEqual(signed(self.r, unit), 256 if velocity > 0 else -256)
                self.assertEqual(signed(self.r, other_unit), 0)
                put(self.r, 'NX', 0)
                put(self.r, 'NY', 0)
                put(self.r, normal, 256 if velocity < 0 else -256)
                self.r.call('reflect_velocity')
                self.assertEqual(signed(self.r, axis), velocity//16-velocity)
                self.assertEqual(signed(self.r, other), 0)

    def test_all_128_unit_vectors(self):
        for angle in range(128):
            self.r.put('ANGLE',angle)
            self.r.put('POWER',32)
            self.r.call('start_shot')
            vx,vy = signed(self.r,'VELOCITY_X'),signed(self.r,'VELOCITY_Y')
            self.assertLessEqual(abs(vx/256-4*math.cos(angle*math.tau/128)),1/128)
            self.assertLessEqual(abs(vy/256-4*math.sin(angle*math.tau/128)),1/128)


class MovementTests(unittest.TestCase):
    def setUp(self):
        self.r = Runtime()
        self.r.call('initialise_state')

    def shoot(self, angle, power):
        self.r.put('ANGLE',angle)
        self.r.put('POWER',power)
        self.r.call('start_shot')

    def test_every_pixel_and_subpixel_including_x_above_255(self):
        isolate_segments(self.r,[])
        position(self.r,256,40)
        self.shoot(0,8)  # one pixel per tick before radial braking
        pixels = []
        fractions = []
        for _ in range(20):
            self.r.call('physics_tick')
            self.r.call('ball_screen_position')
            pixels.append(unsigned(self.r,'BALL_SCREEN_X'))
            fractions.append(self.r.get('BALL_POS_X'))
        self.assertEqual(pixels[:4],[257,258,259,260])
        self.assertTrue(any(fractions))
        self.assertTrue(all(0 <= b-a <= 1 for a,b in zip(pixels,pixels[1:])))
        self.assertEqual(unsigned(self.r,'BALL_POS_X',3) >> 16,1)

    def test_free_roll_constant_radial_deceleration_and_exact_stop(self):
        isolate_segments(self.r,[])
        results = []
        for angle in range(128):
            self.r.call('initialise_state')
            position(self.r,64,112)
            self.shoot(angle,8)
            for _ in range(100):
                self.r.call('physics_tick')
                if not self.r.get('ROLLING'):
                    break
            self.assertEqual(_,63)
            end = point(self.r)
            distance = math.hypot(end[0]-64,end[1]-112)
            actual = math.atan2(end[1]-112,end[0]-64)
            intended = angle*math.tau/128
            error = abs((actual-intended+math.pi)%math.tau-math.pi)
            self.assertLess(error,math.pi/180,(angle,math.degrees(error)))
            results.append(distance)
            self.assertEqual(unsigned(self.r,'SPEED'),0)
            self.assertEqual(signed(self.r,'VELOCITY_X'),0)
            before = point(self.r)
            self.r.call('physics_tick')
            self.assertEqual(point(self.r),before)
        self.assertLess((max(results)-min(results))/max(results),.02,results)

    def test_pause_and_no_second_shot_while_rolling(self):
        self.shoot(0,16)
        before = point(self.r)
        self.r.put('PAUSED',1)
        self.r.call('physics_tick')
        self.assertEqual(point(self.r),before)
        self.r.put('PAUSED',0)
        self.r.put('KEY_ACTIONS',S['KEY_SHOT'])
        self.r.call('apply_controls')
        self.assertEqual(self.r.get('SHOTS'),1)

    def test_max_power_continuous_sweep_and_cardinal_wall_reflection(self):
        isolate_segments(self.r,[((16,100),(200,100),6)])
        position(self.r,64,96)
        self.shoot(32,32)
        self.r.call('physics_tick')
        x,y = point(self.r)
        self.assertAlmostEqual(x,64,places=3)
        self.assertGreaterEqual(y,95.9)
        self.assertLess(y,98)
        self.assertEqual(signed(self.r,'VELOCITY_X'),0)
        self.assertLess(signed(self.r,'VELOCITY_Y'),0)
        self.assertLessEqual(unsigned(self.r,'SPEED'),960)
        self.assertEqual(self.r.get('CONTACT_LIMIT_HITS'),0)

    def test_hidden_vertex_flags_preserve_real_course_physics(self):
        def replay(hidden_caps,scene):
            r = Runtime()
            r.call('initialise_state')
            if not hidden_caps:
                for i in range(S['COURSE_SEGMENT_COUNT']):
                    r.bus[S['course_segments']+i*5+4] &= 7
            x,y,angle = scene
            position(r,x,y)
            r.put('ANGLE',angle)
            r.put('POWER',32)
            r.call('start_shot')
            states = []
            for _ in range(80):
                r.call('physics_tick')
                states.append(bytes(r.bus[S['BALL_POS_X']:S['SHOTS']+1]))
            return states
        for scene in ((18.5,26.5,80),(124,79,17),(124,80,16),(160,78,0)):
            self.assertEqual(replay(True,scene),replay(False,scene),scene)

    def test_radial_diagonal_shortcut_matches_exact_entry_time(self):
        for q in (-363,-364,-400,-511,-512,-600,-1000):
            for step in (1,8,64,256,724):
                position(self.r,100+q/256,100+q/256)
                put(self.r,'POINT_X',25600,3)
                put(self.r,'POINT_Y',25600)
                put(self.r,'STEP_X',step)
                put(self.r,'STEP_Y',step)
                self.r.put('BOUNDS_X',int((25600+q)//512))
                self.r.put('BOUNDS_Y',int((25600+q)//512))
                self.r.put('HIT',0)
                self.r.put('STEP_SQUARE_VALID',0)
                put(self.r,'RADIUS_SQUARED',512*512,4)
                self.r.call('try_circle')
                inside = [t for t in range(256) if 2*(q+step*t//256)**2 < 512*512]
                self.assertEqual(bool(self.r.get('HIT')),bool(inside),(q,step))
                if inside:
                    self.assertEqual(self.r.get('BEST_T'),inside[0]-1,(q,step))

    def test_wall_rounding_epsilon_does_not_drop_incoming_contact(self):
        for deficit in (1,2):
            self.r.call('initialise_state')
            isolate_segments(self.r,[((16,24),(16,152),0)])
            position(self.r,18-deficit/256,80)
            self.shoot(64,32)
            self.r.call('physics_tick')
            self.assertGreater(signed(self.r,'VELOCITY_X'),0)
            self.assertGreater(point(self.r)[0],18)
            self.assertEqual(self.r.get('CONTACT_LIMIT_HITS'),0)

    def test_45_degree_wall_correct_reflection(self):
        isolate_segments(self.r,[((200,20),(300,120),3)])
        position(self.r,244,68)
        self.shoot(0,32)
        self.r.call('physics_tick')
        vx,vy = signed(self.r,'VELOCITY_X'),signed(self.r,'VELOCITY_Y')
        expected = math.atan2(992,32)
        actual = math.atan2(vy,vx)
        self.assertLess(abs(actual-expected),math.pi/180,(vx,vy))
        self.assertGreater(vy,0)
        x,y = point(self.r)
        self.assertGreaterEqual((y-x+180)/math.sqrt(2),2)
        self.assertEqual(self.r.get('CONTACT_LIMIT_HITS'),0)

    def test_convex_endpoint_reflects_radially(self):
        isolate_segments(self.r,[((100,100),(100,152),4)])
        position(self.r,96,96)
        self.shoot(16,32)
        for _ in range(2):
            self.r.call('physics_tick')
        vx,vy = signed(self.r,'VELOCITY_X'),signed(self.r,'VELOCITY_Y')
        self.assertLess(vx,0)
        self.assertLess(vy,0)
        self.assertLess(abs(math.atan2(vy,vx)+3*math.pi/4),math.pi/180,(vx,vy))
        self.assertEqual(self.r.get('CONTACT_LIMIT_HITS'),0)

    def test_swept_circle_finds_grazing_entry_with_both_ends_outside(self):
        isolate_segments(self.r,[((100,100),(100,152),4)])
        position(self.r,99.5,98.01)
        put(self.r,'STEP_X',256)
        put(self.r,'STEP_Y',0)
        self.r.call('collect_candidates')
        self.r.call('find_first_contact')
        self.assertEqual(self.r.get('HIT'),1)
        t = self.r.get('BEST_T')/256
        y = point(self.r)[1]
        expected = (.5-math.sqrt(4-(y-100)**2))
        self.assertLessEqual(abs(t-expected),.02,(t,expected))

    def test_slow_ball_already_inside_cup_is_caught_moving_away(self):
        isolate_segments(self.r,[])
        position(self.r,S['CUP_X']+2.5,S['CUP_Y'])
        self.shoot(0,2)
        self.r.call('physics_tick')
        self.assertEqual(self.r.get('HOLED'),1)
        self.assertEqual(point(self.r),(S['CUP_X'],S['CUP_Y']))

    def test_cup_uses_reduced_velocity_immediately_after_bounce(self):
        isolate_segments(self.r,[((274,80),(274,140),4)])
        position(self.r,271.5,112)
        self.shoot(0,7)
        put(self.r,'SPEED',200)
        self.r.call('physics_tick')
        self.assertEqual(self.r.get('HOLED'),1)
        self.assertEqual(self.r.get('CONTACT_LIMIT_HITS'),0)

    def test_corner_replays_preserve_preoptimization_states(self):
        import json
        from pathlib import Path
        fixture = json.loads((Path(__file__).parent/'fixtures/corner-replays.json').read_text())
        for case in fixture:
            r = Runtime()
            r.call('initialise_state')
            position(r, case['x'], case['y'])
            r.put('ANGLE', case['angle'])
            r.put('POWER', 32)
            r.call('start_shot')
            for frame, expected in enumerate(case['states']):
                r.call('physics_tick')
                self.assertEqual(r.bus[S['BALL_POS_X']:S['STATE_END']], expected,
                                 (case['name'], frame))

    def test_time_bit_circle_search_matches_discrete_geometric_oracle(self):
        rng = random.Random(512)
        hits = 0
        for _ in range(200):
            qx,qy = rng.randrange(-1400,1401),rng.randrange(-1400,1401)
            sx,sy = rng.randrange(-900,901),rng.randrange(-900,901)
            if qx*qx+qy*qy < 512*512 or qx*sx+qy*sy >= 0:
                continue
            inside = [t for t in range(256)
                      if (qx+sx*t//256)**2+(qy+sy*t//256)**2 < 512*512]
            if not inside:
                continue
            position(self.r,100+qx/256,100+qy/256)
            put(self.r,'POINT_X',100*256,3)
            put(self.r,'POINT_Y',100*256)
            put(self.r,'STEP_X',sx)
            put(self.r,'STEP_Y',sy)
            self.r.put('BOUNDS_X',int((100*256+qx)//512))
            self.r.put('BOUNDS_Y',int((100*256+qy)//512))
            self.r.put('HIT',0)
            self.r.put('STEP_SQUARE_VALID',0)
            put(self.r,'RADIUS_SQUARED',512*512,4)
            self.r.call('try_circle')
            self.assertEqual(self.r.get('HIT'),1,(qx,qy,sx,sy))
            self.assertLessEqual(abs(self.r.get('BEST_T')-(inside[0]-1)),1)
            hits += 1
        self.assertGreater(hits,10)

    def test_slow_cup_catches_and_fast_ball_passes(self):
        isolate_segments(self.r,[])
        position(self.r,268.8,112)
        self.shoot(0,4)
        self.r.call('physics_tick')
        self.assertEqual(self.r.get('HOLED'),1)
        self.assertEqual(point(self.r),(272,112))
        self.r.call('reset_ball')
        position(self.r,268.8,112)
        self.shoot(0,32)
        self.r.call('physics_tick')
        self.assertEqual(self.r.get('HOLED'),0)
        self.assertGreater(point(self.r)[0],272)

    def test_real_course_deterministic_long_rolls_never_hit_contact_limit(self):
        def replay():
            r = Runtime()
            r.call('initialise_state')
            states = []
            for angle,power in [(0,32),(96,20),(32,22),(0,32),(16,24)]:
                r.put('ANGLE',angle)
                r.put('POWER',power)
                r.call('start_shot')
                for frame in range(300):
                    r.call('physics_tick')
                    states.append((point(r),signed(r,'VELOCITY_X'),signed(r,'VELOCITY_Y')))
                    self.assertEqual(r.get('CONTACT_LIMIT_HITS'),0,(angle,power,frame,point(r)))
                    if not r.get('ROLLING'):
                        break
                else:
                    self.fail('ball never stops')
            return states
        self.assertEqual(replay(),replay())


if __name__ == '__main__':
    unittest.main()
