; Even/odd scanline fill. Bitmap 1 = solid black, 0 = playable gray.
; Each nonhorizontal edge toggles the pixels to its right, with a half-open
; y interval so shared vertices are counted exactly once. Obstacles use the
; same parity rule. Requires a freshly initialized solid-black playfield.
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
    jsr shade_course
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

; Shade from solid top-left samples in this cell or its top/left neighbor.
; Sampling on the cell grid keeps the shadow in aligned 8x8 blocks.
; Row 0 lookup data is never sampled as geometry: row 1 uses black instead.
shade_course:
    lda #<$1828
    sta COURSE_PTR
    lda #>$1828
    sta COURSE_PTR + 1
    lda #8
    sta PIXEL_Y
shade_row:
    lda #0
    sta PIXEL_X
    sta PIXEL_X + 1
shade_cell:
    jsr point_pixel
    lda (BITMAP_PTR),y
    bmi shade_dark
    lda PIXEL_Y
    cmp #8
    beq shade_dark
    sec
    lda BITMAP_PTR
    sbc #<320
    sta COPY_SOURCE
    lda BITMAP_PTR + 1
    sbc #>320
    sta COPY_SOURCE + 1
    lda (COPY_SOURCE),y
    bmi shade_dark
    lda PIXEL_X
    ora PIXEL_X + 1
    beq shade_dark
    sec
    lda BITMAP_PTR
    sbc #8
    sta COPY_SOURCE
    lda BITMAP_PTR + 1
    sbc #0
    sta COPY_SOURCE + 1
    lda (COPY_SOURCE),y
    bmi shade_dark
    lda #(COURSE_SURFACE_COLOR & $70) + ((COURSE_SOLID_COLOR & $70) >> 4)
    bne shade_store
shade_dark:
    lda #(COURSE_SHADOW_COLOR & $70) + ((COURSE_SOLID_COLOR & $70) >> 4)
shade_store:
    ldy #0
    sta (COURSE_PTR),y
    inc COURSE_PTR
    bne shade_attribute_ready
    inc COURSE_PTR + 1
shade_attribute_ready:
    clc
    lda PIXEL_X
    adc #8
    sta PIXEL_X
    bcc shade_x_ready
    inc PIXEL_X + 1
shade_x_ready:
    lda PIXEL_X + 1
    beq shade_cell
    lda PIXEL_X
    cmp #64
    bcc shade_cell
    clc
    lda PIXEL_Y
    adc #8
    sta PIXEL_Y
    cmp #168
    bcc shade_row
    rts
