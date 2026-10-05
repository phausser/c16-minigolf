; Static course picture. The playfield starts clear. An even/odd fill
; sets the floor pixels, which are then grown by 4 pixels in x and y
; (square distance). A second, identical XOR fill clears the floor again:
; the remaining set pixels are the black frame, 4 px at straight walls and
; 8 px horizontally (~5.7 px across) at 45-degree walls. Half-open y
; intervals count shared vertices once; obstacles follow the parity rule.
draw_course:
    jsr fill_course
    jsr classify_course_cells
    jsr dilate_course
    jsr fill_course
    jsr colour_course_cells
    jmp draw_cup

fill_course:
    lda #0
    sta SEGMENTS_LEFT         ; byte offset of the current segment
fill_edge:
    ; Every non-horizontal wall is one fill edge, walked from its top end.
    ldx SEGMENTS_LEFT
    txa
    tay
    lda course_segments + 3,x
    cmp course_segments + 1,x
    bne fill_sloped
    jmp fill_next_edge
fill_sloped:
    bcc fill_upward
    iny                       ; top x, bottom y+2
    iny
    bne fill_ordered
fill_upward:
    inx
    inx
fill_ordered:
    lda course_segments,x
    asl
    sta LINE_X
    lda #0
    rol
    sta LINE_X + 1
    lda course_segments + 1,x
    asl
    sta LINE_Y
    lda course_segments + 1,y
    sec
    sbc course_segments + 1,x
    asl
    sta LINE_LEFT
    lda course_segments,y
    sec
    sbc course_segments,x
    beq fill_slope            ; vertical
    lda #1
    bcs fill_slope
    lda #$ff
fill_slope:
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
fill_next_edge:
    lda SEGMENTS_LEFT
    clc
    adc #5
    sta SEGMENTS_LEFT
    cmp SEGMENT_BYTES
    bcs fill_done
    jmp fill_edge
fill_done:
    rts

; Cup ring is static and tests plotting at x > 255.
draw_cup:
    lda #0
    sta POINT_INDEX
cup_next:
    ldx POINT_INDEX
    lda cup_dx,x
    clc
    adc COURSE_CUP_X
    sta PIXEL_X
    lda cup_dx,x
    bpl cup_positive_x
    lda #$ff
    bne cup_x_sign
cup_positive_x:
    lda #0
cup_x_sign:
    adc COURSE_CUP_X_HI
    sta PIXEL_X + 1
    lda cup_dy,x
    clc
    adc COURSE_CUP_Y
    sta PIXEL_Y
    jsr plot_pixel
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #CUP_POINTS
    bne cup_next
    rts

; Cell classes, kept in the color matrix while the display is off.
CLASS_FLOOR = 0                 ; cell contains floor: gray, black edges
CLASS_SOLID = 1                 ; black frame pixels on the green checker
CLASS_HIDDEN = 2                ; rows 0, 21..23: equal checker colors

; Before dilation the bitmap is the floor mask: any set bit means floor.
; Rows 0 and 21..23 keep CLASS_HIDDEN.
classify_course_cells:
    lda #CLASS_HIDDEN
    ldx #240
course_class_clear:
    sta COLOR_BASE - 1,x
    sta COLOR_BASE + 239,x
    sta COLOR_BASE + 479,x
    sta COLOR_BASE + 719,x
    dex
    bne course_class_clear
    lda #<$2140
    sta BITMAP_PTR
    lda #>$2140
    sta BITMAP_PTR + 1
    lda #<(COLOR_BASE + 40)
    sta COURSE_PTR
    lda #>(COLOR_BASE + 40)
    sta COURSE_PTR + 1
course_classify:
    lda #0
    ldy #7
course_classify_byte:
    ora (BITMAP_PTR),y
    dey
    bpl course_classify_byte
    cmp #1                    ; C clear only for an empty cell
    lda #CLASS_FLOOR
    bcs course_classify_store
    lda #CLASS_SOLID
course_classify_store:
    ldy #0
    sta (COURSE_PTR),y
    inc COURSE_PTR
    bne course_classify_class
    inc COURSE_PTR + 1
course_classify_class:
    clc
    lda BITMAP_PTR
    adc #8
    sta BITMAP_PTR
    bcc course_classify_more
    inc BITMAP_PTR + 1
course_classify_more:
    cmp #<$3a40
    bne course_classify
    lda BITMAP_PTR + 1
    cmp #>$3a40
    bne course_classify
    rts

; Attributes for rows 0..23 from class and checker parity.
colour_course_cells:
    lda #<COLOR_BASE
    sta COURSE_PTR
    sta COPY_SOURCE
    lda #>COLOR_BASE
    sta COURSE_PTR + 1
    lda #>LUMINANCE_BASE
    sta COPY_SOURCE + 1
    ldy #0
    sty ROW_INDEX             ; checker parity
    lda #40
    sta TEXT_COLUMN
course_attribute:
    lda (COURSE_PTR),y
    asl
    ora ROW_INDEX
    tax
    lda course_luminance,x
    sta (COPY_SOURCE),y
    lda course_color,x
    sta (COURSE_PTR),y
    lda ROW_INDEX
    eor #1
    dec TEXT_COLUMN
    bne course_attribute_parity
    eor #1                    ; 40 cells per row: next row starts flipped
    ldx #40
    stx TEXT_COLUMN
course_attribute_parity:
    sta ROW_INDEX
    inc COPY_SOURCE
    inc COURSE_PTR
    bne course_attribute_ready
    inc COPY_SOURCE + 1
    inc COURSE_PTR + 1
course_attribute_ready:
    lda COURSE_PTR
    cmp #<(COLOR_BASE + 960)
    bne course_attribute
    lda COURSE_PTR + 1
    cmp #>(COLOR_BASE + 960)
    bne course_attribute
    rts

; Index = class * 2 + checker parity.
course_luminance:
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance COURSE_FRAME_COLOR, CHECKER_COLOR_EVEN
    +attribute_luminance COURSE_FRAME_COLOR, CHECKER_COLOR_ODD
    +attribute_luminance CHECKER_COLOR_EVEN, CHECKER_COLOR_EVEN
    +attribute_luminance CHECKER_COLOR_ODD, CHECKER_COLOR_ODD
course_color:
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color COURSE_FRAME_COLOR, CHECKER_COLOR_EVEN
    +attribute_color COURSE_FRAME_COLOR, CHECKER_COLOR_ODD
    +attribute_color CHECKER_COLOR_EVEN, CHECKER_COLOR_EVEN
    +attribute_color CHECKER_COLOR_ODD, CHECKER_COLOR_ODD
