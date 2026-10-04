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

; Uniform course palette. Hidden bitmap rows and HUD are excluded.
initialise_course_colors:
    ldx #0
video_course_colors:
    lda #(COURSE_SURFACE_COLOR & $70) + ((COURSE_SOLID_COLOR & $70) >> 4)
    sta LUMINANCE_BASE + 40,x
    sta LUMINANCE_BASE + 296,x
    sta LUMINANCE_BASE + 552,x
    lda #((COURSE_SOLID_COLOR & $0f) << 4) + (COURSE_SURFACE_COLOR & $0f)
    sta COLOR_BASE + 40,x
    sta COLOR_BASE + 296,x
    sta COLOR_BASE + 552,x
    inx
    bne video_course_colors
    ldx #31
video_course_color_tail:
    lda #(COURSE_SURFACE_COLOR & $70) + ((COURSE_SOLID_COLOR & $70) >> 4)
    sta LUMINANCE_BASE + 808,x
    lda #((COURSE_SOLID_COLOR & $0f) << 4) + (COURSE_SURFACE_COLOR & $0f)
    sta COLOR_BASE + 808,x
    dex
    bpl video_course_color_tail
    rts
