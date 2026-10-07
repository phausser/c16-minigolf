draw_dynamic:
    jsr ball_screen_position
    lda HOLED
    beq ball_visible
    rts
ball_visible:
    sec
    lda BALL_SCREEN_X
    sbc #2
    sta PIXEL_X
    lda BALL_SCREEN_X + 1
    sbc #0
    sta PIXEL_X + 1
    lda BALL_SCREEN_Y
    sec
    sbc #2
    sta PIXEL_Y
    ; Five mask rows per pixel alignment; the right byte column is touched
    ; only from alignment 4 and only left of x = 312.
    lda PIXEL_X
    and #7
    sta TEMP
    asl
    asl
    adc TEMP
    sta BALL_MASK_INDEX       ; alignment * 5
    lda #0
    sta BALL_SIDE
ball_column:
    lda BALL_MASK_INDEX
    sta BALL_MASK_POS
    clc
    adc #5
    sta BALL_MASK_END
    lda PIXEL_Y
    and #7
    sta BALL_ROW_Y
    lda PIXEL_Y
    lsr
    lsr
    lsr
    sta BALL_CELL_ROW
    ; One dynamic character per cell, then the rows inside it. Cells off
    ; the playfield are drawn into the idle renderer scratch instead.
ball_cell:
    lda BALL_CELL_ROW
    beq ball_cell_hidden
    cmp #21
    bcs ball_cell_hidden
    jsr dynamic_cell
    jmp ball_cell_ready
ball_cell_hidden:
    lda #<SCRATCH_BASE
    sta FONT_PTR
    lda #>SCRATCH_BASE
    sta FONT_PTR + 1
ball_cell_ready:
    ldx BALL_MASK_POS
    ldy BALL_ROW_Y
ball_row:
    lda (FONT_PTR),y
    and ball_masks,x
    sta (FONT_PTR),y
    inx
    cpx BALL_MASK_END
    beq ball_column_done
    iny
    cpy #8
    bne ball_row
    stx BALL_MASK_POS
    inc BALL_CELL_ROW
    lda #0
    sta BALL_ROW_Y
    beq ball_cell
ball_column_done:
    lda BALL_SIDE
    bne ball_columns_done
    lda TEMP
    cmp #4
    bcc ball_columns_done
    lda PIXEL_X + 1
    beq ball_right_column
    lda PIXEL_X
    cmp #<(312 - 256)
    bcs ball_columns_done
ball_right_column:
    inc BALL_SIDE
    lda BALL_MASK_INDEX
    clc                       ; carry differs between the x < 256 and x >= 256 paths
    adc #40                   ; the right table
    sta BALL_MASK_INDEX
    clc
    lda PIXEL_X
    adc #8
    sta PIXEL_X
    bcc ball_column
    inc PIXEL_X + 1
    bne ball_column
ball_columns_done:
    lda PAUSED
    ora ROLLING
    beq aim_draw
    rts
aim_draw:

    ; Fractional accumulation gives visibly distinct 128 directions without
    ; a separate bitmap for each angle. This is display data, not physics.
    lda ANGLE
    jsr lookup_aim_step
    sta AIM_STEP_X
    lda ANGLE
    sec
    sbc #32
    jsr lookup_aim_step
    sta AIM_STEP_Y
    lda BALL_SCREEN_X
    sta AIM_X
    lda BALL_SCREEN_X + 1
    sta AIM_X + 1
    lda BALL_SCREEN_Y
    sta AIM_Y
    lda #0
    sta AIM_Y + 1
    ldx #4
aim_start_shift:
    asl AIM_X
    rol AIM_X + 1
    asl AIM_Y
    rol AIM_Y + 1
    dex
    bne aim_start_shift
    ; Walking dots: start AIM_PHASE single pixels (a quarter step each)
    ; further out, so every dot moves outwards and the outermost one
    ; reappears at the inner end of the fixed 8..35 pixel window.
    lda AIM_STEP_X
    pha
    lda AIM_STEP_Y
    pha
    ldx #1
aim_quarter:
    lda AIM_STEP_X,x
    cmp #$80
    ror
    cmp #$80
    ror
    sta AIM_STEP_X,x
    dex
    bpl aim_quarter
    lda AIM_PHASE
    and #3
    tax
    beq aim_phase_done
aim_phase:
    jsr advance_aim
    dex
    bne aim_phase
aim_phase_done:
    pla
    sta AIM_STEP_Y
    pla
    sta AIM_STEP_X
    stx POINT_INDEX
aim_next:
    jsr advance_aim
    ; Skip the first point inside/next to the ball.
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #2
    bcc aim_next
    jsr aim_coordinates
    lda PIXEL_X + 1
    cmp #1
    bcc aim_x_on_screen
    bne aim_skip_pixel
    lda PIXEL_X
    cmp #64
    bcs aim_skip_pixel
aim_x_on_screen:
    lda PIXEL_X
    and #7
    tax
    lda pixel_masks,x
    sta PIXEL_MASK            ; one pixel; the ball leaves a multi-bit mask
    jsr punch_pixel           ; clips y to the playfield itself
aim_skip_pixel:
    lda POINT_INDEX
    cmp #8
    bne aim_next
aim_done:
    rts

; Four pixels along ANGLE in 1/16 pixel units: (cos + 2) / 4, signed.
lookup_aim_step:
    jsr cosine_unit
    clc
    lda M_A
    adc #2
    sta M_A
    lda M_A + 1
    adc #0
    ldx #2
aim_unit_scale:
    cmp #$80
    ror
    ror M_A
    dex
    bne aim_unit_scale
    lda M_A
    rts

advance_aim:
    clc
    lda AIM_X
    adc AIM_STEP_X
    sta AIM_X
    lda #0
    bit AIM_STEP_X
    bpl aim_x_sign
    lda #$ff
aim_x_sign:
    adc AIM_X + 1
    sta AIM_X + 1
    clc
    lda AIM_Y
    adc AIM_STEP_Y
    sta AIM_Y
    lda #0
    bit AIM_STEP_Y
    bpl aim_y_sign
    lda #$ff
aim_y_sign:
    adc AIM_Y + 1
    sta AIM_Y + 1
    rts

aim_coordinates:
    lda AIM_X
    sta PIXEL_X
    lda AIM_X + 1
    sta PIXEL_X + 1
    ldx #4
aim_shift_x:
    lsr PIXEL_X + 1
    ror PIXEL_X
    dex
    bne aim_shift_x
    lda AIM_Y
    sta PIXEL_Y
    lda AIM_Y + 1
    ldx #4
aim_shift_y:
    lsr
    ror PIXEL_Y
    dex
    bne aim_shift_y
    rts

; Status row in the 5-pixel HUD font: flag and hole number from the
; left, club and "strokes/par" right aligned. Glyph rows 1..5, like the bar.
draw_status:
    jsr hud_clear
    jsr hud_begin
    lda #HUD_FLAG
    jsr hud_put
    lda #HUD_GAP
    jsr hud_put
    ldx HOLE
    inx
    txa
    jsr hud_number
    ldx player_count          ; several players: "P" and whose turn it is
    dex
    beq status_left_done
    lda #HUD_GAP
    jsr hud_put
    lda #HUD_PLAYER
    jsr hud_put
    ldx player
    inx
    txa
    jsr hud_number
status_left_done:
    lda #HUD_LEFT_X
    sta HUD_X
    jsr hud_flush
    ldx HOLE
    lda course_par,x
    pha
    lda SHOTS
    jmp hud_right

; A = strokes. The caller pushed the par and jumped here; it is pulled
; below, before the final rts.
hud_right:
    sta HUD_VALUE
    jsr hud_begin
    lda #HUD_CLUB
    jsr hud_put
    lda #HUD_GAP
    jsr hud_put
    lda HUD_VALUE
    jsr hud_number
    lda #HUD_SLASH
    jsr hud_put
    pla
    jsr hud_number
    lda #HUD_RIGHT_END + 1    ; last advance includes one blank column
    sec
    sbc HUD_WIDTH
    sta HUD_X
; Draws the queued glyphs from HUD_X on.
hud_flush:
    ldx #0
hud_flush_next:
    cpx HUD_COUNT
    beq hud_done
    txa
    pha
    lda hud_text,x
    jsr hud_glyph
    pla
    tax
    inx
    bne hud_flush_next
hud_done:
    rts

hud_clear:
    ldx #HUD_CELLS * 8 - 1
    lda #0
hud_clear_byte:
    sta HUD_GLYPHS,x
    dex
    bpl hud_clear_byte
    rts

hud_begin:
    lda #0
    sta HUD_COUNT
    sta HUD_WIDTH
    rts

; A = font index, queued; HUD_WIDTH sums the advances. Preserves Y.
hud_put:
    ldx HUD_COUNT
    sta hud_text,x
    inc HUD_COUNT
    tax
    lda hud_font_advance,x
    clc
    adc HUD_WIDTH
    sta HUD_WIDTH
    rts

; A = 0..255, queued without leading zeros. Y = 1 once a digit is queued.
hud_number:
    sta HUD_VALUE
    ldy #0
    lda #100
    jsr hud_digit
    lda #10
    jsr hud_digit
    ldy #1                    ; the units digit always shows
    lda #1
hud_digit:
    sta HUD_DIVISOR
    ldx #0
hud_digit_count:
    lda HUD_VALUE
    cmp HUD_DIVISOR
    bcc hud_digit_queue
    sbc HUD_DIVISOR
    sta HUD_VALUE
    inx
    bne hud_digit_count
hud_digit_queue:
    txa
    bne hud_digit_shown
    cpy #0
    beq hud_done
hud_digit_shown:
    ldy #1
    jmp hud_put               ; digit value = font index

; A = font index, ORed into the HUD strip at pixel HUD_X, which then
; advances past it. Each font row is shifted across a cell boundary.
hud_glyph:
    tax
    lda hud_font_advance,x
    clc
    adc HUD_X
    pha
    txa
    asl
    asl
    sta HUD_ROW
    txa
    adc HUD_ROW               ; index * 5, carry clear
    sta HUD_ROW
    lda HUD_X
    and #7
    sta TEMP
    lda HUD_X
    and #$f8                  ; cell * 8, then glyph row 1
    ora #1
    tay
hud_glyph_row:
    lda #0
    sta HUD_SPILL
    ldx HUD_ROW
    lda hud_font,x
    ldx TEMP
    beq hud_glyph_store
hud_glyph_shift:
    lsr
    ror HUD_SPILL
    dex
    bne hud_glyph_shift
hud_glyph_store:
    ora HUD_GLYPHS,y
    sta HUD_GLYPHS,y
    lda HUD_SPILL
    ora HUD_GLYPHS + 8,y
    sta HUD_GLYPHS + 8,y
    inc HUD_ROW
    iny
    tya
    and #7
    cmp #6
    bne hud_glyph_row
    pla
    sta HUD_X
    rts

; Ten-cell frame centred in row 24: 1-pixel outline in glyph rows 1..5,
; edges and the 25/50/75 % ticks inside. The first 5 * POWER / 2 pixels
; (80 at full power) fill rows 1..5; the one partly filled cell uses
; the glyph rebuilt here.
draw_power:
    lda POWER
    lsr
    sta TEMP
    lda POWER
    asl
    adc TEMP                  ; POWER <= 32: carry clear
    sta TEMP
    ldx #0
power_bar_cell:
    lda TEMP
    cmp #8
    bcc power_bar_part
    sbc #8                    ; carry set
    sta TEMP
    lda #BAR_CHAR + BAR_FULL
    bne power_bar_store
power_bar_part:
    lda bar_empty,x
    ldy TEMP
    beq power_bar_store
    lda bar_masks,y
    ora bar_frame,x
    sta BAR_PARTIAL_GLYPH + 2
    sta BAR_PARTIAL_GLYPH + 3
    sta BAR_PARTIAL_GLYPH + 4
    lda #0
    sta TEMP
    lda #BAR_CHAR + BAR_PARTIAL
power_bar_store:
    sta SCREEN_BASE + 24 * 40 + BAR_COLUMN,x
    inx
    cpx #BAR_CELLS
    bne power_bar_cell
    rts

wall_offsets_x:
!byte $ff,$ff,0,1,1,1,0,$ff
wall_offsets_y:
!byte 0,$ff,$ff,$ff,0,1,1,1
; HUD font, glyph rows 1..5, pixels from bit 7. Advance = width + 1.
HUD_SLASH = 10
HUD_FLAG = 11
HUD_CLUB = 12
HUD_GAP = 13                  ; two more blank columns after an icon
HUD_PLAYER = 14
hud_font:
!byte %11100000,%10100000,%10100000,%10100000,%11100000 ; 0
!byte %01000000,%11000000,%01000000,%01000000,%11100000 ; 1
!byte %11100000,%00100000,%11100000,%10000000,%11100000 ; 2
!byte %11100000,%00100000,%01100000,%00100000,%11100000 ; 3
!byte %10100000,%10100000,%11100000,%00100000,%00100000 ; 4
!byte %11100000,%10000000,%11100000,%00100000,%11100000 ; 5
!byte %11100000,%10000000,%11100000,%10100000,%11100000 ; 6
!byte %11100000,%00100000,%00100000,%01000000,%01000000 ; 7
!byte %11100000,%10100000,%11100000,%10100000,%11100000 ; 8
!byte %11100000,%10100000,%11100000,%00100000,%11100000 ; 9
!byte %00100000,%00100000,%01000000,%10000000,%10000000 ; /
!byte %11000000,%11110000,%11000000,%10000000,%10000000 ; flag
!byte %00001000,%00010000,%00100000,%01000000,%11100000 ; club
!byte 0,0,0,0,0                                         ; gap
!byte %11100000,%10100000,%11100000,%10000000,%10000000 ; P
hud_font_advance:
!byte 4,4,4,4,4,4,4,4,4,4,4,5,6,2,4
!if * - hud_font_advance != HUD_PLAYER + 1 | hud_font_advance - hud_font != (HUD_PLAYER + 1) * 5 {
    !error "hud_font and hud_font_advance need HUD_PLAYER + 1 glyphs"
}
; Left strip cells 0..3, right strip cells 4..8 (screen columns 35..39).
HUD_CELLS = 9
HUD_LEFT_CELLS = 4
HUD_RIGHT_COLUMN = 40 - (HUD_CELLS - HUD_LEFT_CELLS)
HUD_LEFT_X = 1
HUD_RIGHT_END = HUD_CELLS * 8 - 1 ; last strip column, left blank like HUD_LEFT_X - 1
HUD_GLYPHS = CHARSET_BASE + HUD_CHAR * 8
!if >HUD_GLYPHS != >(HUD_GLYPHS + HUD_CELLS * 8 + 7) { !error "HUD strip must not cross a page" }
hud_text:                     ; flag, gap, 2 digits, gap, P, digit or club, gap, 3 digits, /, 2 digits
!fill 8
BAR_COLUMN = 15
BAR_CELLS = 10
; Glyph offsets from BAR_CHAR: empty frame with each inner pattern, full, partial.
BAR_FULL = 4
BAR_PARTIAL = 5
BAR_GLYPHS = 6
BAR_PARTIAL_GLYPH = CHARSET_BASE + (BAR_CHAR + BAR_PARTIAL) * 8
bar_glyph_rows:
!byte $00,$80,$08,$01,$ff,$00
; Rows 2..4 per cell: left edge, ticks at pixels 20, 40 and 60, right edge.
bar_frame:
!byte $80,$00,$08,$00,$00,$80,$00,$08,$00,$01
bar_empty:
!byte BAR_CHAR + 1, BAR_CHAR, BAR_CHAR + 2, BAR_CHAR, BAR_CHAR
!byte BAR_CHAR + 1, BAR_CHAR, BAR_CHAR + 2, BAR_CHAR, BAR_CHAR + 3
!if bar_empty - bar_frame != BAR_CELLS | * - bar_empty != BAR_CELLS {
    !error "bar_frame and bar_empty need BAR_CELLS entries"
}
bar_masks:                    ; index 1..7: filled pixels from the left
!byte $00,$80,$c0,$e0,$f0,$f8,$fc,$fe

; Inverted ball rows (the pixels to keep) for alignments 0..7: left byte
; column, then the right one. Row 1 leaves the highlight pixel set.
!macro ball_mask_row .shape, .shift, .right {
!if .right { !byte ((.shape << (8 - .shift)) & $ff) XOR $ff } else { !byte (.shape >> .shift) XOR $ff }
}
!macro ball_mask_rows .shift, .right {
    +ball_mask_row $70, .shift, .right
    +ball_mask_row $b8, .shift, .right
    +ball_mask_row $f8, .shift, .right
    +ball_mask_row $f8, .shift, .right
    +ball_mask_row $70, .shift, .right
}
ball_masks:
!for ball_shift, 0, 7 { +ball_mask_rows ball_shift, 0 }
!for ball_shift, 0, 7 { +ball_mask_rows ball_shift, 1 }

; The cup is a round 7-pixel hole: a dark rim with the shadow of its edge
; inside at the top left; the lit far wall at the bottom right stays floor.
; Plotting covers x > 255 too.
draw_cup:
    lda #6
    sta POINT_INDEX           ; hole row 0..6, dy = row - 3
cup_row:
    lda POINT_INDEX
    clc
    adc COURSE_CUP_Y
    sec
    sbc #3
    sta PIXEL_Y
    ldx POINT_INDEX
    lda cup_rows,x
    asl                       ; bits 6..0 are dx = -3..3
    sta GLYPH
    sec
    lda COURSE_CUP_X
    sbc #3
    sta PIXEL_X
    lda COURSE_CUP_X_HI
    sbc #0
    sta PIXEL_X + 1
cup_pixel:
    asl GLYPH
    bcc cup_pixel_next
    jsr plot_pixel
cup_pixel_next:
    inc PIXEL_X
    bne cup_pixel_more
    inc PIXEL_X + 1
cup_pixel_more:
    lda GLYPH
    bne cup_pixel
    dec POINT_INDEX
    bpl cup_row
    rts

cup_rows:
!byte %00011100
!byte %00111110
!byte %01111111
!byte %01111001
!byte %01110001
!byte %00110010
!byte %00011100
