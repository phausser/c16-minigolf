; Title menu shaped like a course, black glyphs on the floor colour:
; MINIGOLF, one to four golfers, the four surfaces, three holes as 16x8
; silhouettes, the ranges 1-18, 1-9 and 10-18, and PLAY at the bottom.
; The playable interior is black; set bits keep the cell's floor colour.
; No cup and no obstacles. The hollow ball marks the row left and right
; change. A filled ball stays under the chosen player count, surface and
; course. Up and down switch the row, fire on PLAY starts. Hole h
; is drawn in block h mod 4: the three shown and the next one in the
; direction of the last slide. A hole that is not ready is drawn into
; its block while that block is not shown, so the row never shows drawing.
TITLE_CHAR = 36               ; title frame from here on (intern_pattern)
PREVIEW_CHAR = 68             ; four 16 x 8 pictures, two cells each
PREVIEW_BLOCKS = 4
PREVIEW_BLOCK = 2
; B, D and the dash sit above the bar, so the frame must stop there.
TITLE_CHAR_LIMIT = LETTER_B - TITLE_CHAR
!if PREVIEW_CHAR + PREVIEW_BLOCKS * PREVIEW_BLOCK > SQUARE_CHAR { !error "previews overlap square_lo" }
!if TITLE_CHAR < FIGURE_CHAR + 2 { !error "the title frame overlaps the font" }
!if FIGURE_CHAR & 1 { !error "the figure's second cell is FIGURE_CHAR or 1" }
!if FIGURE_CHAR >= 64 { !error "the figure must fit ECM's 64 characters" }
; Y-scroll is 3 ($FF06 = $1B). Row N's colour fetch is TED line 3+8*N
; and its eight pixels start on line 4+8*N. The figure is rows 10 and 11,
; pixels 84..99. ECM is on from ECM_ON_LINE to ECM_OFF_LINE. $FF16-$FF18
; take FIGURE_COLOR_1..3 from SHIRT_LINE, so the whole figure is that
; colour. $FF15 stays black.
ECM_ON_LINE = 80
FIGURE_LINE = 80
SHIRT_LINE = 82
LEGS_LINE = 100
ECM_OFF_LINE = 100
TITLE_LAST_ROW = 23           ; the title course reaches down to row 23
HEADER = SCREEN_BASE + 4 * 40 + 16
FIGURE_ROW = SCREEN_BASE + 10 * 40   ; and the row below, then the ball
SURFACE_ROW = SCREEN_BASE + 14 * 40
SURFACE_COLUMN = 8
RANGE_ROW = SCREEN_BASE + 16 * 40
RANGE_COLUMN = 11
PREVIEW_ROW = SCREEN_BASE + 18 * 40  ; pictures; the arrows share this row
HOLE_ROW = PREVIEW_ROW
NUMBER_ROW = PREVIEW_ROW + 40        ; ball and number below each picture
PLAY_ROW = SCREEN_BASE + 20 * 40
PLAY_COLUMN = 18
PLAY_BALL_COLUMN = 19
ARROW_LEFT_COLUMN = 9
ARROW_RIGHT_COLUMN = 29
MENU_SURFACE = 1
MENU_COURSE = 2
MENU_PLAY = 3
; A picture is two cells, column by column: pixel (x, y) is byte
; (x / 8) * 8 + y. Set bits keep the cell colour; cleared bits are black.

title_screen:
    ldx #$ff                  ; entered from the game loop: drop its frames
    txs
    lda #$ff
    ldx #PREVIEW_BLOCKS - 1
title_forget:
    sta block_holes,x
    dex
    bpl title_forget
    lda #3
    sta window_ahead          ; ready the hole right of the row
    jsr title_paint
title_loop:
    jsr title_figure_colors
    jsr menu_input
    lsr
    bcs title_left
    lsr
    bcs title_right
    lsr
    bcs title_up
    lsr
    bcs title_down
    and #KEY_SHOT >> 4
    beq title_loop
    lda menu_row
    cmp #MENU_PLAY
    bne title_loop
    jmp title_start
title_up:
    lda #$ff
    bne title_vert
title_down:
    lda #1
title_vert:
    clc
    adc menu_row
    cmp #MENU_PLAY + 1
    bcs title_loop
    pha
    ldx menu_row
    lda #PICK_CHAR            ; the choice keeps a filled ball
    cpx #MENU_PLAY
    bne title_vert_keep
    lda #BLANK_CHAR           ; PLAY is only the cursor
title_vert_keep:
    jsr title_ball
    pla
    sta menu_row
    jmp title_ball_moved
title_left:
    lda #$ff
    bne title_step
title_right:
    lda #1
title_step:
    ldx menu_row
    cpx #MENU_PLAY
    beq title_loop
    pha
    lda #BLANK_CHAR
    jsr title_ball
    pla
    ldx menu_row
    clc
    adc menu_players,x        ; players, surface and course_pick sit in a row
    cmp row_limit,x
    bcs title_ball_moved      ; $ff and past the end are both above the limit
    sta menu_players,x
    cpx #MENU_SURFACE
    beq title_repaint
    cpx #MENU_COURSE
    bne title_ball_moved
    jsr course_follow
    jmp title_ball_moved
title_repaint:
    jsr title_paint           ; the whole course takes the new surface
    jmp title_loop
title_ball_moved:
    lda #BALL_CHAR
    jsr title_ball
    jmp title_loop

; A = screen code under the choice on menu_row.
title_ball:
    ldx menu_row
; A = screen code, X = row (0 players, 1 surface, 2 course, 3 PLAY).
title_ball_on:
    cpx #MENU_SURFACE
    bcc title_ball_players
    beq title_ball_surface
    cpx #MENU_COURSE
    beq title_ball_course
    ldy #PLAY_BALL_COLUMN
    sta PLAY_ROW + 40,y
    rts
title_ball_players:
    ldx menu_players
    ldy player_ball_columns,x
    sta FIGURE_ROW + 80,y
    rts
title_ball_surface:
    ldx menu_surface
    ldy surface_ball_columns,x
    sta SURFACE_ROW + 40,y
    rts
title_ball_course:
    ldx course_pick
    cpx #3
    bcs title_ball_hole
    ldy range_ball_columns,x
    sta RANGE_ROW + 40,y
    rts
title_ball_hole:
    pha
    lda practice_hole
    sec
    sbc window_first
    tax
    pla
    ldy slot_columns,x
    ldx practice_hole
    cpx #9
    bcc title_ball_store      ; one digit: blank is the picture's left cell
    dey                       ; two digits: blank is the cell left of it
title_ball_store:
    sta NUMBER_ROW,y
    rts

; course_pick 0..2 is 1-18, 1-9, 10-18. From 3 on it is one hole.
; That hole stays inside the three pictures.
course_follow:
    lda course_pick
    cmp #3
    bcc course_follow_done
    sbc #3
    sta practice_hole
    lda window_first
    clc
    adc #2
    cmp practice_hole
    bcc course_follow_right
    lda practice_hole
    cmp window_first
    bcs course_follow_done
    sta window_first
    lda #$ff
    bne course_follow_slide
course_follow_right:
    lda practice_hole
    sec
    sbc #2
    sta window_first
    lda #3
course_follow_slide:
    sta window_ahead
    jsr title_window
course_follow_done:
    rts

title_start:
    lda #0
    ldx #3
title_clear_totals:
    sta totals,x
    dex
    bpl title_clear_totals
    sta player
    ldx menu_players
    inx                       ; one to four players
    stx player_count
    ldx course_pick
    cpx #3
    bcs title_one_hole
    lda range_first,x
    sta HOLE
    lda range_last,x
    sta hole_last
    jmp title_players
title_one_hole:
    txa
    sec
    sbc #3
    sta HOLE
    clc
    adc #1
    sta hole_last
title_players:
    ; Back to the game charset: HUD font, power bar, course area.
    lda #$0b
    sta TED_CONTROL1
    lda #COURSE_CHAR
    sta intern_base
    lda #COURSE_CHAR_LIMIT
    sta intern_limit
    lda #20
    sta last_row
    ldx #0
    txa
title_clear_font:
    sta CHARSET_BASE,x
    sta CHARSET_BASE + $100,x
    inx
    bne title_clear_font
    jsr install_bar_glyphs
    lda #0
    jsr install_font
    jsr install_hud_row
    jsr start_hole
    jmp main_loop

; ECM ($5B) while the sixteen figure pixels are drawn, then text mode
; ($1B) before row 12. The low raster byte wraps at 256, same as
; wait_for_frame. A call that already missed line ECM_ON_LINE waits for
; the next frame instead of turning ECM on over the preview. The three
; figure colours cover the whole golfer. Black paper is only outside it.
title_figure_colors:
    lda TED_RASTER_LO
    cmp #ECM_ON_LINE
    bcs title_figure_colors
title_figure_low:
    lda TED_RASTER_LO
    cmp #ECM_ON_LINE
    bcc title_figure_low
    lda #$5b
    sta TED_CONTROL1
    jsr paper_black
title_shirt:
    lda TED_RASTER_LO
    cmp #SHIRT_LINE
    bcc title_shirt
    ; Immediate and inline. The wait leaves at cycle 25 of this line;
    ; a jsr to the absolute loads would store the third colour at cycle 55,
    ; after that golfer had already been drawn. These finish at cycle 43.
    ; Same bytes as player_inks + 1..3.
    lda #FIGURE_COLOR_1
    sta TED_COLOR1
    lda #FIGURE_COLOR_2
    sta TED_COLOR2
    lda #FIGURE_COLOR_3
    sta TED_COLOR3
title_legs:
    lda TED_RASTER_LO
    cmp #LEGS_LINE
    bcc title_legs
    jsr paper_black
title_figure_off:
    lda TED_RASTER_LO
    cmp #ECM_OFF_LINE
    bcc title_figure_off
    lda #$1b
    sta TED_CONTROL1
    jmp paper_players

paper_black:
    lda #0
    sta TED_COLOR1
    sta TED_COLOR2
    sta TED_COLOR3
    rts

paper_players:
    lda player_inks + 1
    sta TED_COLOR1
    lda player_inks + 2
    sta TED_COLOR2
    lda player_inks + 3
    sta TED_COLOR3
    rts

; One menu frame. A = the keys pressed in it.
menu_input:
    jsr wait_for_frame
    jsr sound_tick
    jsr scan_keyboard
    jsr debounce_keyboard
    lda KEY_ACTIONS
    rts

; Shows holes window_first..+2 from their blocks, with numbers and
; arrows, then draws window_first + window_ahead (3 or -1) out of sight.
title_window:
    lda #2
    sta POINT_INDEX           ; slot 2..0
title_window_slot:
    lda window_first
    clc
    adc POINT_INDEX
    jsr preview_hole          ; normally drawn already
    cpx #PREVIEW_BLOCKS
    bcs title_window_next     ; no such hole
    lda block_codes,x
    ldx POINT_INDEX
    ldy slot_columns,x
    clc
    ldx #2
title_window_codes:           ; carry stays clear: codes < 128
    sta PREVIEW_ROW,y
    adc #1
    iny
    dex
    bne title_window_codes
    lda #<NUMBER_ROW
    sta COPY_TARGET
    lda #>NUMBER_ROW
    sta COPY_TARGET + 1
    ldx POINT_INDEX
    lda slot_columns,x
    clc
    adc #1                    ; ones digit on the picture's right cell
    tay
    lda window_first
    sec                       ; numbers count from 1
    adc POINT_INDEX
    jsr print_number
title_window_next:
    dec POINT_INDEX
    bpl title_window_slot
    ldx #BLANK_CHAR
    lda window_first
    beq title_arrow_left
    ldx #ARROW_LEFT_CHAR
title_arrow_left:
    stx HOLE_ROW + ARROW_LEFT_COLUMN
    ldx #BLANK_CHAR
    lda window_first
    clc
    adc #3
    cmp #COURSE_COUNT
    bcs title_arrow_right
    ldx #ARROW_RIGHT_CHAR
title_arrow_right:
    stx HOLE_ROW + ARROW_RIGHT_COLUMN
    lda window_first
    clc
    adc window_ahead          ; $ff left of hole 1: none

; A = hole. Draws it into block hole mod 4 unless it is there already.
; Returns X = the block, or X = PREVIEW_BLOCKS without such a hole.
preview_hole:
    ldx #PREVIEW_BLOCKS
    cmp #COURSE_COUNT
    bcs preview_hole_done
    sta TEMP
    and #PREVIEW_BLOCKS - 1
    tax
    lda TEMP
    cmp block_holes,x
    beq preview_hole_done
    sta block_holes,x
    stx GLYPH
    lda block_lo,x
    sta BITMAP_PTR
    lda block_hi,x
    sta BITMAP_PTR + 1
    lda #$ff
    ldy #PREVIEW_BLOCK * 8 - 1
preview_clear:
    sta (BITMAP_PTR),y
    dey
    bpl preview_clear
    ldx TEMP
    jsr decode_course
    jsr preview_course
    ldx GLYPH
preview_hole_done:
    rts

; Filled outline into the block at BITMAP_PTR. Only contour 0
; (outline_bytes): no cup, no obstacles. Both axes are one preview
; pixel per 20 course pixels, so a 45-degree edge is not exact after
; the Y offset and needs a real line. Crossings are the first pixel of
; each row except ymax, XORed into a 16-bit mask (bit 7 of the first
; byte is x = 0). A peak touched by two edges cancels, and the bits
; that remain fill even-odd, including both ends. Math scratch is free
; after decode: M_A/M_A+1 are x2/y2, M_B/M_B+1 are dx/dy, and
; M_PRODUCT..+3 are sx/sy/err/ymax. Does not touch POINT_INDEX or GLYPH.
preview_course:
    ldx #15
    lda #0
preview_zero:
    sta SCRATCH_BASE,x
    dex
    bpl preview_zero
    sta SEG_OFFSET
    lda #<course_segments
    sta COPY_SOURCE
    lda #>course_segments
    sta COPY_SOURCE + 1
preview_segment:
    ldy SEG_OFFSET
    cpy outline_bytes
    bcc preview_segment_edge
    jmp preview_fill
preview_segment_edge:
    lda (COPY_SOURCE),y
    jsr preview_x
    sta LINE_X
    iny
    lda (COPY_SOURCE),y
    jsr preview_y
    sta LINE_Y
    iny
    lda (COPY_SOURCE),y
    jsr preview_x
    sta M_A
    iny
    lda (COPY_SOURCE),y
    jsr preview_y
    sta M_A + 1
    lda M_A
    sec
    sbc LINE_X
    jsr preview_abs
    sta M_B
    sty M_PRODUCT
    lda M_A + 1
    sec
    sbc LINE_Y
    jsr preview_abs
    sta M_B + 1
    sty M_PRODUCT + 1
    lda LINE_Y
    cmp M_A + 1
    bcs preview_ymax
    lda M_A + 1
preview_ymax:
    sta M_PRODUCT + 3
    lda M_B
    sec
    sbc M_B + 1
    sta M_PRODUCT + 2
    lda #$ff                  ; no row recorded on this edge yet
    sta TEMP
preview_line:
    jsr preview_black
    jsr preview_record
    lda LINE_X
    cmp M_A
    bne preview_walk
    lda LINE_Y
    cmp M_A + 1
    beq preview_next
preview_walk:
    lda M_PRODUCT + 2         ; e2 = 2 * err; |err| stays inside a byte
    asl
    sta LINE_LEFT
    clc
    adc M_B + 1               ; x step when e2 > -dy, i.e. e2 + dy > 0
    beq preview_skip_x
    bmi preview_skip_x
    lda M_PRODUCT + 2
    sec
    sbc M_B + 1
    sta M_PRODUCT + 2
    lda LINE_X
    clc
    adc M_PRODUCT
    sta LINE_X
preview_skip_x:
    lda LINE_LEFT             ; y step when e2 < dx; test the original e2
    bmi preview_step_y
    cmp M_B
    bcs preview_line
preview_step_y:
    lda M_PRODUCT + 2
    clc
    adc M_B
    sta M_PRODUCT + 2
    lda LINE_Y
    clc
    adc M_PRODUCT + 1
    sta LINE_Y
    jmp preview_line
preview_next:
    lda SEG_OFFSET
    clc
    adc #5
    sta SEG_OFFSET
    jmp preview_segment

; Even-odd fill of the crossing masks. TEMP is 1 while inside a span.
preview_fill:
    ldx #0
preview_fill_row:
    stx LINE_Y
    lda #0
    sta TEMP
    sta LINE_X
    txa
    asl
    sta LINE_LEFT
    lda #2
    sta M_B
preview_fill_byte:
    ldy LINE_LEFT
    lda SCRATCH_BASE,y
    sta M_A
    inc LINE_LEFT
    lda #8
    sta LINE_X_STEP
preview_fill_bit:
    asl M_A
    bcc preview_fill_off
    lda TEMP
    eor #1
    sta TEMP
    sec
    bcs preview_fill_paint    ; a crossing is black either way
preview_fill_off:
    lda TEMP
    beq preview_fill_next
preview_fill_paint:
    jsr preview_black
preview_fill_next:
    inc LINE_X
    dec LINE_X_STEP
    bne preview_fill_bit
    dec M_B
    bne preview_fill_byte
    ldx LINE_Y
    inx
    cpx #8
    bne preview_fill_row
    rts

; First pixel of this row, except on ymax. XORed so a double peak cancels.
preview_record:
    lda LINE_Y
    cmp M_PRODUCT + 3
    beq preview_record_done
    cmp TEMP
    beq preview_record_done
    sta TEMP
    asl
    sta LINE_LEFT
    lda LINE_X
    cmp #8
    bcc preview_record_low
    sbc #8
    inc LINE_LEFT
preview_record_low:
    tax
    ldy LINE_LEFT
    lda pixel_masks,x
    eor SCRATCH_BASE,y
    sta SCRATCH_BASE,y
preview_record_done:
    rts

; Clears pixel (LINE_X, LINE_Y). Clobbers A, X and Y.
preview_black:
    lda LINE_X
    and #$f8
    clc
    adc LINE_Y
    tay
    lda LINE_X
    and #7
    tax
    lda pixel_masks,x
    eor #$ff
    and (BITMAP_PTR),y
    sta (BITMAP_PTR),y
    rts

; A = 2px units. Returns A / 10, clamped to 15. Preserves Y.
preview_x:
    ldx #16
    bne preview_div_limit
; A = 2px units. Returns (A - 4) / 10, or 0 below the playfield edge
; (pixel 8), clamped to 7. Preserves Y.
preview_y:
    sec
    sbc #4
    bcs preview_y_div
    lda #0
    rts
preview_y_div:
    ldx #8
preview_div_limit:
    stx LINE_X_STEP
preview_div:
    ldx #0
preview_div_loop:
    cmp #10
    bcc preview_div_done
    sbc #10
    inx
    cpx LINE_X_STEP
    bne preview_div_loop
    dex
preview_div_done:
    txa
    rts

; A = signed difference from the sbc just above (carry still valid).
; Returns the absolute value in A and the sign ($01 or $ff) in Y.
preview_abs:
    ldy #1
    bcs preview_abs_pos
    eor #$ff
    adc #1
    ldy #$ff
preview_abs_pos:
    rts

; End of the round in the lower field: RESULTS, then every player as
; #, number and strokes, fewest strokes first. Equal scores keep the
; lower number. Listed totals become $ff; the next round clears them.
; Fire returns to the menu.
SUMMARY_HEAD_ROW = 13
SUMMARY_LIST_ROW = 15
SUMMARY_ROW = SCREEN_BASE + SUMMARY_LIST_ROW * 40
SUMMARY_COLUMN = 16           ; # and number; strokes end five cells later
summary_screen:
    ldx #$ff
    txs
    jsr draw_title_frame
    ldx #summary_head - title_texts
    jsr print_texts
    lda #<SUMMARY_ROW
    sta COPY_TARGET
    lda #>SUMMARY_ROW
    sta COPY_TARGET + 1
    ldx #0
summary_row:
    txa
    pha
    lda #$ff                  ; best remaining total
    sta TEMP
    ldy #0
    ldx #0
summary_find:
    lda totals,y
    cmp TEMP
    bcs summary_find_next     ; higher, or the same score seen earlier
    sta TEMP
    tya
    tax
summary_find_next:
    iny
    cpy player_count
    bcc summary_find
    lda #$ff
    sta totals,x
    ldy #SUMMARY_COLUMN
    lda #HASH_CHAR
    sta (COPY_TARGET),y
    iny
    txa
    clc
    adc #DIGIT_CHAR + 1
    sta (COPY_TARGET),y
    ldy #SUMMARY_COLUMN + 5
    lda TEMP
    jsr print_digits
    lda COPY_TARGET
    clc
    adc #40
    sta COPY_TARGET
    bcc summary_row_page
    inc COPY_TARGET + 1
summary_row_page:
    pla
    tax
    inx
    cpx player_count
    bcc summary_row
    lda #$1b
    sta TED_CONTROL1
summary_loop:
    jsr menu_input
    and #KEY_SHOT
    beq summary_loop
    jmp title_screen

; Course, golfers, labels, pictures and the balls. Display ends on.
title_paint:
    jsr draw_title_frame
    ldx #9
title_figures:
    lda figure_columns,x
    and #$3f
    tay
    lda figure_columns,x
    and #$c0                  ; ECM paper in bits 7-6
    ora #FIGURE_CHAR
    sta FIGURE_ROW,y
    ora #1                    ; second cell, same paper
    sta FIGURE_ROW + 40,y
    dex
    bpl title_figures
    ldx #title_labels - title_texts
    jsr print_texts
    jsr title_window
    jsr title_picks
    lda #BALL_CHAR
    jsr title_ball
    lda #$1b
    sta TED_CONTROL1
    rts

; Filled ball on each choice the cursor is not standing on. A surface
; repaint redraws the pictures and would otherwise wipe a hole's mark.
title_picks:
    lda #MENU_COURSE
    sta POINT_INDEX
title_pick:
    ldx POINT_INDEX
    cpx menu_row
    beq title_pick_next
    lda #PICK_CHAR
    jsr title_ball_on
title_pick_next:
    dec POINT_INDEX
    bpl title_pick
    rts

; The title course with display off, lawn in row 24, the font in black on
; white and MINIGOLF. The course catalogue starts at TITLE_CHAR.
draw_title_frame:
    lda #$0b
    sta TED_CONTROL1
    lda #TITLE_CHAR
    sta intern_base
    lda #TITLE_CHAR_LIMIT
    sta intern_limit
    lda #TITLE_LAST_ROW
    sta last_row
    ldx #TITLE_COURSE
    jsr decode_course
    jsr draw_course
    lda #24
    jsr emit_hidden_row
    lda #$ff
    jsr install_font
    ldx #MENU_GLYPHS * 8 - 1
title_menu_glyph:             ; B, D and the dash, already black on floor
    lda menu_glyphs,x
    sta CHARSET_BASE + LETTER_B * 8,x
    dex
    bpl title_menu_glyph
    ldx #0                    ; MINIGOLF and the menu labels
; X = offset into title_texts: screen address, codes, $ff, ... up to an
; address with high byte 0.
print_texts:
    lda title_texts,x
    sta COPY_TARGET
    lda title_texts + 1,x
    beq print_texts_done
    sta COPY_TARGET + 1
    inx
    inx
    ldy #0
print_text_char:
    lda title_texts,x
    inx
    cmp #$ff
    beq print_texts
    sta (COPY_TARGET),y
    iny
    bne print_text_char
print_texts_done:
    rts

title_texts:
    !word HEADER
    !byte LETTER_M, LETTER_I, LETTER_N, LETTER_I, LETTER_G, LETTER_O, LETTER_L, LETTER_F, $ff
    !byte 0, 0
title_labels:
    !word SURFACE_ROW + SURFACE_COLUMN
    !byte LETTER_B, LETTER_E, LETTER_T, LETTER_O, LETTER_N, 0, 0
    !byte LETTER_G, LETTER_R, LETTER_A, LETTER_S, 0, 0
    !byte LETTER_E, LETTER_R, LETTER_D, LETTER_E, 0, 0
    !byte LETTER_G, LETTER_U, LETTER_M, LETTER_M, LETTER_I, $ff
    !word RANGE_ROW + RANGE_COLUMN
    !byte DIGIT_CHAR + 1, DASH_CHAR, DIGIT_CHAR + 1, DIGIT_CHAR + 8, 0, 0, 0
    !byte DIGIT_CHAR + 1, DASH_CHAR, DIGIT_CHAR + 9, 0, 0, 0
    !byte DIGIT_CHAR + 1, DIGIT_CHAR, DASH_CHAR, DIGIT_CHAR + 1, DIGIT_CHAR + 8, $ff
    !word PLAY_ROW + PLAY_COLUMN
    !byte LETTER_P, LETTER_L, LETTER_A, LETTER_Y, $ff
    !byte 0, 0
summary_head:
    !word SCREEN_BASE + SUMMARY_HEAD_ROW * 40 + SUMMARY_COLUMN
    !byte LETTER_R, LETTER_E, LETTER_S, LETTER_U, LETTER_L, LETTER_T, LETTER_S, $ff
    !byte 0, 0
; Golfers in groups of one to four, one cell apart; the ball below each
; group's middle. Bits 7-6 are the ECM paper (0 black, 1 red, 2 blue,
; 3 yellow); bits 5-0 are the column. Each group reads left to right.
figure_columns:
!byte 13, 15, 16|$40, 18, 19|$40, 20|$80, 22, 23|$40, 24|$80, 25|$c0
player_ball_columns:
!byte 13, 15, 19, 23
; First column of each picture. The number is right-aligned under the
; two cells; the ball replaces the blank just left of the number.
slot_columns:
!byte 12, 18, 24
surface_ball_columns:
!byte 10, 16, 22, 29
range_ball_columns:
!byte 12, 19, 26
range_first:
!byte 0, 0, 9
range_last:
!byte COURSE_COUNT, 9, COURSE_COUNT
row_limit:
!byte 4, 4, COURSE_COUNT + 3
block_codes:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte PREVIEW_CHAR + block * PREVIEW_BLOCK }
block_lo:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte <(CHARSET_BASE + (PREVIEW_CHAR + block * PREVIEW_BLOCK) * 8) }
block_hi:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte >(CHARSET_BASE + (PREVIEW_CHAR + block * PREVIEW_BLOCK) * 8) }

menu_row:                     ; 0 players, 1 surface, 2 course, 3 PLAY
!byte 0
; These three are indexed by menu_row. Do not insert a byte between them.
menu_players:                 ; 0..3: one to four players
!byte 0
menu_surface:                 ; Beton, Gras, Erde, Gummi
!byte GRAS_SURFACE
course_pick:                  ; 0..2 ranges, then one hole
!byte 0
practice_hole:                ; hole under the ball while a picture is chosen
!byte 0
window_first:                 ; first hole shown
!byte 0
block_holes:                  ; hole drawn in each block, $ff: none
!fill PREVIEW_BLOCKS, $ff
window_ahead:                 ; 3 after sliding right, $ff after sliding left
!byte 3
hole_last:                    ; first hole that is not in this round
!byte COURSE_COUNT
player_count:
!byte 1
player:                       ; 0-based, whose turn it is
!byte 0
totals:                       ; strokes of the finished holes per player
!fill 4
