; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white, 13 light blue, 15 light green.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
; Floor and lawn of each hole and the title: assets/colours.json, checked
; by hole_inks below. The lawn is a 2x2 checker at luminance 4 and 3; the
; floor is brighter, so the black ball stands out on it.
LAWN_LUMINANCE = 4
COURSE_MARKER_COLOR = (0 << 4) + 0 ; ball, aim marks, cup ring and inner edges
COURSE_FRAME_COLOR = (0 << 4) + 0  ; one-cell frame around the course
WATER_DRAWN_COLOR = (7 << 4) + 0   ; drawn with display off, until water_init
                                   ; gives water the lawn colour; no floor
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0

; One entry of course_inks. Water runs through the lawn colour at
; luminance 4, 3 and 2 (water.asm): physics tells it from the floor by the
; ink. The obstacle fill tells reached lawn by its lower luminance.
!macro hole_inks .floor, .lawn {
    !if (.lawn & $f0) != LAWN_LUMINANCE << 4 { !error "the lawn has LAWN_LUMINANCE" }
    !if (.floor & $f0) <= LAWN_LUMINANCE << 4 | (.floor & $f0) > $70 | (.floor & 15) = 0 {
        !error "the floor needs a hue and must be brighter than the lawn"
    }
    !byte .floor, .lawn
}

; Hi-res attribute bytes for foreground/background color pairs.
!macro attribute_luminance .foreground, .background {
    !byte (.background & $70) + ((.foreground & $70) >> 4)
}
!macro attribute_color .foreground, .background {
    !byte ((.foreground & $0f) << 4) + (.background & $0f)
}
