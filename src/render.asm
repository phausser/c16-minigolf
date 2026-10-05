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
    ; Two row shapes, shifted once: M_A/M_B = left/right byte masks,
    ; index 0 = narrow top/bottom row, index 1 = full middle rows.
    lda #$70
    sta M_A
    lda #$f8
    sta M_A + 1
    lda #0
    sta M_B
    sta M_B + 1
    lda PIXEL_X
    and #7
    tax
    beq ball_masks_ready
ball_mask_shift:
    lsr M_A
    ror M_B
    lsr M_A + 1
    ror M_B + 1
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
    lda M_A,x
    beq ball_second_byte
    sta PIXEL_MASK
    jsr save_dynamic_byte
ball_second_byte:
    ldx GLYPH
    lda M_B,x
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
    lda #1
    sta TEXT_COLUMN
    lda #<hud_power
    sta TEXT_PTR
    lda #>hud_power
    sta TEXT_PTR + 1
    jmp draw_text

draw_power:
    lda #24
    sta TEXT_ROW
    lda #7
    sta TEXT_COLUMN
    ldx #0
    lda POWER
power_tens:
    cmp #10
    bcc power_digits
    sec
    sbc #10
    inx
    bne power_tens
power_digits:
    clc
    adc #'0'
    sta TEMP
    txa
    clc
    adc #'0'
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEMP
    jsr draw_glyph

    lda POWER
    clc
    adc #1
    lsr
    sta BAR_LEFT
    lda #15
    sta TEXT_COLUMN
power_bar:
    lda #' '
    ldx BAR_LEFT
    beq power_empty
    dec BAR_LEFT
    lda #'#'
power_empty:
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEXT_COLUMN
    cmp #31
    bne power_bar
    rts

draw_status:
    rts

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
    cmp #'#'
    bne glyph_rom
    lda #<power_glyph
    sta FONT_PTR
    lda #>power_glyph
    sta FONT_PTR + 1
    jmp glyph_address
glyph_rom:
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
hud_power:
!text "KRAFT 00/32  [                ]",0
power_glyph:
!byte 0,0,$7c,$7c,$7c,0,0,0

ball_row_shapes:
!byte 0,1,1,1,0
