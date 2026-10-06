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
    lda #$ff
    sta solid_code            ; none yet
    jsr clear_course_classes
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
    ; Slot 1 -> slot 0 and slot 2 -> slot 1. Each index reads slot 1
    ; before it is overwritten.
    ldx #0
slide_first_page:
    lda SCRATCH_BASE + 320,x
    sta SCRATCH_BASE,x
    lda SCRATCH_BASE + 640,x
    sta SCRATCH_BASE + 320,x
    inx
    bne slide_first_page
    ldx #320 - 256
slide_rest:
    lda SCRATCH_BASE + 320 + 256 - 1,x
    sta SCRATCH_BASE + 256 - 1,x
    lda SCRATCH_BASE + 640 + 256 - 1,x
    sta SCRATCH_BASE + 320 + 256 - 1,x
    dex
    bne slide_rest
    inc window_row
    lda window_row
    clc
    adc #2
    jmp fill_window_row

; A = absolute cell row. window_row selects its scratch slot. Rows 1..20
; are classified as soon as they are filled: shaping row r needs only the
; classes of rows r-1..r+1, and shaping may then turn cells of row r+1
; into outer edges.
fill_window_row:
    sta fill_target
    jsr fill_window_pixels
    lda fill_target
    beq fill_window_done
    cmp #21
    bcs fill_window_done
    jmp classify_row
fill_window_done:
    rts

fill_window_pixels:
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
    bcc fill_scanline_open
    jmp fill_next_edge
fill_scanline_open:
    ; BITMAP_PTR = this scanline in its window slot; the bytes of one
    ; scanline are 8 apart, columns 32..39 lie 256 bytes further on.
    lsr
    lsr
    lsr
    sec
    sbc window_row
    tax
    lda LINE_Y
    and #7
    clc
    adc scratch_lo,x
    sta BITMAP_PTR
    lda scratch_hi,x
    adc #0
    sta BITMAP_PTR + 1
    lda LINE_X
    and #7
    tax
    lda pixel_masks,x
    asl
    sec
    sbc #1
    sta PIXEL_MASK            ; first byte: bits from the crossing rightwards
    lda LINE_X
    and #$f8
    tay
    ; Invert from the crossing to column 38.
    lda LINE_X + 1
    bne fill_high_first
    lda (BITMAP_PTR),y
    eor PIXEL_MASK
    sta (BITMAP_PTR),y
    clc
fill_low:
    tya
    adc #8
    tay
    bcs fill_high_start       ; carry only past column 31
    lda (BITMAP_PTR),y
    eor #$ff
    sta (BITMAP_PTR),y
    jmp fill_low
fill_high_first:
    inc BITMAP_PTR + 1
    lda (BITMAP_PTR),y
    eor PIXEL_MASK
    sta (BITMAP_PTR),y
    jmp fill_high_next
fill_high_start:
    inc BITMAP_PTR + 1
    ldy #0
fill_high:
    lda (BITMAP_PTR),y
    eor #$ff
    sta (BITMAP_PTR),y
fill_high_next:
    tya
    clc
    adc #8
    tay
    cpy #7 * 8
    bcc fill_high
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
    beq fill_next_edge
    jmp fill_scanline
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

clear_course_classes:
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
    rts

; A = absolute row resident in the window. Cells already marked as water
; keep that class; water areas only cover whole floor cells.
classify_row:
    pha
    sec
    sbc window_row
    tax
    lda scratch_lo,x
    sta COPY_TARGET
    lda scratch_hi,x
    sta COPY_TARGET + 1
    pla
    jsr class_row_pointer
    lda #0
    sta TEXT_COLUMN
classify_cell:
    ldy #0
    lda (COPY_TARGET),y
!for cell_byte, 1, 7 {
    ldy #cell_byte
    ora (COPY_TARGET),y
}
    ldx #CLASS_SOLID
    tay
    beq classify_store
    ldy #0
    lda (COPY_TARGET),y
!for cell_byte, 1, 7 {
    ldy #cell_byte
    and (COPY_TARGET),y
}
    ldx #CLASS_EDGE
    cmp #$ff
    bne classify_store
    ldx #CLASS_FLOOR
classify_store:
    ldy TEXT_COLUMN
    lda (COURSE_PTR),y
    cmp #CLASS_WATER
    beq classify_next
    txa
    sta (COURSE_PTR),y
classify_next:
    clc
    lda COPY_TARGET
    adc #8
    sta COPY_TARGET
    bcc classify_column
    inc COPY_TARGET + 1
classify_column:
    inc TEXT_COLUMN
    lda TEXT_COLUMN
    cmp #40
    bne classify_cell
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
    bcc shape_floor_or_edge
    cmp #CLASS_OUTER
    bne shape_next_far
    lda #$ff                  ; outer cells: orthogonal bands only
    bne shape_bands
shape_frame:
    lda #0
shape_bands:
    sta frame_skip
    jsr frame_bands
shape_next_far:
    jmp shape_next
shape_floor_or_edge:
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
    tya
    tax                       ; class offset of the outer cell
    lda #0
    ldy #7
course_outer_clear:
    sta (COPY_TARGET),y
    dey
    bpl course_outer_clear
    ; A cell left of or above the edge was shaped already: give it its
    ; orthogonal bands again, so a straight frame meets the slope closed.
    lda COURSE_PTR
    pha
    lda COURSE_PTR + 1
    pha
    lda BITMAP_PTR
    pha
    lda BITMAP_PTR + 1
    pha
    txa
    sec
    sbc #CLASS_SELF
    tay                       ; -40..40
    clc
    adc COURSE_PTR
    sta COURSE_PTR
    tya
    and #$80
    beq outer_offset_positive
    lda #$ff
outer_offset_positive:
    adc COURSE_PTR + 1
    sta COURSE_PTR + 1
    +copy16 COPY_TARGET, BITMAP_PTR
    lda #$ff
    sta frame_skip
    jsr frame_bands
    pla
    sta BITMAP_PTR + 1
    pla
    sta BITMAP_PTR
    pla
    sta COURSE_PTR + 1
    pla
    sta COURSE_PTR
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
; Bands towards whole floor or water neighbours; frame_skip = $ff keeps
; only the four orthogonal ones (outer cells beside a slope).
frame_bands:
    ldx #7
frame_band_neighbour:
    lda frame_diagonal,x
    and frame_skip
    bne frame_band_next
    ldy course_neighbours,x
    lda (COURSE_PTR),y
    beq frame_band_floor
    cmp #CLASS_WATER
    bne frame_band_next
frame_band_floor:
    ldy frame_row_first,x
frame_band_row:
    lda (BITMAP_PTR),y
    ora frame_columns,x
    sta (BITMAP_PTR),y
    iny
    tya
    cmp frame_row_end,x
    bne frame_band_row
frame_band_next:
    dex
    bpl frame_band_neighbour
    rts
frame_skip:
!byte 0
frame_diagonal:
!byte $ff,0,$ff,0,0,$ff,0,$ff
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
    sta COPY_TARGET
    lda scratch_hi,x
    sta COPY_TARGET + 1
    lda emit_row
    jsr class_row_pointer
    lda COURSE_PTR
    sta COPY_SOURCE
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COPY_SOURCE + 1
    lda #0
    sta TEXT_COLUMN
emit_cell:
    ldy TEXT_COLUMN
    lda (COURSE_PTR),y
    sta GLYPH
    ; No black pixel: the solid character. The emitted row is not read
    ; again, so its bytes need not be inverted.
    ldy #0
    lda (COPY_TARGET),y
!for cell_byte, 1, 7 {
    ldy #cell_byte
    ora (COPY_TARGET),y
}
    bne emit_pattern
    jsr solid_character
    jmp emit_code
emit_pattern:
!for cell_byte, 0, 7 {
    ldy #cell_byte
    lda (COPY_TARGET),y
    eor #$ff
    sta (COPY_TARGET),y
}
    lda COPY_TARGET
    sta BITMAP_PTR
    lda COPY_TARGET + 1
    sta BITMAP_PTR + 1
    jsr intern_pattern
emit_code:
    ldy TEXT_COLUMN
    sta (COPY_SOURCE),y
    tya
    eor emit_row
    and #1
    asl GLYPH
    ora GLYPH
    tax
    lda course_ink,x
    sta (COURSE_PTR),y
    clc
    lda COPY_TARGET
    adc #8
    sta COPY_TARGET
    bcc emit_column
    inc COPY_TARGET + 1
emit_column:
    inc TEXT_COLUMN
    lda TEXT_COLUMN
    cmp #40
    beq emit_row_done
    jmp emit_cell
emit_row_done:
    rts

; A = screen code of the solid glyph, interned on first use.
solid_character:
    lda solid_code
    bpl solid_ready
    lda #<solid_glyph
    sta BITMAP_PTR
    lda #>solid_glyph
    sta BITMAP_PTR + 1
    jsr intern_pattern
    sta solid_code
solid_ready:
    rts

; Rows whose bitmap is irrelevant: one solid character, checker foreground.
emit_hidden_row:
    sta emit_row
    jsr solid_character
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
solid_code:
!byte $ff
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
