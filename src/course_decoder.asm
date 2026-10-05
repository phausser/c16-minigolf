; X = course index. Unpacks a version-3 stream (tools/course_codec.py)
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
    ; Cells to 2px segment units: x/8 * 4.
    iny
    lda (COURSE_PTR),y
    asl
    asl
    sta DECODE_X
    iny
    lda (COURSE_PTR),y
    and #$80
    sta DECODE_SIDE
    eor (COURSE_PTR),y
    asl
    asl
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
    asl
    asl
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

; A = direction of the segment ending at the current vertex.
; Caps are hidden at collinear joints and convex playable corners.
emit_segment:
    ldx SEGMENT_BYTES
    pha
    sec
    sbc DECODE_PREV
    and #7
    beq emit_hidden
    cmp #4                    ; carry set: left turn
    lda #0
    ror
    eor DECODE_SIDE           ; $80: turn matches the normal side
    jmp emit_flag
emit_hidden:
    lda #$80
emit_flag:
    sta course_segments + 4,x
    pla
    sta DECODE_PREV
    clc
    adc #6                    ; normal = direction - 2
    bit DECODE_SIDE
    bpl emit_normal
    adc #4                    ; normal = direction + 2
emit_normal:
    and #7
    ora course_segments + 4,x
    sta course_segments + 4,x
    lda DECODE_SX
    sta course_segments,x
    lda DECODE_SY
    sta course_segments + 1,x
    lda DECODE_X
    sta course_segments + 2,x
    lda DECODE_Y
    sta course_segments + 3,x
    txa
    clc
    adc #5
    sta SEGMENT_BYTES
    rts

direction_dx:
!byte 1,1,0,$ff,$ff,$ff,0,1
direction_dy:
!byte 0,1,1,1,0,$ff,$ff,$ff
