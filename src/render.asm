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
    ; Three row shapes, shifted once: BALL_LEFT/BALL_RIGHT byte masks,
    ; 0 = narrow top/bottom row, 1 = full row, 2 = row with the highlight
    ; pixel left clear so the floor shines through top left.
    ldx #2
ball_mask_init:
    lda ball_shapes,x
    sta BALL_LEFT,x
    lda #0
    sta BALL_RIGHT,x
    dex
    bpl ball_mask_init
    lda PIXEL_X
    and #7
    tax
    beq ball_masks_ready
ball_mask_shift:
    lsr BALL_LEFT
    ror BALL_RIGHT
    lsr BALL_LEFT + 1
    ror BALL_RIGHT + 1
    lsr BALL_LEFT + 2
    ror BALL_RIGHT + 2
    dex
    bne ball_mask_shift
ball_masks_ready:
    ; The right byte is off screen from x = 312.
    lda PIXEL_X + 1
    beq ball_right_ok
    lda PIXEL_X
    cmp #56
    lda #0
    bcs ball_right_flag
ball_right_ok:
    lda #1
ball_right_flag:
    sta TEMP
    jsr point_pixel
    lda #0
    sta ROW_INDEX
ball_next:
    lda PIXEL_Y
    cmp #8
    bcc ball_row_done
    cmp #168
    bcs ball_row_done
    ldx ROW_INDEX
    lda ball_row_shapes,x
    sta GLYPH
    tax
    lda BALL_LEFT,x
    beq ball_second_byte
    sta PIXEL_MASK
    jsr save_dynamic_byte
ball_second_byte:
    ldx GLYPH
    lda BALL_RIGHT,x
    beq ball_row_done
    sta PIXEL_MASK
    lda TEMP
    beq ball_row_done
    ldy #8                    ; next cell to the right
    jsr save_dynamic_byte
    ldy #0
ball_row_done:
    inc PIXEL_Y
    ; Next scanline: +1 inside a cell row (never carries), else +313.
    lda PIXEL_Y
    and #7
    beq ball_next_cell_row
    inc BITMAP_PTR
    bne ball_row_advanced
ball_next_cell_row:
    clc
    lda BITMAP_PTR
    adc #<313
    sta BITMAP_PTR
    lda BITMAP_PTR + 1
    adc #>313
    sta BITMAP_PTR + 1
ball_row_advanced:
    inc ROW_INDEX
    lda ROW_INDEX
    cmp #5
    bne ball_next
    lda PAUSED
    bne aim_done
    lda ROLLING
    bne aim_done

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
    lda #0
    sta POINT_INDEX
aim_next:
    jsr advance_aim
    ; Skip the first two points inside/next to the ball.
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #3
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
    lda PIXEL_Y
    cmp #168
    bcs aim_skip_pixel
    jsr plot_dynamic
aim_skip_pixel:
    lda POINT_INDEX
    cmp #10
    bne aim_next
aim_done:
    rts

lookup_aim_step:
    jsr cosine_unit
    +copy16 M_A, M_B
    asl M_A
    rol M_A + 1
    +add16 M_A, M_B, M_A
    clc
    lda M_A
    adc #8
    sta M_A
    lda M_A + 1
    adc #0
    sta M_A + 1
    ldx #4
aim_unit_scale:
    lda M_A + 1
    asl
    ror M_A + 1
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

draw_static_hud:
    lda #24
    sta TEXT_ROW
    lda #0
    sta TEXT_COLUMN
    lda #<hud_hole
    ldx #>hud_hole
    jsr draw_text_at
draw_status:
    lda #5
    sta TEXT_COLUMN
    ldx HOLE
    inx
    txa
    jsr draw_number
    ; "PUNKTE n" ends in column 39: one digit gets a leading blank.
    lda #31
    sta TEXT_COLUMN
    lda SHOTS
    cmp #10
    lda #<hud_shots
    bcc status_shots
    lda #<(hud_shots + 1)
status_shots:
    ldx #>hud_shots
    jsr draw_text_at
    lda SHOTS
    jsr number_digits
    cpx #'0'
    beq number_single_digit
    bne number_pair
; A = 0..99, left aligned in two cells from TEXT_COLUMN.
draw_number:
    jsr number_digits
    cpx #'0'
    beq number_single
number_pair:
    sta TEMP
    txa
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEMP
    jmp draw_glyph
number_single:
    jsr draw_glyph
    inc TEXT_COLUMN
    lda #' '
number_single_digit:
    jmp draw_glyph
; A = 0..99 -> X = tens digit, A = units digit (ASCII).
number_digits:
    ldx #'0'
number_tens:
    cmp #10
    bcc number_units
    sbc #10
    inx
    bne number_tens
number_units:
    ora #'0'
    rts

; Ten-cell bar centred in row 24: glyph row 3 is a thin line; the first
; 5 * POWER / 2 pixels (80 at full power) grow to rows 1..5.
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
    ldy TEMP
    cpy #8
    bcc power_bar_mask
    ldy #8
power_bar_mask:
    lda bar_masks,y
    sta HUD_BAR + 1,x
    sta HUD_BAR + 2,x
    sta HUD_BAR + 4,x
    sta HUD_BAR + 5,x
    lda #$ff
    sta HUD_BAR + 3,x
    lda TEMP
    sec
    sbc #8
    bcs power_bar_next
    lda #0
power_bar_next:
    sta TEMP
    txa
    clc
    adc #8
    tax
    cpx #BAR_CELLS * 8
    bne power_bar_cell
    rts

draw_text_at:
    sta TEXT_PTR
    stx TEXT_PTR + 1
draw_text:
    ldy #0
    lda (TEXT_PTR),y
    beq text_done
    jsr draw_glyph
    inc TEXT_COLUMN
    inc TEXT_PTR
    bne draw_text
    inc TEXT_PTR + 1
    jmp draw_text
text_done:
    rts

; A = ASCII 32..93; aligned bitmap glyphs overwrite only their own cell.
draw_glyph:
    cmp #64
    bcc glyph_code
    and #63
glyph_code:
    sta FONT_PTR
    lda #0
    sta FONT_PTR + 1
    ldx #3
glyph_offset:
    asl FONT_PTR
    rol FONT_PTR + 1
    dex
    bne glyph_offset
    clc
    lda FONT_PTR
    adc #<$d000
    sta FONT_PTR
    lda FONT_PTR + 1
    adc #>$d000
    sta FONT_PTR + 1
glyph_address:
    ldx TEXT_ROW
    lda bitmap_rows_lo,x
    sta BITMAP_PTR
    lda bitmap_rows_hi,x
    sta BITMAP_PTR + 1
    lda TEXT_COLUMN
    ldx #0
    asl
    asl
    asl
    bcc glyph_column
    inx
glyph_column:
    clc
    adc BITMAP_PTR
    sta BITMAP_PTR
    txa
    adc BITMAP_PTR + 1
    sta BITMAP_PTR + 1
    ldy #0
glyph_copy:
    lda (FONT_PTR),y
    sta (BITMAP_PTR),y
    iny
    cpy #8
    bne glyph_copy
    rts

wall_offsets_x:
!byte $ff,$ff,0,1,1,1,0,$ff
wall_offsets_y:
!byte 0,$ff,$ff,$ff,0,1,1,1
hud_hole:
!text "BAHN",0
hud_shots:
!text " PUNKTE ",0
BAR_COLUMN = 15
BAR_CELLS = 10
HUD_BAR = $3e00 + BAR_COLUMN * 8
bar_masks:
!byte $00,$80,$c0,$e0,$f0,$f8,$fc,$fe,$ff

ball_row_shapes:
!byte 0,2,1,1,0
ball_shapes:
!byte $70,$f8,$b8

; The cup is a filled round 7-pixel disc; plotting covers x > 255 too.
draw_cup:
    lda #6
    sta POINT_INDEX           ; disc row 0..6, dy = row - 3
cup_row:
    lda POINT_INDEX
    clc
    adc COURSE_CUP_Y
    sec
    sbc #3
    sta PIXEL_Y
    ldx POINT_INDEX
    lda cup_half_widths,x
    sta TEMP
    asl
    sta GLYPH
    inc GLYPH                 ; 2 * half width + 1 pixels
    sec
    lda COURSE_CUP_X
    sbc TEMP
    sta PIXEL_X
    lda COURSE_CUP_X_HI
    sbc #0
    sta PIXEL_X + 1
cup_pixel:
    jsr plot_pixel
    inc PIXEL_X
    bne cup_pixel_next
    inc PIXEL_X + 1
cup_pixel_next:
    dec GLYPH
    bne cup_pixel
    dec POINT_INDEX
    bpl cup_row
    rts

cup_half_widths:
!byte 1,2,3,3,3,2,1
