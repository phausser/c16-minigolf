; Static course picture, drawn into a three-row scratch bitmap and then stored
; as characters. The fill, classification and frame shaping are the bitmap
; renderer: set bits are black. Each finished cell is inverted, so set bits
; become the cell colour and clear bits the global black background.
; Water is classified before shaping and counts as floor, so walls beside
; it keep their frame while the water cell itself stays a plain disc-free
; floor cell. Rows 0 and 21..23 are a solid green checker.
FRAME_WIDTH = 6
draw_course:
    lda #0
    sta pattern_count
    sta pattern_overflow
    jsr classify_course_cells
    jsr mark_water
    lda #0
    sta window_row
    jsr fill_window_row
    lda #1
    jsr fill_window_row
    lda #2
    jsr fill_window_row
    lda #1
    sta shape_row
draw_shape_loop:
    lda shape_row
    jsr shape_one_row
    lda shape_row
    cmp #1
    beq draw_shape_advance
    sec
    sbc #1
    jsr emit_playfield_row
draw_shape_advance:
    lda shape_row
    cmp #20
    beq draw_shape_done
    jsr slide_window
    inc shape_row
    bne draw_shape_loop
draw_shape_done:
    lda #20
    jsr emit_playfield_row
    lda #0
    jsr emit_hidden_row
    ldx #21
draw_hidden:
    txa
    pha                       ; emit clobbers X (ink index, row pointer)
    jsr emit_hidden_row
    pla
    tax
    inx
    cpx #24
    bne draw_hidden
    lda pattern_overflow
    beq draw_course_done
    lda #$22                  ; red border: the 64-character budget overflowed
    sta TED_BORDER
draw_course_done:
    rts

; Drop the oldest scratch row, keep the two just shaped, and fill the next.
slide_window:
    ; slot 1 -> slot 0, then slot 2 -> slot 1. Copying as one 640-byte
    ; block would make the second half's destination overlap its source.
    lda #<(SCRATCH_BASE + 320)
    sta COPY_SOURCE
    lda #>(SCRATCH_BASE + 320)
    sta COPY_SOURCE + 1
    lda #<SCRATCH_BASE
    sta COPY_TARGET
    lda #>SCRATCH_BASE
    sta COPY_TARGET + 1
    jsr copy_320
    lda #<(SCRATCH_BASE + 640)
    sta COPY_SOURCE
    lda #>(SCRATCH_BASE + 640)
    sta COPY_SOURCE + 1
    lda #<(SCRATCH_BASE + 320)
    sta COPY_TARGET
    lda #>(SCRATCH_BASE + 320)
    sta COPY_TARGET + 1
    jsr copy_320
    inc window_row
    lda window_row
    clc
    adc #2
    jmp fill_window_row

; A = absolute cell row. window_row selects its scratch slot.
fill_window_row:
    sta fill_target
    sec
    sbc window_row
    jsr clear_scratch_slot
    lda fill_target
    asl
    asl
    asl
    sta fill_y0
    clc
    adc #8
    sta fill_y1
    jmp fill_course

clear_scratch_slot:
    tax
    lda scratch_lo,x
    sta BITMAP_PTR
    lda scratch_hi,x
    sta BITMAP_PTR + 1
    lda #0
    tay
clear_256:
    sta (BITMAP_PTR),y
    iny
    bne clear_256
    inc BITMAP_PTR + 1
    ldx #64
clear_64:
    sta (BITMAP_PTR),y
    iny
    dex
    bne clear_64
    rts

copy_320:
    ldy #0
copy_256:
    lda (COPY_SOURCE),y
    sta (COPY_TARGET),y
    iny
    bne copy_256
    inc COPY_SOURCE + 1
    inc COPY_TARGET + 1
    ldx #64
copy_64:
    lda (COPY_SOURCE),y
    sta (COPY_TARGET),y
    iny
    dex
    bne copy_64
    clc
    lda COPY_SOURCE
    adc #64
    sta COPY_SOURCE
    bcc copy_source_ready
    inc COPY_SOURCE + 1
copy_source_ready:
    clc
    lda COPY_TARGET
    adc #64
    sta COPY_TARGET
    bcc copy_target_ready
    inc COPY_TARGET + 1
copy_target_ready:
    rts

fill_course:
    lda #0
    sta SEGMENTS_LEFT
fill_edge:
    ldx SEGMENTS_LEFT
    txa
    tay
    lda course_segments + 3,x
    cmp course_segments + 1,x
    bne fill_sloped
    jmp fill_next_edge
fill_sloped:
    bcc fill_upward
    iny
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
    beq fill_slope
    lda #1
    bcs fill_slope
    lda #$ff
fill_slope:
    sta LINE_X_STEP
    ; Jump straight to this cell row. Edges entirely above or below it
    ; contribute no pixels; the crossing x still advances by the skipped
    ; steps because LINE_X_STEP is only -1, 0 or +1.
    lda LINE_Y
    cmp fill_y1
    bcc fill_y_open
    jmp fill_next_edge
fill_y_open:
    cmp fill_y0
    bcs fill_scanline
    lda fill_y0
    sec
    sbc LINE_Y
    cmp LINE_LEFT
    bcc fill_edge_crosses
    jmp fill_next_edge
fill_edge_crosses:
    sta TEMP
    lda LINE_LEFT
    sec
    sbc TEMP
    sta LINE_LEFT
    lda fill_y0
    sta LINE_Y
    lda LINE_X_STEP
    beq fill_scanline
    bmi fill_clip_back
    clc
    lda LINE_X
    adc TEMP
    sta LINE_X
    bcc fill_scanline
    inc LINE_X + 1
    jmp fill_scanline
fill_clip_back:
    sec
    lda LINE_X
    sbc TEMP
    sta LINE_X
    bcs fill_scanline
    dec LINE_X + 1
fill_scanline:
    lda LINE_Y
    cmp fill_y1
    bcs fill_next_edge
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
    sbc #1
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

; Cell classes, kept in the attribute matrix while the display is off.
CLASS_FLOOR = 0
CLASS_EDGE = 1
CLASS_SOLID = 2
CLASS_OUTER = 3
CLASS_HIDDEN = 4
CLASS_WATER = 5
CLASS_SELF = 41

classify_course_cells:
    lda #CLASS_HIDDEN
    sta CLASS_SENTINEL
    ldx #240                  ; rows 0..23 only; row 24 is the HUD
classify_clear:
    sta ATTR_BASE - 1,x
    sta ATTR_BASE + 239,x
    sta ATTR_BASE + 479,x
    sta ATTR_BASE + 719,x
    dex
    bne classify_clear
    lda #1
    sta shape_row
classify_rows:
    lda shape_row
    sta window_row
    jsr fill_window_row
    lda #<SCRATCH_BASE
    sta BITMAP_PTR
    lda #>SCRATCH_BASE
    sta BITMAP_PTR + 1
    lda shape_row
    jsr class_row_pointer
    ldy #0
classify_cell:
    jsr cell_bitmap_address
    tya
    pha
    ldy #7
    lda (COPY_TARGET),y
    sta TEMP
    sta GLYPH
classify_byte:
    dey
    bmi classify_ready
    lda (COPY_TARGET),y
    tax
    ora GLYPH
    sta GLYPH
    txa
    and TEMP
    sta TEMP
    jmp classify_byte
classify_ready:
    ldx #CLASS_SOLID
    lda GLYPH
    beq classify_store
    dex
    lda TEMP
    cmp #$ff
    bne classify_store
    dex
classify_store:
    pla
    tay
    txa
    sta (COURSE_PTR),y
    iny
    cpy #40
    bne classify_cell
    inc shape_row
    lda shape_row
    cmp #21
    bne classify_rows
    rts

; A = absolute row already resident in the scratch window.
shape_one_row:
    pha
    sec
    sbc window_row
    tax
    lda scratch_lo,x
    sta BITMAP_PTR
    lda scratch_hi,x
    sta BITMAP_PTR + 1
    pla
    jsr class_row_pointer
    sec
    lda COURSE_PTR
    sbc #CLASS_SELF
    sta COURSE_PTR
    bcs shape_ptr_ready
    dec COURSE_PTR + 1
shape_ptr_ready:
    lda #40
    sta shape_cells_left
shape_cell:
    ldy #CLASS_SELF
    lda (COURSE_PTR),y
    cmp #CLASS_WATER
    beq shape_invert
    cmp #CLASS_SOLID
    beq shape_frame
    bcs shape_next
    cmp #CLASS_EDGE
    bne shape_invert
    lda #0
    sta TEMP
    lda #8
    sta LINE_LEFT
    ldy #4
    lda (BITMAP_PTR),y
    lsr
    ldy #CLASS_SELF + 1
    lda #FRAME_LEFT
    sta GLYPH
    lda #8
    ldx #0
    bcc shape_outer_horizontal
    ldy #CLASS_SELF - 1
    lda #FRAME_RIGHT
    sta GLYPH
    lda #<-8
    ldx #>-8
shape_outer_horizontal:
    jsr course_outer_cell
    lda #$ff
    sta GLYPH
    ldy #0
    lda (BITMAP_PTR),y
    and #$08
    bne shape_outer_down
    lda #8 - FRAME_WIDTH
    sta TEMP
    ldy #CLASS_SELF - 40
    lda #<-320
    ldx #>-320
    bne shape_outer_vertical
shape_outer_down:
    lda #FRAME_WIDTH
    sta LINE_LEFT
    ldy #CLASS_SELF + 40
    lda #<320
    ldx #>320
shape_outer_vertical:
    jsr course_outer_cell
shape_invert:
    ldy #7
shape_invert_byte:
    lda (BITMAP_PTR),y
    eor #$ff
    sta (BITMAP_PTR),y
    dey
    bpl shape_invert_byte
    bmi shape_next
shape_frame:
    ldx #7
shape_neighbour:
    ldy course_neighbours,x
    lda (COURSE_PTR),y
    beq shape_is_floor
    cmp #CLASS_WATER
    bne shape_neighbour_next
shape_is_floor:
    ldy frame_row_first,x
shape_frame_row:
    lda (BITMAP_PTR),y
    ora frame_columns,x
    sta (BITMAP_PTR),y
    iny
    tya
    cmp frame_row_end,x
    bne shape_frame_row
shape_neighbour_next:
    dex
    bpl shape_neighbour
shape_next:
    jsr course_cells_next
    beq shape_row_done
    jmp shape_cell
shape_row_done:
    rts

course_outer_cell:
    sta COPY_TARGET
    stx COPY_TARGET + 1
    clc
    lda BITMAP_PTR
    adc COPY_TARGET
    sta COPY_TARGET
    lda BITMAP_PTR + 1
    adc COPY_TARGET + 1
    sta COPY_TARGET + 1
    lda (COURSE_PTR),y
    cmp #CLASS_OUTER
    beq course_outer_add
    cmp #CLASS_SOLID
    bne course_outer_done
    lda #CLASS_OUTER
    sta (COURSE_PTR),y
    lda #0
    ldy #7
course_outer_clear:
    sta (COPY_TARGET),y
    dey
    bpl course_outer_clear
course_outer_add:
    ldy TEMP
course_outer_copy:
    lda (BITMAP_PTR),y
    and GLYPH
    ora (COPY_TARGET),y
    sta (COPY_TARGET),y
    iny
    cpy LINE_LEFT
    bne course_outer_copy
course_outer_done:
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
    dec shape_cells_left
    rts

mark_water:
    lda HAZARD_COUNT
    beq water_done
    sta GLYPH
    ldy #0
water_area:
    ldx #0
water_bounds:
    lda (HAZARD_PTR),y
    sta LINE_X,x
    iny
    inx
    cpx #4
    bne water_bounds
    sty TEXT_COLUMN
water_row:
    lda LINE_X + 1
    jsr class_row_pointer
    ldy LINE_X
    lda #CLASS_WATER
water_cell:
    sta (COURSE_PTR),y
    cpy LINE_X + 2
    iny
    bcc water_cell
    lda LINE_X + 1
    inc LINE_X + 1
    cmp LINE_X + 3
    bcc water_row
    ldy TEXT_COLUMN
    dec GLYPH
    bne water_area
water_done:
    rts

FRAME_LEFT = ($ff << (8 - FRAME_WIDTH)) & $ff
FRAME_RIGHT = $ff >> (8 - FRAME_WIDTH)
course_neighbours:
!byte 0,1,2,40,42,80,81,82
frame_row_first:
!byte 0,0,0,0,0,8 - FRAME_WIDTH,8 - FRAME_WIDTH,8 - FRAME_WIDTH
frame_row_end:
!byte FRAME_WIDTH,FRAME_WIDTH,FRAME_WIDTH,8,8,8,8,8
frame_columns:
!byte FRAME_LEFT,$ff,FRAME_RIGHT,FRAME_LEFT,FRAME_RIGHT,FRAME_LEFT,$ff,FRAME_RIGHT

; Stamp the cup, invert the row and assign each cell a character and a
; foreground colour. A = absolute row resident in the scratch window.
emit_playfield_row:
    sta emit_row
    jsr draw_cup
    lda emit_row
    sec
    sbc window_row
    tax
    lda scratch_lo,x
    sta BITMAP_PTR
    lda scratch_hi,x
    sta BITMAP_PTR + 1
    lda emit_row
    jsr class_row_pointer
    lda COURSE_PTR
    sta COPY_SOURCE
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COPY_SOURCE + 1
    ldy #0
    sty TEXT_COLUMN
emit_cell:
    lda (COURSE_PTR),y
    sta GLYPH
    jsr cell_bitmap_address
    tya
    pha
    ldy #7
emit_invert:
    lda (COPY_TARGET),y
    eor #$ff
    sta (COPY_TARGET),y
    dey
    bpl emit_invert
    lda BITMAP_PTR
    pha
    lda BITMAP_PTR + 1
    pha
    lda COPY_TARGET
    sta BITMAP_PTR
    lda COPY_TARGET + 1
    sta BITMAP_PTR + 1
    jsr intern_pattern
    tax
    pla
    sta BITMAP_PTR + 1
    pla
    sta BITMAP_PTR
    pla
    tay
    txa
    sta (COPY_SOURCE),y
    lda emit_row
    eor TEXT_COLUMN
    and #1
emit_ink_index:
    asl GLYPH
    ora GLYPH
    tax
    lda course_ink,x
    sta (COURSE_PTR),y
    inc TEXT_COLUMN
    iny
    cpy #40
    bne emit_cell
    rts

; Rows whose bitmap is irrelevant: one solid character, checker foreground.
emit_hidden_row:
    sta emit_row
    lda #<solid_glyph
    sta BITMAP_PTR
    lda #>solid_glyph
    sta BITMAP_PTR + 1
    jsr intern_pattern
    sta TEMP
    lda emit_row
    jsr class_row_pointer
    lda COURSE_PTR
    sta COPY_SOURCE
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COPY_SOURCE + 1
    ldy #0
    sty TEXT_COLUMN
hidden_cell:
    lda TEMP
    sta (COPY_SOURCE),y
    lda #CLASS_HIDDEN
    sta GLYPH
    lda emit_row
    eor TEXT_COLUMN
    and #1
    jmp emit_ink_store
hidden_stored:
    inc TEXT_COLUMN
    iny
    cpy #40
    bne hidden_cell
    rts

; Shared ink store used by the hidden row. Falls through from eor above.
emit_ink_store:
    asl GLYPH
    ora GLYPH
    tax
    lda course_ink,x
    sta (COURSE_PTR),y
    jmp hidden_stored

; Y = column. COPY_TARGET points at that cell in the row at BITMAP_PTR.
; Column 32 is byte 256 of the row, so the shift carry is the high byte.
cell_bitmap_address:
    tya
    asl
    asl
    asl
    sta COPY_TARGET
    lda #0
    rol
    sta COPY_TARGET + 1
    clc
    lda COPY_TARGET
    adc BITMAP_PTR
    sta COPY_TARGET
    lda COPY_TARGET + 1
    adc BITMAP_PTR + 1
    sta COPY_TARGET + 1
    rts

; Eight bytes at BITMAP_PTR join the course catalogue. A = screen code.
intern_pattern:
    ldx #0
intern_search:
    cpx pattern_count
    beq intern_new
    txa
    clc
    adc #COURSE_CHAR
    jsr charset_address
    ldy #7
intern_cmp:
    lda (BITMAP_PTR),y
    cmp (FONT_PTR),y
    bne intern_next
    dey
    bpl intern_cmp
    txa
    clc
    adc #COURSE_CHAR
    rts
intern_next:
    inx
    bne intern_search
intern_new:
    cpx #COURSE_CHAR_LIMIT
    bcc intern_store
    lda #1
    sta pattern_overflow
    lda #COURSE_CHAR
    rts
intern_store:
    txa
    clc
    adc #COURSE_CHAR
    pha
    jsr charset_address
    ldy #7
intern_copy:
    lda (BITMAP_PTR),y
    sta (FONT_PTR),y
    dey
    bpl intern_copy
    inc pattern_count
    pla
    rts

; Index = class * 2 + checker parity. The value is the text-mode foreground
; (luminance in bits 6..4, hue in bits 3..0). Black is the global background.
course_ink:
!byte COURSE_SURFACE_COLOR,COURSE_SURFACE_COLOR
!byte COURSE_SURFACE_COLOR,COURSE_SURFACE_COLOR
!byte CHECKER_COLOR_EVEN,CHECKER_COLOR_ODD
!byte CHECKER_COLOR_EVEN,CHECKER_COLOR_ODD
!byte CHECKER_COLOR_EVEN,CHECKER_COLOR_ODD
!byte WATER_COLOR_EVEN,WATER_COLOR_ODD

window_row:
!byte 0
fill_target:
!byte 0
fill_y0:
!byte 0
fill_y1:
!byte 0
emit_row:
!byte 0
shape_row:
!byte 0
shape_cells_left:
!byte 0
pattern_count:
!byte 0
pattern_overflow:
!byte 0
solid_glyph:
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
