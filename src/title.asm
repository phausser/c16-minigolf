; Title menu on a rectangular course: text in a 7 x 5 font, one glyph per
; character cell (black on the white floor), and 1:8 outlines of nine
; holes per page. Joystick up/down picks an entry, left/right changes the
; practice hole, fire starts.
; Glyph codes follow build/title.ct (tools/generate_assets.py): blank,
; the letters of TITLE_LETTERS, digits, ball. Other characters are blank.
BLANK_CHAR = 0                ; white floor
DIGIT_CHAR = 16
CURSOR_CHAR = 26
!if CURSOR_CHAR + 1 != TITLE_GLYPHS { !error "TITLE_GLYPHS must match the glyph codes" }
TITLE_CHAR = 27               ; title frame and previews from here on
TITLE_CHAR_LIMIT = TITLE_FONT_CHAR - TITLE_CHAR
CURSOR_COLUMN = 5
MENU_COLUMN = 7
MENU_PRACTICE = 4             ; menu entries 0..3: one to four players
PRACTICE_ROW = 17
; Preview: 5 x 3 cells, column by column in the scratch area, so pixel
; (x, y) lies at PREVIEW_BITMAP + (x / 8) * 24 + y. Course cell (x + 1,
; y + 1) becomes preview pixel (x, y).
PREVIEW_PAGE = 9
PREVIEW_BITMAP = SCRATCH_BASE
PREVIEW_BYTES = 5 * 3 * 8
!if <PREVIEW_BITMAP != 0 { !error "the preview bitmap must start a page" }

title_screen:
    ldx #$ff                  ; entered from the game loop: drop its frames
    txs
    jsr draw_title_frame
    lda pattern_count
    sta title_patterns
    ldx #title_menu - title_texts
    jsr print_texts
    lda #$ff
    sta title_page            ; draws the page of the practice hole
    jsr title_holes
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
    lda #BLANK_CHAR
    jsr title_cursor
    dec menu_item
    bpl title_cursor_moved
title_down:
    lda menu_item
    cmp #MENU_PRACTICE
    beq title_loop
    lda #BLANK_CHAR
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
    jsr title_holes
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
    ; Back to the game charset: no title glyphs, blank 32, power bar, HUD.
    lda #$0b
    sta TED_CONTROL1
    lda #COURSE_CHAR
    sta intern_base
    lda #COURSE_CHAR_LIMIT
    sta intern_limit
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

; Page of the practice hole (drawn when it changes), then the numbers
; below the previews with a ball beside the practice hole.
title_holes:
    ldx #0
    lda practice_hole
    cmp #PREVIEW_PAGE
    bcc title_page_known
    ldx #PREVIEW_PAGE
title_page_known:
    cpx title_page
    beq title_labels
    stx title_page
    lda title_patterns        ; the previous page's glyphs are free again
    sta pattern_count
    ldx #0
title_preview:
    stx POINT_INDEX
    jsr title_slot_target
    lda #$ff
    ldx #PREVIEW_BYTES
title_preview_clear:
    sta PREVIEW_BITMAP - 1,x
    dex
    bne title_preview_clear
    lda TEMP
    cmp #COURSE_COUNT
    bcs title_preview_cells   ; no such hole: empty floor
    tax
    jsr decode_course
    jsr preview_course
title_preview_cells:
    lda #<PREVIEW_BITMAP
    sta BITMAP_PTR
    lda #>PREVIEW_BITMAP
    sta BITMAP_PTR + 1
    lda #0
    sta HUD_VALUE             ; preview column
title_cell_column:
    ldy HUD_VALUE
title_cell:
    sty GLYPH                 ; row * 40 + column
    jsr intern_pattern
    ldy GLYPH
    sta (COPY_TARGET),y
    lda BITMAP_PTR
    clc
    adc #8
    sta BITMAP_PTR
    tya                       ; carry clear: the bitmap stays in one page
    adc #40
    tay
    cmp #3 * 40
    bcc title_cell
    inc HUD_VALUE
    lda HUD_VALUE
    cmp #5
    bcc title_cell_column
    ldx POINT_INDEX
    inx
    cpx #PREVIEW_PAGE
    bcc title_preview
title_labels:
    ldx #0
title_label:
    stx POINT_INDEX
    jsr title_slot_target
    lda COPY_TARGET           ; three rows below the preview
    clc
    adc #3 * 40
    sta COPY_TARGET
    bcc title_label_row
    inc COPY_TARGET + 1
title_label_row:
    lda TEMP
    cmp #COURSE_COUNT
    bcs title_label_next
    ldx #BLANK_CHAR
    cmp practice_hole
    bne title_label_marker
    ldx #CURSOR_CHAR
title_label_marker:
    txa
    ldy #1
    sta (COPY_TARGET),y
    ldx TEMP
    inx
    txa
    iny
    jsr screen_number
title_label_next:
    ldx POINT_INDEX
    inx
    cpx #PREVIEW_PAGE
    bcc title_label
    rts

; X = slot 0..8. TEMP = its hole, COPY_TARGET = its top left cell.
title_slot_target:
    txa
    clc
    adc title_page
    sta TEMP
    ldy slot_rows,x
    lda screen_rows_lo,y
    clc
    adc slot_columns,x
    sta COPY_TARGET
    lda screen_rows_hi,y
    adc #0
    sta COPY_TARGET + 1
    rts

; Outline of the decoded hole into the preview bitmap.
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
; Clears preview pixel (LINE_X, LINE_Y): black on the white floor.
; Leaves X = SEG_OFFSET.
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
    and PREVIEW_BITMAP,y
    sta PREVIEW_BITMAP,y
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

; End of the round: every player's strokes, a ball beside the best, the
; course par below. Fire returns to the menu.
SUMMARY_SCORE_COLUMN = 16
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
    ldy menu_rows,x
    lda screen_rows_lo,y
    sta COPY_TARGET
    lda screen_rows_hi,y
    sta COPY_TARGET + 1
    ldy #MENU_COLUMN + 5
summary_name_char:
    lda summary_name - MENU_COLUMN,y
    sta (COPY_TARGET),y
    dey
    cpy #MENU_COLUMN
    bcs summary_name_char
    txa                       ; carry clear
    adc #DIGIT_CHAR + 1
    ldy #MENU_COLUMN + 7
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

; A = 0..255 without leading zeros at (COPY_TARGET),Y and on, then one
; blank cell. Clobbers X.
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
    clc
    adc #DIGIT_CHAR
    sta (COPY_TARGET),y
    iny
    inx
    cpx HUD_COUNT
    bne screen_number_digit
    lda #BLANK_CHAR
    sta (COPY_TARGET),y
    rts

; Rectangle course with display off, lawn in row 24, title glyphs below
; TITLE_CHAR. The course catalogue starts at TITLE_CHAR.
draw_title_frame:
    lda #$0b
    sta TED_CONTROL1
    lda #TITLE_CHAR
    sta intern_base
    lda #TITLE_CHAR_LIMIT
    sta intern_limit
    ldx #TITLE_COURSE
    jsr decode_course
    jsr draw_course
    lda #24
    jsr emit_hidden_row
    ldx #0
title_glyph:
    stx GLYPH
    txa
    jsr charset_address
    ldy #7
    lda #$ff                  ; rows 0, 6 and 7 stay floor
    sta (FONT_PTR),y
    dey
    sta (FONT_PTR),y
    ldy #0
    sta (FONT_PTR),y
    txa
    asl
    asl
    adc GLYPH                 ; X * 5, carry clear
    tax
title_glyph_row:
    lda TITLE_FONT_STORE,x
    eor #$ff
    iny
    sta (FONT_PTR),y
    inx
    cpy #5
    bne title_glyph_row
    ldx GLYPH
    inx
    cpx #TITLE_GLYPHS
    bne title_glyph
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

preview_columns:
!byte 0, 24, 48, 72, 96
; Top left cells of the nine previews: three columns, three rows.
slot_rows:
!byte 4, 4, 4, 9, 9, 9, 14, 14, 14
slot_columns:
!byte 18, 25, 32, 18, 25, 32, 18, 25, 32
menu_rows:
!byte 8, 10, 12, 14, PRACTICE_ROW

!macro title_text .row, .column, .text {
    !word SCREEN_BASE + .row * 40 + .column
    !convtab "build/title.ct" { !text .text }
    !byte $ff
}
title_texts:
title_menu:
    +title_text 8, MENU_COLUMN, "1 player"
    +title_text 10, MENU_COLUMN, "2 players"
    +title_text 12, MENU_COLUMN, "3 players"
    +title_text 14, MENU_COLUMN, "4 players"
    +title_text PRACTICE_ROW, MENU_COLUMN, "practice"
title_header:
    +title_text 4, 5, "minigolf"
    !byte 0, 0
summary_par:
    +title_text PRACTICE_ROW, MENU_COLUMN, "par"
    !word SCREEN_BASE + PRACTICE_ROW * 40 + SUMMARY_SCORE_COLUMN
    !byte DIGIT_CHAR + TOTAL_PAR / 10, DIGIT_CHAR + TOTAL_PAR % 10, $ff
    !byte 0, 0
!if * - title_texts > 256 { !error "title texts need an 8-bit index" }
summary_name:
!convtab "build/title.ct" { !text "player" }

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
title_page:                   ; first hole of the page shown
!byte 0
title_patterns:               ; pattern_count after the frame
!byte 0
