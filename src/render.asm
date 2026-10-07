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

; Status row 24 in the font, one glyph per cell: flag and hole number on
; the left, with several players the player sign and number beside them;
; club and "strokes/par" on the right. Numbers come first: print_number
; blanks the cell left of them, where the signs go afterwards.
STATUS_ROW = SCREEN_BASE + 24 * 40
draw_status:
    lda #<STATUS_ROW
    sta COPY_TARGET
    lda #>STATUS_ROW
    sta COPY_TARGET + 1
    ldx HOLE
    inx
    txa
    ldy #2
    jsr print_number
    lda #FLAG_CHAR
    sta STATUS_ROW
    ldx player_count
    dex
    beq status_right
    ldx player
    inx
    txa
    ldy #5
    jsr print_number
    lda #PLAYER_CHAR
    sta STATUS_ROW + 4
status_right:
    ldx HOLE
    lda course_par,x
    ldy #38
    jsr print_number
    lda SHOTS
    ldy #36
    jsr print_number
    lda #SLASH_CHAR
    sta STATUS_ROW + 37
    lda #CLUB_CHAR
    sta STATUS_ROW + 33
    rts

; A = 0..255, written leftwards from (COPY_TARGET),Y without leading
; zeros, then one blank cell. Clobbers X.
print_number:
    ldx #$ff
    sec
print_tens:
    inx
    sbc #10
    bcs print_tens
    adc #10 + DIGIT_CHAR      ; carry clear: the remainder's glyph
    sta (COPY_TARGET),y
    dey
    txa
    bne print_number
    lda #BLANK_CHAR
    sta (COPY_TARGET),y
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
