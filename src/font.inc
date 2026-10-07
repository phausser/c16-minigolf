; Font image, one row per pixel line: edit the dots and hashes. It is not
; part of the runtime: start copies it into the charset cells from
; FONT_CHAR on, which nothing else uses. install_font expands it into
; codes 0..FONT_GLYPHS-1 (pixel rows 1..5, column 7 free; code 0 blank)
; and the two cells of the golfer.
; Codes: letters from LETTER_M, DIGIT_CHAR 0..9, then BALL_CHAR, the
; arrows, FLAG_CHAR, CLUB_CHAR, the parentheses; FIGURE_CHAR: the
; golfer, 8 x 16.

LETTER_M = 1
LETTER_I = 2
LETTER_N = 3
LETTER_G = 4
LETTER_O = 5
LETTER_L = 6
LETTER_F = 7
LETTER_P = 8
LETTER_A = 9
LETTER_Y = 10
LETTER_R = 11
LETTER_C = 12
LETTER_T = 13
LETTER_S = 14
LETTER_E = 15
font_image:
; M
!byte %##...##.
!byte %###.###.
!byte %##.#.##.
!byte %##...##.
!byte %##...##.
; I
!byte %.####...
!byte %..##....
!byte %..##....
!byte %..##....
!byte %.####...
; N
!byte %.#####..
!byte %##...##.
!byte %##...##.
!byte %##...##.
!byte %##...##.
; G
!byte %.######.
!byte %##......
!byte %##...##.
!byte %##...##.
!byte %.######.
; O
!byte %.#####..
!byte %##...##.
!byte %##...##.
!byte %##...##.
!byte %.#####..
; L
!byte %##......
!byte %##......
!byte %##......
!byte %##......
!byte %.######.
; F
!byte %.######.
!byte %##......
!byte %#####...
!byte %##......
!byte %##......
; P
!byte %######..
!byte %##...##.
!byte %######..
!byte %##......
!byte %##......
; A
!byte %.#####..
!byte %##...##.
!byte %#######.
!byte %##...##.
!byte %##...##.
; Y
!byte %##...##.
!byte %##...##.
!byte %.#####..
!byte %...##...
!byte %..##....
; R
!byte %######..
!byte %##...##.
!byte %######..
!byte %##..##..
!byte %##...##.
; C
!byte %.######.
!byte %##......
!byte %##......
!byte %##......
!byte %.######.
; T
!byte %######..
!byte %..##....
!byte %..##....
!byte %..##....
!byte %..##....
; S
!byte %.######.
!byte %##......
!byte %.#####..
!byte %.....##.
!byte %######..
; E
!byte %.######.
!byte %##......
!byte %#####...
!byte %##......
!byte %.######.
; 0
!byte %.#####..
!byte %##...##.
!byte %##.#.##.
!byte %##...##.
!byte %.#####..
; 1
!byte %..###...
!byte %...##...
!byte %...##...
!byte %...##...
!byte %..####..
; 2
!byte %######..
!byte %.....##.
!byte %.#####..
!byte %##......
!byte %#######.
; 3
!byte %######..
!byte %.....##.
!byte %..####..
!byte %.....##.
!byte %######..
; 4
!byte %##...##.
!byte %##...##.
!byte %.######.
!byte %.....##.
!byte %.....##.
; 5
!byte %#######.
!byte %##......
!byte %######..
!byte %.....##.
!byte %######..
; 6
!byte %.#####..
!byte %##......
!byte %######..
!byte %##...##.
!byte %.#####..
; 7
!byte %#######.
!byte %.....##.
!byte %....##..
!byte %...##...
!byte %...##...
; 8
!byte %.#####..
!byte %##...##.
!byte %.#####..
!byte %##...##.
!byte %.#####..
; 9
!byte %.#####..
!byte %##...##.
!byte %.######.
!byte %.....##.
!byte %.#####..
; golf ball
!byte %..###...
!byte %.#.###..
!byte %.#####..
!byte %.#####..
!byte %..###...
; arrow left
!byte %....##..
!byte %...###..
!byte %..####..
!byte %...###..
!byte %....##..
; arrow right
!byte %.##.....
!byte %.###....
!byte %.####...
!byte %.###....
!byte %.##.....
; flag
!byte %..##....
!byte %..####..
!byte %..##....
!byte %..#.....
!byte %..#.....
; club
!byte %......#.
!byte %.....#..
!byte %....#...
!byte %##.#....
!byte %.##.....
; (
!byte %..###...
!byte %..##....
!byte %..##....
!byte %..##....
!byte %..###...
; )
!byte %..###...
!byte %...##...
!byte %...##...
!byte %...##...
!byte %..###...
; golfer, top and bottom cell
!byte %....##..
!byte %...####.
!byte %...####.
!byte %..####..
!byte %.###....
!byte %#####...
!byte %#####...
!byte %######..
!byte %###.##..
!byte %###..#..
!byte %.##..#..
!byte %.##..#..
!byte %.##..#..
!byte %.##..#..
!byte %.###.#..
!byte %.###.##.
font_image_end:
!if font_image_end - font_image != (FONT_GLYPHS - 1) * 5 + 16 { !error "font image does not match FONT_GLYPHS" }
