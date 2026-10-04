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
FRAME_END_RASTER = $2d       ; debug timing, low byte
STATE_END = $2e
AIM_X = $30                 ; word, unsigned pixel position * 16
AIM_Y = $32                 ; word
AIM_STEP_X = $34            ; signed byte, 4 fractional bits
AIM_STEP_Y = $35
BAR_LEFT = $36
GLYPH_BITS = $37

KEY_LEFT = 1
KEY_RIGHT = 2
KEY_UP = 4
KEY_DOWN = 8
KEY_PAUSE = 16

RELOCATOR_BASE = $0200
RUNTIME_BASE = $0240
RUNTIME_LIMIT = $1700
DYNAMIC_LO = $1700           ; three arrays of 32 bytes; restore in reverse
DYNAMIC_HI = $1720
DYNAMIC_OLD = $1740
SCRATCH_END = $1800
LUMINANCE_BASE = $1800
COLOR_BASE = $1c00
BITMAP_BASE = $2000
BITMAP_END = $4000
