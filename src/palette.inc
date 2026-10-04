; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
COURSE_INK_COLOR = (7 << 4) + 1 ; white ball, aim, cup ring and surface pattern
COURSE_SOLID_COLOR = (0 << 4) + 0 ; black outside, obstacles and pattern background
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0

!if COURSE_INK_COLOR = COURSE_SOLID_COLOR {
    !error "ink and solid colors must remain distinguishable"
}
