; Title menu shaped like a course, black glyphs on the white floor:
; MINIGOLF; PLAY over one to four golfers; PRACTISE over three holes as
; 1:8 outlines with their numbers and arrows towards further holes. The
; golf ball below marks the choice: up/down switches the row, left/right
; moves in it, fire starts. Hole h is drawn in block h mod 4: the three shown
; and the next one in the direction of the last slide. A hole that is not
; ready is drawn into its block while that block is not shown, so the row
; never shows drawing.
TITLE_CHAR = 35               ; title frame from here on (intern_pattern)
PREVIEW_CHAR = 68             ; four preview blocks of 5 x 3 cells
PREVIEW_BLOCKS = 4
PREVIEW_BLOCK = 5 * 3
TITLE_CHAR_LIMIT = PREVIEW_CHAR - TITLE_CHAR
!if PREVIEW_CHAR + PREVIEW_BLOCKS * PREVIEW_BLOCK > 128 { !error "previews exceed the charset" }
!if TITLE_CHAR < FIGURE_CHAR + 2 { !error "the title frame overlaps the font" }
TITLE_LAST_ROW = 23           ; the title course reaches down to row 23
HEADER = SCREEN_BASE + 4 * 40 + 16
FIGURE_ROW = SCREEN_BASE + 13 * 40   ; and the row below, then the ball
PREVIEW_ROW = SCREEN_BASE + 18 * 40  ; three rows of outlines, then the number
HOLE_ROW = PREVIEW_ROW + 40          ; arrows
NUMBER_ROW = PREVIEW_ROW + 120       ; ball and number below each outline
ARROW_LEFT_COLUMN = 9
ARROW_RIGHT_COLUMN = 29
; A preview block holds its outline column by column: pixel (x, y) at
; block + (x / 8) * 24 + y; course cell (x + 1, y + 1) is pixel (x, y).

title_screen:
    ldx #$ff                  ; entered from the game loop: drop its frames
    txs
    jsr draw_title_frame
    ldx #9
title_figures:
    ldy figure_columns,x
    lda #FIGURE_CHAR
    sta FIGURE_ROW,y
    lda #FIGURE_CHAR + 1
    sta FIGURE_ROW + 40,y
    dex
    bpl title_figures
    lda #$ff
    ldx #PREVIEW_BLOCKS - 1
title_forget:
    sta block_holes,x
    dex
    bpl title_forget
    ldx #title_labels - title_texts
    jsr print_texts
    lda #3
    sta window_ahead          ; ready the hole right of the row
    jsr title_window
    lda #BALL_CHAR
    jsr title_ball
    lda #$1b
    sta TED_CONTROL1
title_loop:
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
    jmp title_start
title_up:
    lda menu_row
    beq title_loop
    lda #BLANK_CHAR
    jsr title_ball
    dec menu_row
    bpl title_ball_moved
title_down:
    lda menu_row
    bne title_loop
    lda #BLANK_CHAR
    jsr title_ball
    inc menu_row
    bne title_ball_moved
title_left:
    lda #$ff
    bne title_step
title_right:
    lda #1
title_step:
    pha
    lda #BLANK_CHAR
    jsr title_ball
    pla
    ldx menu_row
    bne title_hole_step
    clc
    adc menu_players
    cmp #4
    bcs title_ball_moved      ; no further entry that way
    sta menu_players
    bcc title_ball_moved
title_hole_step:
    clc
    adc practice_hole
    cmp #COURSE_COUNT
    bcs title_ball_moved
    sta practice_hole
    ldx #$ff                  ; sliding left: ready the hole left of it
    cmp window_first
    bcc title_slide           ; left of the window: it starts here
    sbc #2
    bcc title_ball_moved
    cmp window_first
    beq title_ball_moved
    bcc title_ball_moved      ; inside the window
    ldx #3
title_slide:                  ; right of it: it ends here
    sta window_first
    stx window_ahead
    jsr title_window
title_ball_moved:
    lda #BALL_CHAR
    jsr title_ball
    jmp title_loop

; A = screen code below the chosen golfers or hole.
title_ball:
    ldx menu_row
    bne title_ball_hole
    ldx menu_players
    ldy player_ball_columns,x
    sta FIGURE_ROW + 80,y
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
    bcs title_ball_number     ; two digits from hole 10 on
    iny
title_ball_number:
    sta NUMBER_ROW + 2,y      ; right before the number
    rts

title_start:
    lda #0
    ldx #3
title_clear_totals:
    sta totals,x
    dex
    bpl title_clear_totals
    sta player
    sta practice
    sta HOLE
    ldx menu_players
    inx                       ; one to four players
    lda menu_row
    beq title_players
    sta practice              ; nonzero
    lda practice_hole
    sta HOLE
    ldx #1
title_players:
    stx player_count
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
    ldx #5
title_window_codes:           ; carry stays clear: codes < 128
    sta PREVIEW_ROW,y
    adc #1
    sta PREVIEW_ROW + 40,y
    adc #1
    sta PREVIEW_ROW + 80,y
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
    adc #4                    ; last digit under the outline's right end
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

; Outline of the decoded hole into the block at BITMAP_PTR.
preview_course:
    lda #0
    sta SEG_OFFSET
preview_segment:
    ldx SEG_OFFSET
    cpx SEGMENT_BYTES
    bcs preview_cup
    ; Vertices lie on the 8-pixel grid: 2-pixel units / 4 is exact.
    lda course_segments,x
    jsr preview_cell
    sta LINE_X
    lda course_segments + 1,x
    jsr preview_cell
    sta LINE_Y
    lda course_segments + 2,x
    jsr preview_cell
    sec
    sbc LINE_X
    jsr preview_axis
    sty LINE_X_STEP
    sta LINE_LEFT
    lda course_segments + 3,x
    jsr preview_cell
    sec
    sbc LINE_Y
    jsr preview_axis
    sty LINE_Y_STEP
    ora LINE_LEFT             ; 0, 45 or 90 degrees: the longer axis
    sta LINE_LEFT
preview_line:
    jsr preview_plot
    clc
    lda LINE_X
    adc LINE_X_STEP
    sta LINE_X
    clc
    lda LINE_Y
    adc LINE_Y_STEP
    sta LINE_Y
    dec LINE_LEFT
    bne preview_line
    lda SEG_OFFSET
    clc
    adc #5
    sta SEG_OFFSET
    bne preview_segment
preview_cup:
    lda COURSE_CUP_X_HI
    lsr
    lda COURSE_CUP_X
    ror
    lsr
    lsr
    sec
    sbc #1
    sta LINE_X
    lda COURSE_CUP_Y
    lsr
    lsr
    lsr
    sec
    sbc #1
    sta LINE_Y
; Clears pixel (LINE_X, LINE_Y): black on the white floor. X = SEG_OFFSET.
preview_plot:
    lda LINE_X
    lsr
    lsr
    lsr
    tay
    lda LINE_X
    and #7
    tax
    lda preview_columns,y
    clc
    adc LINE_Y
    tay
    lda pixel_masks,x
    eor #$ff
    and (BITMAP_PTR),y
    sta (BITMAP_PTR),y
    ldx SEG_OFFSET
    rts

; A = 2-pixel units. Returns the preview coordinate units / 4 - 1.
preview_cell:
    lsr
    lsr
    sec
    sbc #1
    rts

; A = signed difference. Returns its size in A, its sign in Y and
; X = SEG_OFFSET.
preview_axis:
    ldy #0
    tax
    beq preview_axis_done
    iny
    tax
    bpl preview_axis_done
    eor #$ff
    clc
    adc #1
    ldy #$ff
preview_axis_done:
    ldx SEG_OFFSET
    rts

; End of the round, one row per player: club, player and strokes, a ball
; beside the best; below them flag and (par). Fire returns to the menu.
SUMMARY_ROW = SCREEN_BASE + 12 * 40
SUMMARY_COLUMN = 15           ; club; ball left, strokes up to column 20
summary_screen:
    ldx #$ff
    txs
    jsr draw_title_frame
    ldx #summary_par - title_texts
    jsr print_texts
    lda #$ff
    sta TEMP                  ; best total
    ldx player_count
    dex
summary_best:
    lda totals,x
    cmp TEMP
    bcs summary_best_next
    sta TEMP
summary_best_next:
    dex
    bpl summary_best
    lda #<SUMMARY_ROW
    sta COPY_TARGET
    lda #>SUMMARY_ROW
    sta COPY_TARGET + 1
    ldx #0
summary_row:
    stx player
    lda totals,x
    ldy #SUMMARY_COLUMN + 5
    jsr print_digits
    ldx player
    lda totals,x
    cmp TEMP
    bne summary_sign
    lda #BALL_CHAR
    ldy #SUMMARY_COLUMN - 1
    sta (COPY_TARGET),y
summary_sign:
    txa
    clc
    adc #DIGIT_CHAR + 1
    ldy #SUMMARY_COLUMN + 1
    sta (COPY_TARGET),y
    dey
    lda #CLUB_CHAR
    sta (COPY_TARGET),y
    lda COPY_TARGET
    clc
    adc #80                   ; every other row
    sta COPY_TARGET
    bcc summary_next
    inc COPY_TARGET + 1
summary_next:
    ldx player
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
    ldx #0                    ; MINIGOLF
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
    !word SCREEN_BASE + 12 * 40 + 18
    !byte LETTER_P, LETTER_L, LETTER_A, LETTER_Y, $ff
    !word SCREEN_BASE + 17 * 40 + 16
    !byte LETTER_P, LETTER_R, LETTER_A, LETTER_C, LETTER_T, LETTER_I, LETTER_S, LETTER_E, $ff
    !byte 0, 0
summary_par:                  ; flag and (par), the par below the strokes
    !word SCREEN_BASE + 21 * 40 + SUMMARY_COLUMN
    !byte FLAG_CHAR, BLANK_CHAR, BLANK_CHAR, PAREN_LEFT_CHAR
    !byte (TOTAL_PAR > 9) * (DIGIT_CHAR + TOTAL_PAR / 10)   ; blank below 10
    !byte DIGIT_CHAR + TOTAL_PAR % 10, PAREN_RIGHT_CHAR, $ff
    !byte 0, 0
; Golfers in groups of one to four, one cell apart; the ball below each
; group's middle.
figure_columns:
!byte 13, 15, 16, 18, 19, 20, 22, 23, 24, 25
player_ball_columns:
!byte 13, 15, 19, 23
; First column of each shown outline, one cell between them. Below it the
; number, right aligned, with the ball right before it.
slot_columns:
!byte 11, 17, 23
preview_columns:
!byte 0, 24, 48, 72, 96
block_codes:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte PREVIEW_CHAR + block * PREVIEW_BLOCK }
block_lo:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte <(CHARSET_BASE + (PREVIEW_CHAR + block * PREVIEW_BLOCK) * 8) }
block_hi:
!for block, 0, PREVIEW_BLOCKS - 1 { !byte >(CHARSET_BASE + (PREVIEW_CHAR + block * PREVIEW_BLOCK) * 8) }

menu_row:                     ; 0: players, 1: holes
!byte 0
menu_players:                 ; 0..3: one to four players
!byte 0
practice_hole:
!byte 0
window_first:                 ; first hole shown
!byte 0
block_holes:                  ; hole drawn in each block, $ff: none
!fill PREVIEW_BLOCKS, $ff
window_ahead:                 ; 3 after sliding right, $ff after sliding left
!byte 3
practice:                     ; nonzero: one hole, then back to the menu
!byte 0
player_count:
!byte 1
player:                       ; 0-based, whose turn it is
!byte 0
totals:                       ; strokes of the finished holes per player
!fill 4
