; Even/odd fill: 0 = gray floor, 1 = foreground ink or solid geometry.
; Whole floor cells use white ink; cells containing solid pixels use black.
; Requires a freshly initialized $ff-filled playfield. Half-open y intervals
; count shared vertices once, and obstacles follow the same parity rule.
draw_course:
    lda #<course_fill_edges
    sta COURSE_PTR
    lda #>course_fill_edges
    sta COURSE_PTR + 1
    lda #COURSE_FILL_COUNT
    sta SEGMENTS_LEFT
fill_edge:
    ldy #0
    lda (COURSE_PTR),y
    asl
    sta LINE_X
    lda #0
    rol
    sta LINE_X + 1
    iny
    lda (COURSE_PTR),y
    sta LINE_Y
    iny
    lda (COURSE_PTR),y
    sta LINE_LEFT
    iny
    lda (COURSE_PTR),y
    sta LINE_X_STEP
fill_scanline:
    lda LINE_X
    sta PIXEL_X
    lda LINE_X + 1
    sta PIXEL_X + 1
    lda LINE_Y
    sta PIXEL_Y
    jsr point_pixel
    lda PIXEL_MASK
    asl
    sec
    sbc #1                  ; first byte: bits from the crossing to the right
    sta PIXEL_MASK
    lda PIXEL_X + 1
    lsr
    lda PIXEL_X
    ror
    lsr
    lsr
    sta TEMP
    lda #39
    sec
    sbc TEMP
    sta GLYPH_BITS
fill_byte:
    lda (BITMAP_PTR),y
    eor PIXEL_MASK
    sta (BITMAP_PTR),y
    clc
    lda BITMAP_PTR
    adc #8
    sta BITMAP_PTR
    bcc fill_byte_ready
    inc BITMAP_PTR + 1
fill_byte_ready:
    lda #$ff
    sta PIXEL_MASK
    dec GLYPH_BITS
    bne fill_byte
    clc
    lda LINE_X
    adc LINE_X_STEP
    sta LINE_X
    lda #0
    bit LINE_X_STEP
    bpl fill_step_positive
    lda #$ff
fill_step_positive:
    adc LINE_X + 1
    sta LINE_X + 1
    inc LINE_Y
    dec LINE_LEFT
    bne fill_scanline
    clc
    lda COURSE_PTR
    adc #4
    sta COURSE_PTR
    bcc fill_pointer_ready
    inc COURSE_PTR + 1
fill_pointer_ready:
    dec SEGMENTS_LEFT
    beq fill_done
    jmp fill_edge
fill_done:
    jsr initialise_course_colors
    ; Cup ring is static and tests plotting at x > 255.
    lda #0
    sta POINT_INDEX
cup_next:
    ldx POINT_INDEX
    lda cup_dx,x
    clc
    adc #<CUP_X
    sta PIXEL_X
    lda cup_dx,x
    bpl cup_positive_x
    lda #$ff
    bne cup_x_sign
cup_positive_x:
    lda #0
cup_x_sign:
    adc #>CUP_X
    sta PIXEL_X + 1
    lda cup_dy,x
    clc
    adc #CUP_Y
    sta PIXEL_Y
    jsr plot_pixel
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #CUP_POINTS
    bne cup_next
    rts

; Choose the palette from static geometry before drawing cup/ball/aim.
; Scan only rows 1..20; lookup, renderer and HUD code stay hidden and intact.
initialise_course_colors:
    lda #<$2140
    sta BITMAP_PTR
    lda #>$2140
    sta BITMAP_PTR + 1
    lda #<(LUMINANCE_BASE + 40)
    sta COURSE_PTR
    lda #>(LUMINANCE_BASE + 40)
    sta COURSE_PTR + 1
course_color_cell:
    lda #0
    ldy #7
course_color_scan:
    ora (BITMAP_PTR),y
    dey
    bpl course_color_scan
    cmp #0                  ; DEY changed flags; test the accumulated bitmap
    bne course_color_boundary
    lda #(COURSE_SURFACE_COLOR & $70) + ((COURSE_INK_COLOR & $70) >> 4)
    ldx #((COURSE_INK_COLOR & $0f) << 4) + (COURSE_SURFACE_COLOR & $0f)
    jmp course_color_store
course_color_boundary:
    lda #(COURSE_SURFACE_COLOR & $70) + ((COURSE_SOLID_COLOR & $70) >> 4)
    ldx #((COURSE_SOLID_COLOR & $0f) << 4) + (COURSE_SURFACE_COLOR & $0f)
course_color_store:
    ldy #0
    sta (COURSE_PTR),y
    lda COURSE_PTR + 1
    clc
    adc #4
    sta COPY_TARGET + 1
    lda COURSE_PTR
    sta COPY_TARGET
    txa
    sta (COPY_TARGET),y
    clc
    lda BITMAP_PTR
    adc #8
    sta BITMAP_PTR
    bcc course_color_next
    inc BITMAP_PTR + 1
course_color_next:
    inc COURSE_PTR
    bne course_color_end
    inc COURSE_PTR + 1
course_color_end:
    lda BITMAP_PTR + 1
    cmp #>$3a40
    bne course_color_cell
    lda BITMAP_PTR
    cmp #<$3a40
    bne course_color_cell
    rts
