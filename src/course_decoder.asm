; X = course index. Unpacks a version-2 stream (tools/course_codec.py)
; into course_segments plus start/cup variables. Runs of one direction merge
; into one segment; flags match tools/generate_assets.expanded_segments.
decode_course:
    lda course_table_lo,x
    sta COURSE_PTR
    lda course_table_hi,x
    sta COURSE_PTR + 1
    ldy #3
decode_header:
    lda (COURSE_PTR),y
    asl
    sta COURSE_POS_LO,y
    lda #0
    sta SEGMENT_BYTES
    rol
    sta COURSE_POS_HI,y
    dey
    bpl decode_header
    ldy #2
    lda (COURSE_PTR),y
    sta COURSE_CUP_HALF_X
    ldy #4
    lda (COURSE_PTR),y
    sta DECODE_CONTOURS
decode_contour:
    iny
    lda (COURSE_PTR),y
    sta DECODE_X
    iny
    lda (COURSE_PTR),y
    and #$80
    sta DECODE_SIDE
    eor (COURSE_PTR),y
    sta DECODE_Y
    iny
    lda (COURSE_PTR),y
    sta DECODE_RUNS
    ; The closing run's direction precedes the first vertex.
    sty TEMP
    clc
    adc TEMP
    tay
    lda (COURSE_PTR),y
    lsr
    lsr
    lsr
    lsr
    lsr
    sta DECODE_PREV
    ldy TEMP
    lda #$ff
    sta DECODE_DIR
decode_run:
    iny
    lda (COURSE_PTR),y
    and #31
    bne decode_length
    lda #32
decode_length:
    sta DECODE_LENGTH
    lda (COURSE_PTR),y
    lsr
    lsr
    lsr
    lsr
    lsr
    cmp DECODE_DIR
    beq decode_move
    pha
    lda DECODE_DIR
    bmi decode_new_segment
    jsr emit_segment
decode_new_segment:
    lda DECODE_X
    sta DECODE_SX
    lda DECODE_Y
    sta DECODE_SY
    pla
    sta DECODE_DIR
decode_move:
    tax
    lda direction_dx,x
    pha
    lda direction_dy,x
    sta TEMP
    ldx #0
    pla                       ; flags for the x step
decode_axis:
    beq decode_axis_next
    bmi decode_axis_negative
    lda DECODE_X,x
    clc
    adc DECODE_LENGTH
    bcc decode_axis_store     ; validated coordinates never carry
decode_axis_negative:
    lda DECODE_X,x
    sec
    sbc DECODE_LENGTH
decode_axis_store:
    sta DECODE_X,x
decode_axis_next:
    inx
    cpx #2
    beq decode_run_done
    lda TEMP
    jmp decode_axis
decode_run_done:
    dec DECODE_RUNS
    bne decode_run
    lda DECODE_DIR
    jsr emit_segment
    dec DECODE_CONTOURS
    beq decode_done
    jmp decode_contour
decode_done:
    rts
