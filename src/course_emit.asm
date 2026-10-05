; Hidden-row part of decode_course (src/course_decoder.asm).
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
