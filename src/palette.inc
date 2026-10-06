; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white, 13 light blue, 15 light green.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
COURSE_SURFACE_COLOR = (7 << 4) + 1 ; white floor
COURSE_MARKER_COLOR = (0 << 4) + 0 ; ball, aim marks, cup ring and inner edges
COURSE_FRAME_COLOR = (0 << 4) + 0  ; one-cell frame around the course
CHECKER_COLOR_EVEN = (4 << 4) + 15  ; non-playable area: horizontal stripes
CHECKER_COLOR_ODD = (3 << 4) + 15   ; neighbouring stripes, one luminance step
WATER_COLOR_EVEN = (4 << 4) + 13    ; water areas: blue checker, no frame
WATER_COLOR_ODD = (3 << 4) + 13
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0

!if COURSE_MARKER_COLOR = COURSE_SURFACE_COLOR {
    !error "markers must remain visible on the floor"
}
; Physics finds water by the foreground hue of the ball's cell.
WATER_HUE = WATER_COLOR_EVEN & 15
!if (WATER_COLOR_ODD & 15) != WATER_HUE { !error "water checker needs one hue" }
!if (COURSE_SURFACE_COLOR & 15) = WATER_HUE | (CHECKER_COLOR_EVEN & 15) = WATER_HUE | (CHECKER_COLOR_ODD & 15) = WATER_HUE {
    !error "water hue must differ from floor and grass"
}

; Hi-res attribute bytes for foreground/background color pairs.
!macro attribute_luminance .foreground, .background {
    !byte (.background & $70) + ((.foreground & $70) >> 4)
}
!macro attribute_color .foreground, .background {
    !byte ((.foreground & $0f) << 4) + (.background & $0f)
}
