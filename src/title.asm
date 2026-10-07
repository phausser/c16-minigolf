; Title menu on a rectangular course: English text in the ROM font, copied
; inverted into the RAM charset (black letters on the white floor), and a
; 1:4 outline of the practice hole. Joystick up/down picks an entry,
; left/right changes the practice hole, fire starts.
ROM_FONT = $d000              ; upper case font in the KERNAL ROM
CURSOR_CHAR = 31              ; ROM ball (screen code 81) copied here
CURSOR_COLUMN = 6
MENU_PRACTICE = 4             ; menu entries 0..3: one to four players
BLANK_FLOOR = 32              ; the inverted ROM space: plain white floor
PRACTICE_ROW = 16
PRACTICE_NUMBER = SCREEN_BASE + PRACTICE_ROW * 40 + 18
; Preview: 10 x 5 characters, column by column, so that the byte of preview
; pixel (x, y) lies at PREVIEW_GLYPHS + (x / 8) * 40 + y. Course pixel
; (8 + 4x, 8 + 4y) maps to (x, y).
PREVIEW_CHAR = 78
PREVIEW_COLUMNS = 10
PREVIEW_ROWS = 5
PREVIEW_GLYPHS = CHARSET_BASE + PREVIEW_CHAR * 8
PREVIEW_BYTES = PREVIEW_COLUMNS * PREVIEW_ROWS * 8
PREVIEW_SCREEN = SCREEN_BASE + 12 * 40 + 25   ; bottom row beside PRACTICE

title_screen:
    ldx #$ff                  ; entered from the game loop: drop its frames
    txs
    jsr draw_title_frame
    ldx #title_menu - title_texts
    jsr print_texts
    ldy #0
    lda #PREVIEW_CHAR
    clc
title_preview_codes:          ; the screen codes never change
!for preview_row, 0, PREVIEW_ROWS - 1 {
    sta PREVIEW_SCREEN + preview_row * 40,y
    adc #1
}
    iny
    cpy #PREVIEW_COLUMNS      ; carry stays clear while looping
    bne title_preview_codes
    jsr title_practice_hole
    lda #CURSOR_CHAR
    jsr title_cursor
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
    lda menu_item
    beq title_loop
    lda #BLANK_FLOOR
    jsr title_cursor
    dec menu_item
    bpl title_cursor_moved
title_down:
    lda menu_item
    cmp #MENU_PRACTICE
    beq title_loop
    lda #BLANK_FLOOR
    jsr title_cursor
    inc menu_item
title_cursor_moved:
    lda #CURSOR_CHAR
    jsr title_cursor
    jmp title_loop
title_left:
    ldx practice_hole
    bne title_hole_down
    ldx #COURSE_COUNT
title_hole_down:
    dex
    bpl title_hole_changed
title_right:
    ldx practice_hole
    inx
    cpx #COURSE_COUNT
    bcc title_hole_changed
    ldx #0
title_hole_changed:
    lda menu_item
    cmp #MENU_PRACTICE
    bne title_loop            ; the hole changes only on PRACTICE
    stx practice_hole
    jsr title_practice_hole
    jmp title_loop

; A = screen code at the cursor column of the selected entry.
title_cursor:
    ldx menu_item
    ldy menu_rows,x
    ldx screen_rows_lo,y
    stx COPY_TARGET
    ldx screen_rows_hi,y
    stx COPY_TARGET + 1
    ldy #CURSOR_COLUMN
    sta (COPY_TARGET),y
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
    ldx menu_item
    inx                       ; entries 0..3: one to four players
    cpx #MENU_PRACTICE + 1
    bcc title_players
    stx practice              ; nonzero
    lda practice_hole
    sta HOLE
    ldx #1
title_players:
    stx player_count
    ; Back to the game charset: no ROM letters, blank 32, power bar, HUD.
    lda #$0b
    sta TED_CONTROL1
    ldx #0
    txa
title_clear_font:
    sta CHARSET_BASE,x
    sta CHARSET_BASE + $100,x
    inx
    bne title_clear_font
    jsr install_bar_glyphs
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

; End of the round: every player's strokes, a ball beside the best, the
; course par below. Fire returns to the menu.
SUMMARY_NAME_COLUMN = 8
SUMMARY_SCORE_COLUMN = 19
summary_screen:
    ldx #$ff
    txs
    jsr draw_title_frame
    ldx #title_header - title_texts
    jsr print_texts
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
    ldx #0
summary_row:
    stx player
    txa
    asl
    adc #7                    ; rows 7, 9, 11, 13 like the menu
    tay
    lda screen_rows_lo,y
    sta COPY_TARGET
    lda screen_rows_hi,y
    sta COPY_TARGET + 1
    ldy #SUMMARY_NAME_COLUMN + 6
summary_name_char:
    lda summary_name - SUMMARY_NAME_COLUMN,y
    sta (COPY_TARGET),y
    dey
    cpy #SUMMARY_NAME_COLUMN
    bcs summary_name_char
    txa                       ; carry clear
    adc #"1"
    ldy #SUMMARY_NAME_COLUMN + 7
    sta (COPY_TARGET),y
    lda totals,x
    cmp TEMP
    bne summary_score
    lda #CURSOR_CHAR
    ldy #CURSOR_COLUMN
    sta (COPY_TARGET),y
summary_score:
    lda totals,x
    ldy #SUMMARY_SCORE_COLUMN
    jsr screen_number
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

; A = 0..255 without leading zeros at (COPY_TARGET),Y and on.
screen_number:
    sty GLYPH
    pha
    jsr hud_begin
    pla
    jsr hud_number
    ldy GLYPH
    ldx #0
screen_number_digit:
    lda hud_text,x
    ora #"0"
    sta (COPY_TARGET),y
    iny
    inx
    cpx HUD_COUNT
    bne screen_number_digit
    rts

; Rectangle course with display off, lawn in row 24, ROM font in 0..63.
draw_title_frame:
    lda #$0b
    sta TED_CONTROL1
    ldx #TITLE_COURSE
    jsr decode_course
    jsr draw_course
    lda #24
    jsr emit_hidden_row
    ldx #0
title_copy_font:
    lda ROM_FONT,x
    eor #$ff
    sta CHARSET_BASE,x
    lda ROM_FONT + $100,x
    eor #$ff
    sta CHARSET_BASE + $100,x
    inx
    bne title_copy_font
    ldx #7
title_copy_ball:
    lda ROM_FONT + 81 * 8,x
    eor #$ff
    sta CHARSET_BASE + CURSOR_CHAR * 8,x
    dex
    bpl title_copy_ball
    rts

; X = offset into title_texts: screen address, screen codes, $ff, ...
; up to an address with high byte 0.
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

; Number and outline of the practice hole.
title_practice_hole:
    ldx practice_hole
    inx
    txa
    ldx #BLANK_FLOOR
    cmp #10
    bcc title_number_tens
    sbc #10
    ldx #"1"
title_number_tens:
    stx PRACTICE_NUMBER
    ora #"0"
    sta PRACTICE_NUMBER + 1
    ldx #PREVIEW_BYTES / 2
    lda #$ff
title_preview_clear:
    sta PREVIEW_GLYPHS - 1,x
    sta PREVIEW_GLYPHS + PREVIEW_BYTES / 2 - 1,x
    dex
    bne title_preview_clear
    ldx practice_hole
    jsr decode_course
    lda #0
    sta SEG_OFFSET
preview_segment:
    ldx SEG_OFFSET
    cpx SEGMENT_BYTES
    bcs preview_cup
    ; Vertices lie on the 8-pixel grid: 2-pixel units / 2 is exact.
    lda course_segments,x
    lsr
    sec
    sbc #2
    sta LINE_X
    lda course_segments + 1,x
    lsr
    sec
    sbc #2
    sta LINE_Y
    lda course_segments + 2,x
    lsr
    sec
    sbc #2
    sec
    sbc LINE_X
    jsr preview_axis
    sty LINE_X_STEP
    sta LINE_LEFT
    ldx SEG_OFFSET
    lda course_segments + 3,x
    lsr
    sec
    sbc #2
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
    ; The cup as a 2 x 2 dot at (cup / 4 - 2).
    lda COURSE_CUP_X_HI
    lsr
    lda COURSE_CUP_X
    ror
    lsr
    sec
    sbc #2
    sta LINE_X
    lda COURSE_CUP_Y
    lsr
    lsr
    sec
    sbc #2
    sta LINE_Y
    jsr preview_plot
    inc LINE_X
    jsr preview_plot
    inc LINE_Y
    jsr preview_plot
    dec LINE_X
; Clears preview pixel (LINE_X, LINE_Y): black on the white floor.
preview_plot:
    lda LINE_X
    lsr
    lsr
    lsr
    tax
    lda preview_columns_lo,x
    clc
    adc LINE_Y
    sta BITMAP_PTR
    lda preview_columns_hi,x
    adc #0
    sta BITMAP_PTR + 1
    lda LINE_X
    and #7
    tax
    lda pixel_masks,x
    eor #$ff
    ldy #0
    and (BITMAP_PTR),y
    sta (BITMAP_PTR),y
    rts

; A = signed difference. Returns its size in A and its sign in Y.
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
    rts

preview_columns_lo:
!for preview_column, 0, PREVIEW_COLUMNS - 1 { !byte <(PREVIEW_GLYPHS + preview_column * 40) }
preview_columns_hi:
!for preview_column, 0, PREVIEW_COLUMNS - 1 { !byte >(PREVIEW_GLYPHS + preview_column * 40) }

menu_rows:
!byte 7, 9, 11, 13, PRACTICE_ROW
!macro title_text .row, .column, .text {
    !word SCREEN_BASE + .row * 40 + .column
    !scr .text
    !byte $ff
}
title_texts:
title_menu:
    +title_text 7, 8, "1 player"
    +title_text 9, 8, "2 players"
    +title_text 11, 8, "3 players"
    +title_text 13, 8, "4 players"
    +title_text PRACTICE_ROW, 8, "practice <  >"
title_header:
    +title_text 4, 6, "minigolf"
    !byte 0, 0
summary_par:
    +title_text PRACTICE_ROW, SUMMARY_NAME_COLUMN, "par"
    !word SCREEN_BASE + PRACTICE_ROW * 40 + SUMMARY_SCORE_COLUMN
    !byte $30 + TOTAL_PAR / 10, $30 + TOTAL_PAR % 10, $ff   ; screen code digits
    !byte 0, 0
!if * - title_texts > 256 { !error "title texts need an 8-bit index" }

menu_item:
!byte 0
practice_hole:
!byte 0
practice:                     ; nonzero: one hole, then back to the menu
!byte 0
player_count:
!byte 1
player:                       ; 0-based, whose turn it is
!byte 0
totals:                       ; strokes of the finished holes per player
!fill 4
summary_name:
!scr "player "
