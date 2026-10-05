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
    jsr punch_pixel
ball_second_byte:
    ldx GLYPH
    lda BALL_RIGHT,x
    beq ball_row_done
    sta PIXEL_MASK
    lda TEMP
    beq ball_row_done
    clc
    lda PIXEL_X
    pha
    adc #8
    sta PIXEL_X
    lda PIXEL_X + 1
    pha
    adc #0
    sta PIXEL_X + 1
    jsr punch_pixel
    pla
    sta PIXEL_X + 1
    pla
    sta PIXEL_X
ball_row_done:
    inc PIXEL_Y
    inc ROW_INDEX
    lda ROW_INDEX
    cmp #5
    bne ball_next
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

; Whole status row: "BAHN n" left, "PUNKTE n" right aligned.
draw_status:
    lda #0
    sta TEXT_COLUMN
    lda #<hud_hole
    ldx #>hud_hole
    jsr draw_text_at
    inc TEXT_COLUMN
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
; Round summary: total par left ("PAR nn "), "SUMME nnn" right.
draw_summary:
    lda #0
    sta TEXT_COLUMN
    lda #<hud_par_text
    ldx #>hud_par_text
    jsr draw_text_at
    lda #31
    sta TEXT_COLUMN
    lda #<hud_total
    ldx #>hud_total
    jsr draw_text_at
    lda TOTAL
    ldy #'0'
total_hundreds:
    cmp #100
    bcc total_tens
    sbc #100
    iny
    bne total_hundreds
total_tens:
    pha
    tya
    cmp #'0'
    bne total_digit
    lda #' '
total_digit:
    jsr draw_glyph
    inc TEXT_COLUMN
    pla
    jsr number_digits         ; a round has at least 18 strokes
    jmp number_pair

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

; Ten-cell bar centred in row 24. Each cell is one of nine glyphs:
; row 3 is always a full line, rows 1, 2, 4 and 5 grow from the left
; by 5 * POWER / 2 pixels (80 at full power).
draw_power:
    lda #24
    jsr class_row_pointer
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COURSE_PTR + 1
    lda POWER
    lsr
    sta TEMP
    lda POWER
    asl
    adc TEMP                  ; POWER <= 32: carry clear
    sta TEMP
    ldy #BAR_COLUMN
power_bar_cell:
    lda TEMP
    cmp #8
    bcc power_bar_width
    lda #8
power_bar_width:
    clc
    adc #BAR_CHAR
    sta (COURSE_PTR),y
    lda TEMP
    sec
    sbc #8
    bcs power_bar_next
    lda #0
power_bar_next:
    sta TEMP
    iny
    cpy #BAR_COLUMN + BAR_CELLS
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

; A = ASCII 32..93. The screen code selects the ROM glyph copied at startup.
draw_glyph:
    cmp #64
    bcc glyph_code
    and #63
glyph_code:
    pha
    lda TEXT_ROW
    jsr class_row_pointer
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COURSE_PTR + 1
    pla
    ldy TEXT_COLUMN
    sta (COURSE_PTR),y
    rts

wall_offsets_x:
!byte $ff,$ff,0,1,1,1,0,$ff
wall_offsets_y:
!byte 0,$ff,$ff,$ff,0,1,1,1
hud_hole:
!text "BAHN",0
hud_shots:
!text " PUNKTE ",0
hud_total:
!text "SUMME ",0
BAR_COLUMN = 15
BAR_CELLS = 10
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
