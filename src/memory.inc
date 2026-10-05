; $00/$01 are the CPU I/O port. The hardware stack stays at $0100-$01ff.
COPY_SOURCE = $02             ; word, reused by renderer after relocation
COPY_TARGET = $04             ; word
BITMAP_PTR = $06              ; word
TEXT_PTR = $08                ; word
FONT_PTR = $0a                ; word
COURSE_PTR = $0c              ; word
PIXEL_X = $0e                 ; word, unsigned 0..319
PIXEL_Y = $10
PIXEL_MASK = $11
TEMP = $12
ROW_INDEX = $13
LINE_X_STEP = $14             ; -1 / 0 / +1
LINE_Y_STEP = $15
LINE_LEFT = $16               ; pixel steps remaining
LINE_X = $17                  ; word
LINE_Y = $19
SEGMENTS_LEFT = $1a
TEXT_COLUMN = $1b
TEXT_ROW = $1c
GLYPH = $1d
POINT_INDEX = $1e

; Clearable state, deliberately contiguous for tests and snapshots.
STATE_BEGIN = $20
ANGLE = $20                  ; 0..127, clockwise, 0 = right
POWER = $21                  ; 1..32
PAUSED = $22
KEY_CURRENT = $23            ; logical bit mask
KEY_PREVIOUS = $24
KEY_CANDIDATE = $25
KEY_DEBOUNCE = $26
KEY_ACTIONS = $27
KEY_REPEAT = $28
DIRTY = $29
DYNAMIC_COUNT = $2a
FRAMES = $2b                 ; word, includes paused frames
CHARGING = $2e              ; fire held; valid shot strength is being built
CHARGE_TICKS = $2f          ; one increment every two PAL frames
FRAME_END_RASTER = $2d       ; debug timing, low byte
AIM_X = $30                 ; word, unsigned pixel position * 16
AIM_Y = $32                 ; word
AIM_STEP_X = $34            ; signed byte, 4 fractional bits
AIM_STEP_Y = $35
AIM_PHASE = $36            ; walking aim dots, low two bits
GLYPH_BITS = $37

BALL_POS_X = $38             ; unsigned 24-bit Q16.8 (320 pixels need >16 bits)
BALL_POS_Y = $3b             ; unsigned 16-bit Q8.8
VELOCITY_X = $3d             ; signed Q8.8
VELOCITY_Y = $3f
SPEED = $41                 ; unsigned Q8.8, radial roll resistance
UNIT_X = $43                ; signed Q1.8 unit direction
UNIT_Y = $45
ROLLING = $47
HOLED = $48
SHOTS = $49
HUD_DIRTY = $4a
CONTACT_LIMIT_HITS = $4b
CANDIDATE_COUNT = $4c
FIRE_LOCK = $4d             ; require release after pause/rolling/restart
STATE_END = $4e
HOLE = $4e                 ; current hole, 0-based; COURSE_COUNT = summary
TOTAL = $4f                ; strokes of the finished holes
BALL_SCREEN_X = $50          ; rounded integer word
BALL_SCREEN_Y = $52
PHYS_INDEX = $53
REFLECT_INDEX = $54       ; 0 = x, 2 = y component in reflect_unit
CONTACTS_LEFT = $56
HIT = $57
BEST_T = $58
TRIAL_T = $59
NORMAL_CODE = $5a
BISECT_LO = $5b
BISECT_HI = $5c
SEG_OFFSET = $5d
FRAME_CUP = $5e
BOUNDS_X = $5f
BOUNDS_Y = $60
WALL_X_OFFSET = $61
WALL_Y_OFFSET = $62
STEP_SQUARE_VALID = $63
CIRCLE_DELTA = $65       ; two signed 24-bit STEP * time-bit values
CIRCLE_TRIAL = $c9       ; two signed 24-bit relative coordinates, Q8.16
CIRCLE_OUT = $cf         ; six bytes, last definitely outside point
CIRCLE_BIT = $d5

; Dedicated 32-byte zero-page candidate list, separate from math scratch.
CANDIDATES = $d8
; Current course in pixels, written by decode_course: four low bytes,
; then the matching high bytes ($fd and $ff stay zero).
COURSE_POS_LO = $f8
COURSE_START_X = $f8
COURSE_START_Y = $f9
COURSE_CUP_X = $fa
COURSE_CUP_Y = $fb
COURSE_POS_HI = $fc
COURSE_START_X_HI = $fc
COURSE_CUP_X_HI = $fe
SEGMENT_BYTES = $ab       ; 5 * segment count
COLLECT_X_LOW = $ac       ; broadphase window in packed 2px units
COLLECT_X_HIGH = $ad      ; exclusive upper limits
COLLECT_Y_LOW = $ae
COLLECT_Y_HIGH = $af
FRAME_START = $6b         ; BALL_POS_X/Y copy at the start of a rolling frame
HAZARD_COUNT = $74        ; water areas of the current course, 0..3
HAZARD_PTR = $75          ; word: their cell rectangles in the course stream
STEP_X = $70              ; signed Q8.8 residual displacement
STEP_Y = $72
REMAINING_TIME = $78       ; Q0.8, 256 = complete frame
POINT_X = $7a             ; 24-bit Q16.8 static contact endpoint
POINT_Y = $7d             ; 16-bit Q8.8
QX = $7f                 ; signed Q8.8, relative position near endpoint
QY = $81
TRIAL_X = $83
TRIAL_Y = $85
NX = $87                 ; signed unit normal Q1.8
NY = $89
BEST_NX = $8b
BEST_NY = $8d
STEP_SQUARED = $8f        ; 32-bit
DX_WIDE = $93             ; signed 24-bit relative coordinates
DY_WIDE = $96
GAP = $99                 ; signed 24-bit distance along unnormalized normal
DOT_STEP = $9c            ; signed 16-bit
RADIUS_SQUARED = $9e      ; 32-bit, 2px walls / 3px cup
SAVED_DOT = $a2           ; 16-bit reflection scalar
SAVED_X = $a4             ; reflection input word
SAVED_Y = $a6
SAVED_SPEED = $a8
M_A = $b0                ; signed 16-bit multiply input
M_B = $b2
M_PRODUCT = $b4           ; signed 32-bit output / sqrt input
M_MULTIPLICAND = $b8      ; 32-bit scratch
M_SIGN = $bc
M_REM = $bd              ; 24-bit fractional division remainder
M_DEN = $c0              ; 24-bit positive denominator
M_QUOT = $c3             ; 16-bit division/sqrt result
M_TRIAL = $c5            ; 24-bit sqrt trial
M_COUNT = $c8
BALL_LEFT = M_PRODUCT       ; three left byte masks while drawing the ball
BALL_RIGHT = M_MULTIPLICAND ; three right byte masks
; decode_course scratch shares math scratch; decoding precedes physics.
DECODE_X = M_A            ; current vertex, 2px units
DECODE_Y = M_A + 1
DECODE_SX = M_B           ; segment start
DECODE_SY = M_B + 1
DECODE_DIR = M_PRODUCT    ; current segment direction, $ff = none
DECODE_PREV = M_PRODUCT + 1
DECODE_SIDE = M_PRODUCT + 2 ; $80 = normal is direction + 2
DECODE_RUNS = M_PRODUCT + 3
DECODE_CONTOURS = M_SIGN
DECODE_LENGTH = M_COUNT

BALL_RADIUS = 512
DIAGONAL_RADIUS = 725       ; ceil(2 * sqrt(2) * 256), never inside the wall
ROLL_DECEL = 4              ; 1/64 pixel per 50-Hz step
MAX_CONTACTS = 4
CIRCLE_MIN_BIT = 16         ; corner contact time resolution, 1/256 frame units

KEY_LEFT = 1
KEY_RIGHT = 2
KEY_UP = 4
KEY_DOWN = 8
KEY_PAUSE = 16
KEY_SHOT = 32

RELOCATOR_BASE = $0100        ; boot only; overwritten by volatile buffers
MAX_SEGMENTS = 32
course_segments = $0100       ; decoded: x1/2, y1/2, x2/2, y2/2, flags
MAX_DYNAMIC_BYTES = 18
DYNAMIC_LO = $01a0           ; three arrays of 18 bytes; restore in reverse
DYNAMIC_HI = $01b2
DYNAMIC_OLD = $01c4
; Measured call depth is 12 bytes; $01d6-$01ff stay reserved for the stack.
STACK_FLOOR = $01d6
RUNTIME_BASE = $0200
RUNTIME_LIMIT = $1800
LUMINANCE_BASE = $1800
COLOR_BASE = $1c00
BITMAP_BASE = $2000
BITMAP_END = $4000
