; TED colors: (LUMINANCE << 4) + HUE. Luminance 0..7, hue 0..15.
; Hue 0 is black, hue 1 is neutral gray/white, 13 light blue, 15 light green.
; Hi-res stores luminance and hue in separate foreground/background nibbles.
; Floor and lawn come from the surface chosen on the title
; (assets/colours.json). Same hue on both. The lawn is a 1x1 checker at
; luminance 3 and 2. Gras, Erde and Gummi use floor luminance 7 so the
; black ball stands out. Beton is hue 1 at luminance 5: luminance 7
; would be white. The floor stays brighter than luminance 3, so the
; obstacle sweep still tells lawn from floor.
LAWN_LUMINANCE = 3
COURSE_MARKER_COLOR = (0 << 4) + 0 ; ball, aim marks, cup ring and inner edges
COURSE_FRAME_COLOR = (0 << 4) + 0  ; one-cell frame around the course
WATER_DRAWN_COLOR = (7 << 4) + 0   ; drawn with display off, until water_init
                                   ; gives water the lawn colour; no floor
HUD_FOREGROUND_COLOR = (7 << 4) + 1
HUD_BACKGROUND_COLOR = (0 << 4) + 0
BORDER_COLOR = (0 << 4) + 0
; Ink of the three coloured title figures ($FF16-$FF18) and of players 2..4
; on the status row. Player 1 uses HUD_FOREGROUND_COLOR (white): black would
; vanish on the black HUD paper. The first figure stays $FF15, which is black.
; Luminance is 0..7, hue is 0..15 (0 black, 1 white, 2 red, 6 blue, 7 yellow).
FIGURE_COLOR_1 = (3 << 4) + 2
FIGURE_COLOR_2 = (4 << 4) + 6
FIGURE_COLOR_3 = (3 << 4) + 5

; Water runs through the lawn colour at luminance 3, 2 and 1
; (water.asm). Physics tells water from the floor by the whole ink.

; Hi-res attribute bytes for foreground/background color pairs.
!macro attribute_luminance .foreground, .background {
    !byte (.background & $70) + ((.foreground & $70) >> 4)
}
!macro attribute_color .foreground, .background {
    !byte ((.foreground & $0f) << 4) + (.background & $0f)
}
