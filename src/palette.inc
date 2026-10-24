; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white, 13 light blue, 15 light green.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
COURSE_SURFACE_COLOR = (5 << 4) + 5 ; white floor
COURSE_MARKER_COLOR = (0 << 4) + 0 ; ball, aim marks, cup ring and inner edges
COURSE_FRAME_COLOR = (0 << 4) + 0  ; one-cell frame around the course
CHECKER_COLOR_EVEN = (7 << 4) + 1  ; non-playable area: 2x2 checker
CHECKER_COLOR_ODD = (6 << 4) + 1   ; neighbouring squares, one luminance step
WATER_COLOR_EVEN = CHECKER_COLOR_EVEN ; water areas: the lawn colour, no frame
WATER_COLOR_ODD = WATER_COLOR_EVEN  ; formerly a checker; kept for the tables
WATER_DRAWN_COLOR = (4 << 4) + 1   ; drawn with display off, until water_init
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0

!if COURSE_MARKER_COLOR = COURSE_SURFACE_COLOR {
    !error "markers must remain visible on the floor"
}
; Physics finds water by the foreground hue of the ball's cell, which is
; never a lawn cell.
WATER_HUE = WATER_COLOR_EVEN & 15
!if (WATER_COLOR_ODD & 15) != WATER_HUE { !error "water needs one hue" }
!if (COURSE_SURFACE_COLOR & 15) = WATER_HUE | (WATER_DRAWN_COLOR & 15) != WATER_HUE {
    !error "water hue must differ from the floor"
}

; Hi-res attribute bytes for foreground/background color pairs.
!macro attribute_luminance .foreground, .background {
    !byte (.background & $70) + ((.foreground & $70) >> 4)
}
!macro attribute_color .foreground, .background {
    !byte ((.foreground & $0f) << 4) + (.background & $0f)
}
