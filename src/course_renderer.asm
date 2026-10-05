; Even/odd fill: 0 = gray floor, 1 = foreground ink or solid geometry.
; Whole floor cells use white ink; cells containing solid pixels use black.
; Requires a freshly initialized $ff-filled playfield. Half-open y intervals
; count shared vertices once, and obstacles follow the same parity rule.
draw_course:
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
    jsr initialise_course_colors
    ; Cup ring is static and tests plotting at x > 255.
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
CLASS_FLOOR = 0                 ; only floor pixels
CLASS_EDGE = 1                  ; inner 45-degree edge: floor and solid
CLASS_SOLID = 2                 ; far from the course: green checker
CLASS_FRAME = 3                 ; solid cell touching floor: black frame
CLASS_OUTER = 4                 ; outer 45-degree frame edge: black/green
; COURSE_PTR addresses the class of cell i - 41: neighbours of i are at
; Y = 0,1,2 / 40,(41),42 / 80,81,82.
CLASS_SELF = 41

; Colors depend on the static geometry and are set before cup/ball/aim.
; Rows 0 and 21..23 hide data with equal colors, here the green checker.
initialise_course_colors:
    lda #CLASS_SOLID
    ldx #240
course_class_clear:
    sta COLOR_BASE - 1,x
    sta COLOR_BASE + 239,x
    sta COLOR_BASE + 479,x
    sta COLOR_BASE + 719,x
    dex
    bne course_class_clear
    ; Floor, inner edge or solid from the 8 bitmap bytes of rows 1..20.
    jsr course_cells_begin
course_classify:
    ldy #7
    lda (BITMAP_PTR),y
    sta TEMP                  ; AND of all bytes
    sta GLYPH                 ; OR of all bytes
course_classify_byte:
    dey
    bmi course_classify_ready
    lda (BITMAP_PTR),y
    tax
    ora GLYPH
    sta GLYPH
    txa
    and TEMP
    sta TEMP
    jmp course_classify_byte
course_classify_ready:
    ldx #CLASS_FLOOR
    lda GLYPH
    beq course_classify_store
    inx
    lda TEMP
    cmp #$ff
    bne course_classify_store
    inx
course_classify_store:
    txa
    ldy #CLASS_SELF
    sta (COURSE_PTR),y
    jsr course_cells_next
    bne course_classify
    ; Inner edges put the same pattern one cell further out, horizontally
    ; and vertically, as the outer frame edge. Solid cells next to floor
    ; become frame.
    jsr course_cells_begin
course_shape:
    ldy #CLASS_SELF
    lda (COURSE_PTR),y
    cmp #CLASS_EDGE
    bne course_shape_solid
    ldy #4                    ; middle row: rightmost pixel solid?
    lda (BITMAP_PTR),y
    lsr
    ldy #CLASS_SELF + 1
    lda #8
    ldx #0
    bcs course_shape_horizontal
    ldy #CLASS_SELF - 1
    lda #<-8
    ldx #>-8
course_shape_horizontal:
    jsr course_outer_cell
    ldy #0                    ; top row: centre pixel solid?
    lda (BITMAP_PTR),y
    and #$08
    beq course_shape_down
    ldy #CLASS_SELF - 40
    lda #<-320
    ldx #>-320
    bne course_shape_vertical
course_shape_down:
    ldy #CLASS_SELF + 40
    lda #<320
    ldx #>320
course_shape_vertical:
    jsr course_outer_cell
    jmp course_shape_next
course_shape_solid:
    cmp #CLASS_SOLID
    bne course_shape_next
    ldx #7
course_shape_neighbour:
    ldy course_neighbours,x
    lda (COURSE_PTR),y
    beq course_shape_frame    ; CLASS_FLOOR
    dex
    bpl course_shape_neighbour
    bmi course_shape_next
course_shape_frame:
    lda #CLASS_FRAME
    ldy #CLASS_SELF
    sta (COURSE_PTR),y
course_shape_next:
    jsr course_cells_next
    bne course_shape
    ; Attributes for rows 0..23 from class and checker parity.
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

; Y = class offset of the target, A/X = bitmap distance to it. Converts a
; solid or frame cell into an outer edge with this edge cell's pattern.
course_outer_cell:
    sta COPY_TARGET
    stx COPY_TARGET + 1
    lda (COURSE_PTR),y
    cmp #CLASS_SOLID
    bcc course_outer_done
    cmp #CLASS_OUTER
    bcs course_outer_done
    lda #CLASS_OUTER
    sta (COURSE_PTR),y
    clc
    lda BITMAP_PTR
    adc COPY_TARGET
    sta COPY_TARGET
    lda BITMAP_PTR + 1
    adc COPY_TARGET + 1
    sta COPY_TARGET + 1
    ldy #7
course_outer_copy:
    lda (BITMAP_PTR),y
    sta (COPY_TARGET),y
    dey
    bpl course_outer_copy
course_outer_done:
    rts

; Walk cells 40..839 (rows 1..20): BITMAP_PTR = cell bitmap,
; COURSE_PTR = class of cell - 41. Z clear while cells remain.
course_cells_begin:
    lda #<$2140
    sta BITMAP_PTR
    lda #>$2140
    sta BITMAP_PTR + 1
    lda #<(COLOR_BASE + 40 - CLASS_SELF)
    sta COURSE_PTR
    lda #>(COLOR_BASE + 40 - CLASS_SELF)
    sta COURSE_PTR + 1
    rts
course_cells_next:
    clc
    lda BITMAP_PTR
    adc #8
    sta BITMAP_PTR
    bcc course_cells_bitmap
    inc BITMAP_PTR + 1
course_cells_bitmap:
    inc COURSE_PTR
    bne course_cells_class
    inc COURSE_PTR + 1
course_cells_class:
    lda BITMAP_PTR + 1
    cmp #>$3a40
    bne course_cells_more
    lda BITMAP_PTR
    cmp #<$3a40
course_cells_more:
    rts

course_neighbours:
!byte 0,1,2,40,42,80,81,82
; Index = class * 2 + checker parity.
course_luminance:
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_luminance CHECKER_COLOR_EVEN, CHECKER_COLOR_EVEN
    +attribute_luminance CHECKER_COLOR_ODD, CHECKER_COLOR_ODD
    +attribute_luminance COURSE_FRAME_COLOR, COURSE_FRAME_COLOR
    +attribute_luminance COURSE_FRAME_COLOR, COURSE_FRAME_COLOR
    +attribute_luminance CHECKER_COLOR_EVEN, COURSE_FRAME_COLOR
    +attribute_luminance CHECKER_COLOR_ODD, COURSE_FRAME_COLOR
course_color:
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color COURSE_MARKER_COLOR, COURSE_SURFACE_COLOR
    +attribute_color CHECKER_COLOR_EVEN, CHECKER_COLOR_EVEN
    +attribute_color CHECKER_COLOR_ODD, CHECKER_COLOR_ODD
    +attribute_color COURSE_FRAME_COLOR, COURSE_FRAME_COLOR
    +attribute_color COURSE_FRAME_COLOR, COURSE_FRAME_COLOR
    +attribute_color CHECKER_COLOR_EVEN, COURSE_FRAME_COLOR
    +attribute_color CHECKER_COLOR_ODD, COURSE_FRAME_COLOR
