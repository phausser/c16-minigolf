; X = course index. Unpacks a version-5 stream (tools/course_codec.py)
; into course_segments plus start/cup variables. Runs of one direction merge
; into one segment; flags match tools/generate_assets.expanded_segments.
; Floor and lawn inks first, from the surface chosen on the title.
decode_course:
    lda #0
    sta outline_bytes
    jsr apply_surface
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
    ldy #4
    lda (COURSE_PTR),y
    sta ANGLE                 ; initial aim along the course
    iny
    lda (COURSE_PTR),y
    and #31
    sta DECODE_CONTOURS
    lda (COURSE_PTR),y
    lsr
    lsr
    lsr
    lsr
    lsr
    sta HAZARD_COUNT          ; 0..7
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
    lda normal_sign_x,x       ; same eight steps as the collision normals
    pha
    lda normal_sign_y,x
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
    jsr emit_segment          ; A = length so far; X is free, Y is the stream
    ldx outline_bytes
    bne outline_kept
    sta outline_bytes         ; contour 0, the outline
outline_kept:
    dec DECODE_CONTOURS
    beq decode_done
    jmp decode_contour
decode_done:
    ; Water rectangles follow the last run.
    iny
    tya
    clc
    adc COURSE_PTR
    sta HAZARD_PTR
    lda COURSE_PTR + 1
    adc #0
    sta HAZARD_PTR + 1
    rts

; Paints floor_ink and lawn_ink from menu_surface. X is the course index
; and comes back unchanged. The darker lawn square is one luminance down.
apply_surface:
    txa
    pha
    ldx menu_surface
    lda surface_lawn,x
    sta lawn_ink
    ora #$80                  ; solid and outer: not reached yet
    sta lawn_ink - 2
    sta lawn_ink - 4
    sec
    sbc #$10
    sta lawn_ink - 1
    sta lawn_ink - 3
    and #$7f
    sta lawn_ink + 1
    lda surface_floor,x
    ldy #3
apply_floor:
    sta floor_ink,y
    dey
    bpl apply_floor
    pla
    tax
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
