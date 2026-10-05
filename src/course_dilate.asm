; Grow the set (floor) pixels of rows 1..20 by DILATE_RADIUS pixels in x and
; y, in place: a pixel becomes set when a set pixel lies within the square.
; Pixels outside the playfield rows count as clear.
DILATE_PREV = M_A             ; original byte left of the current one
DILATE_CUR = M_A + 1
DILATE_NEXT = M_B
DILATE_LOW = M_B + 1          ; 16-bit shift window
DILATE_HIGH = M_PRODUCT
DILATE_RADIUS = 3
!if DILATE_RADIUS != 3 { !error "dilate_vertical_byte keeps three history bytes" }
DILATE_HISTORY = M_PRODUCT + 1 ; DILATE_RADIUS original bytes above/below
DILATE_CELLS = M_COUNT

dilate_course:
    lda #<$2140
    sta LINE_X
    lda #>$2140
    sta LINE_X + 1
dilate_cell_row:
    lda #0
    sta ROW_INDEX
dilate_pixel_row:
    ; BITMAP_PTR walks the row with Y += 8, COPY_TARGET is one byte ahead.
    lda LINE_X
    sta BITMAP_PTR
    clc
    adc #8
    sta COPY_TARGET
    lda LINE_X + 1
    sta BITMAP_PTR + 1
    adc #0
    sta COPY_TARGET + 1
    ldy ROW_INDEX
    lda #0
    sta DILATE_PREV
    lda #40
    sta TEXT_COLUMN
dilate_byte:
    lda #0
    dec TEXT_COLUMN
    beq dilate_next_ready     ; nothing right of the screen
    lda (COPY_TARGET),y
dilate_next_ready:
    sta DILATE_NEXT
    lda (BITMAP_PTR),y
    sta DILATE_CUR
    cmp #$ff
    beq dilate_byte_done      ; already full
    ora DILATE_PREV
    ora DILATE_NEXT
    beq dilate_byte_done      ; nothing near
    lda DILATE_PREV
    sta DILATE_HIGH
    lda DILATE_CUR
    sta DILATE_LOW
    ldx #DILATE_RADIUS
dilate_from_left:
    lsr DILATE_HIGH
    ror DILATE_LOW
    ora DILATE_LOW
    dex
    bne dilate_from_left
    ldx DILATE_NEXT
    stx DILATE_LOW
    ldx DILATE_CUR
    stx DILATE_HIGH
    ldx #DILATE_RADIUS
dilate_from_right:
    asl DILATE_LOW
    rol DILATE_HIGH
    ora DILATE_HIGH
    dex
    bne dilate_from_right
    sta (BITMAP_PTR),y
dilate_byte_done:
    lda DILATE_CUR
    sta DILATE_PREV
    tya
    clc
    adc #8
    tay
    bcc dilate_column_ready
    inc BITMAP_PTR + 1
    inc COPY_TARGET + 1
dilate_column_ready:
    lda TEXT_COLUMN
    bne dilate_byte
    inc ROW_INDEX
    lda ROW_INDEX
    cmp #8
    bne dilate_pixel_row
    clc
    lda LINE_X
    adc #<320
    sta LINE_X
    lda LINE_X + 1
    adc #>320
    sta LINE_X + 1
    cmp #>$3a40
    bne dilate_more_rows
    lda LINE_X
    cmp #<$3a40
    beq dilate_rows_done
dilate_more_rows:
    jmp dilate_cell_row
dilate_rows_done:

    ; Vertical: per byte column, first downwards, then upwards.
    lda #<$2140
    sta LINE_X
    lda #>$2140
    sta LINE_X + 1
    lda #40
    sta TEXT_COLUMN
dilate_down_column:
    jsr dilate_history_clear
    lda LINE_X
    sta COPY_SOURCE
    lda LINE_X + 1
    sta COPY_SOURCE + 1
dilate_down_cell:
    ldy #0
dilate_down_byte:
    jsr dilate_vertical_byte
    iny
    cpy #8
    bne dilate_down_byte
    clc
    lda COPY_SOURCE
    adc #<320
    sta COPY_SOURCE
    lda COPY_SOURCE + 1
    adc #>320
    sta COPY_SOURCE + 1
    dec DILATE_CELLS
    bne dilate_down_cell
    ; COPY_SOURCE is one cell row past the bottom: walk back up.
    jsr dilate_history_clear
dilate_up_cell:
    sec
    lda COPY_SOURCE
    sbc #<320
    sta COPY_SOURCE
    lda COPY_SOURCE + 1
    sbc #>320
    sta COPY_SOURCE + 1
    ldy #7
dilate_up_byte:
    jsr dilate_vertical_byte
    dey
    bpl dilate_up_byte
    dec DILATE_CELLS
    bne dilate_up_cell
    clc
    lda LINE_X
    adc #8
    sta LINE_X
    bcc dilate_next_column
    inc LINE_X + 1
dilate_next_column:
    dec TEXT_COLUMN
    bne dilate_down_column
    rts

dilate_history_clear:
    lda #0
    ldx #DILATE_RADIUS - 1
dilate_history_zero:
    sta DILATE_HISTORY,x
    dex
    bpl dilate_history_zero
    lda #20
    sta DILATE_CELLS
    rts

; OR the byte at (COPY_SOURCE),Y with the three previous originals of this
; pass and remember its original value.
dilate_vertical_byte:
    lda (COPY_SOURCE),y
    tax
    ora DILATE_HISTORY
    ora DILATE_HISTORY + 1
    ora DILATE_HISTORY + 2
    beq dilate_vertical_done  ; all clear: nothing to store or remember
    sta (COPY_SOURCE),y
    lda DILATE_HISTORY + 1
    sta DILATE_HISTORY + 2
    lda DILATE_HISTORY
    sta DILATE_HISTORY + 1
    stx DILATE_HISTORY
dilate_vertical_done:
    rts
