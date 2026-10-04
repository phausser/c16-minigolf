; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
COURSE_SURFACE_COLOR = (5 << 4) + 1
COURSE_SHADOW_COLOR = (3 << 4) + 1
COURSE_SOLID_COLOR = (0 << 4) + 0 ; outside, obstacles, ball, aim and cup ring
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0

!if (COURSE_SHADOW_COLOR & $0f) != (COURSE_SURFACE_COLOR & $0f) {
    !error "surface and shadow must share the same hue in the current renderer"
}
!if COURSE_SURFACE_COLOR = COURSE_SOLID_COLOR {
    !error "surface and solid colors must remain distinguishable"
}
