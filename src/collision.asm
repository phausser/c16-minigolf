!macro add24 .left, .right, .target {
    +add16 .left, .right, .target
    lda .left + 2
    adc .right + 2
    sta .target + 2
}
!macro sub24 .left, .right, .target {
    +sub16 .left, .right, .target
    lda .left + 2
    sbc .right + 2
    sta .target + 2
}
!macro extend16 .source, .target {
    +copy16 .source, .target
    lda .source + 1
    bpl +
    lda #$ff
    bne .extended
+   lda #0
.extended:
    sta .target + 2
}

; Packed coordinates are only for the broadphase. +/-8 pixels includes
; the entire 4px frame path, reflections and the 2px ball radius.
collect_candidates:
    lda BALL_POS_X + 2
    lsr
    lda BALL_POS_X + 1
    ror
    sta BOUNDS_X
    lda BALL_POS_Y + 1
    lsr
    sta BOUNDS_Y
    lda #0
    sta CANDIDATE_COUNT
    sta SEG_OFFSET
collect_next:
    ldy SEG_OFFSET
    lda course_segments,y
    cmp course_segments + 2,y
    bcc collect_x_ordered
    lda course_segments + 2,y
collect_x_ordered:
    sec
    sbc #4
    cmp BOUNDS_X
    bcc collect_x_max
    beq collect_x_max
    jmp collect_skip
collect_x_max:
    lda course_segments,y
    cmp course_segments + 2,y
    bcs collect_x_max_ordered
    lda course_segments + 2,y
collect_x_max_ordered:
    clc
    adc #4
    cmp BOUNDS_X
    bcc collect_skip
    lda course_segments + 1,y
    cmp course_segments + 3,y
    bcc collect_y_ordered
    lda course_segments + 3,y
collect_y_ordered:
    sec
    sbc #4
    cmp BOUNDS_Y
    bcc collect_y_max
    beq collect_y_max
    bcs collect_skip
collect_y_max:
    lda course_segments + 1,y
    cmp course_segments + 3,y
    bcs collect_y_max_ordered
    lda course_segments + 3,y
collect_y_max_ordered:
    clc
    adc #4
    cmp BOUNDS_Y
    bcc collect_skip
    ldx CANDIDATE_COUNT
    lda SEG_OFFSET
    sta CANDIDATES,x
    inc CANDIDATE_COUNT
collect_skip:
    clc
    lda SEG_OFFSET
    adc #5
    sta SEG_OFFSET
    cmp #COURSE_SEGMENT_COUNT * 5
    bcc collect_next
    rts

find_first_contact:
    lda #0
    sta HIT
    sta FRAME_CUP
    sta PHYS_INDEX
    sta STEP_SQUARE_VALID
    sta RADIUS_SQUARED
    sta RADIUS_SQUARED + 1
    sta RADIUS_SQUARED + 3
    lda #4                    ; (2 * 256)^2 = $00040000
    sta RADIUS_SQUARED + 2
contact_next:
    lda PHYS_INDEX
    cmp CANDIDATE_COUNT
    bcs contact_done
    tax
    lda CANDIDATES,x
    sta SEG_OFFSET
    tay
    lda course_segments + 4,y
    sta NORMAL_CODE
    jsr decode_start
    jsr try_line
    jsr try_circle
    ; Every contour is closed: each segment end is the next segment start.
    ; Test each vertex once, preventing duplicate swept-circle work.
    inc PHYS_INDEX
    jmp contact_next
contact_done:
    rts

decode_start:
    ldy SEG_OFFSET
    lda course_segments + 1,y
    tax
    lda course_segments,y
    jmp decode_point
decode_end:
    ldy SEG_OFFSET
    lda course_segments + 3,y
    tax
    lda course_segments + 2,y
decode_point:
    asl
    sta POINT_X + 1
    lda #0
    rol
    sta POINT_X + 2
    lda #0
    sta POINT_X
    sta POINT_Y
    txa
    asl
    sta POINT_Y + 1
    rts

relative_point:
    +sub24 BALL_POS_X, POINT_X, DX_WIDE
    +sub16 BALL_POS_Y, POINT_Y, DY_WIDE
    lda #0
    sbc #0
    sta DY_WIDE + 2
    rts

; Signed dot of wide relative coordinates with an unnormalized axis/45deg
; inward normal. Keeping 24 bits avoids wrapping a long diagonal's start.
dot_normal:
    lda #0
    sta GAP
    sta GAP + 1
    sta GAP + 2
    ldx NORMAL_CODE
    lda normal_sign_x,x
    beq dot_normal_y
    bmi dot_normal_negative_x
    +add24 GAP, DX_WIDE, GAP
    jmp dot_normal_y
dot_normal_negative_x:
    +sub24 GAP, DX_WIDE, GAP
dot_normal_y:
    lda normal_sign_y,x
    beq dot_normal_done
    bmi dot_normal_negative_y
    +add24 GAP, DY_WIDE, GAP
    rts
dot_normal_negative_y:
    +sub24 GAP, DY_WIDE, GAP
dot_normal_done:
    rts

try_line:
    jsr incoming_normal
    bcs line_incoming
    clc
    rts
line_incoming:
    jsr axis_projection_near
    bcs line_projection_near
    clc
    rts
line_projection_near:
    jsr relative_point
    jsr dot_normal
    lda NORMAL_CODE
    and #1
    beq line_axis_radius
    lda #<DIAGONAL_RADIUS
    ldx #>DIAGONAL_RADIUS
    bne line_sub_radius
line_axis_radius:
    lda #<BALL_RADIUS
    ldx #>BALL_RADIUS
line_sub_radius:
    sta M_A
    stx M_A + 1
    lda #0
    sta M_A + 2             ; M_A+2 aliases M_B, unused in this subtraction
    +sub24 GAP, M_A, GAP
    lda GAP + 2
    beq collision_branch_1
    jmp line_no_contact
collision_branch_1:
    +copy16 GAP, SAVED_X
    +copy16 DOT_STEP, M_DEN
    +negate16 M_DEN
    +copy16 SAVED_X, M_REM
    lda #0
    sta M_DEN + 2
    sta M_REM + 2
    lda M_REM + 1
    cmp M_DEN + 1
    bcc line_fraction
    beq collision_branch_3
    jmp line_no_contact
collision_branch_3:
    lda M_REM
    cmp M_DEN
    bcc line_fraction
    beq collision_branch_4
    jmp line_no_contact
collision_branch_4:
    lda #255
    bne line_time_ready
line_fraction:
    jsr divide_fraction
    lda M_QUOT
line_time_ready:
    sta TRIAL_T
    jsr displacement_at_t
    jsr line_projection
    bcs collision_branch_5
    jmp line_no_contact
collision_branch_5:
    ldx NORMAL_CODE
    lda normal_x_lo,x
    sta NX
    lda normal_x_hi,x
    sta NX + 1
    lda normal_y_lo,x
    sta NY
    lda normal_y_hi,x
    sta NY + 1
    jmp record_contact
line_no_contact:
    clc
    rts

; Project the trial contact onto the finite segment, in Q10.6 to fit the
; entire 320px extent in a signed word. Error is bounded by 1/64px at the
; line/cap transition. Circle caps use the original Q8 fractional precision.
line_projection:
    jsr relative_point
    +extend16 TRIAL_X, M_MULTIPLICAND
    +add24 DX_WIDE, M_MULTIPLICAND, DX_WIDE
    +extend16 TRIAL_Y, M_MULTIPLICAND
    +add24 DY_WIDE, M_MULTIPLICAND, DY_WIDE
    ldx #2
projection_scale:
    lda DX_WIDE + 2
    asl
    ror DX_WIDE + 2
    ror DX_WIDE + 1
    ror DX_WIDE
    lda DY_WIDE + 2
    asl
    ror DY_WIDE + 2
    ror DY_WIDE + 1
    ror DY_WIDE
    dex
    bne projection_scale
    lda #0
    sta SAVED_X
    sta SAVED_X + 1
    sta SAVED_Y
    sta SAVED_Y + 1
    ldy SEG_OFFSET
    lda course_segments + 2,y
    cmp course_segments,y
    beq projection_y
    bcc projection_left
    sec
    sbc course_segments,y
    sta SAVED_Y
    +copy16 DX_WIDE, SAVED_X
    jmp projection_y
projection_left:
    lda course_segments,y
    sec
    sbc course_segments + 2,y
    sta SAVED_Y
    +copy16 DX_WIDE, SAVED_X
    +negate16 SAVED_X
projection_y:
    lda course_segments + 3,y
    cmp course_segments + 1,y
    beq projection_compare
    bcc projection_up
    sec
    sbc course_segments + 1,y
    clc
    adc SAVED_Y
    sta SAVED_Y
    +add16 SAVED_X, DY_WIDE, SAVED_X
    jmp projection_compare
projection_up:
    lda course_segments + 1,y
    sec
    sbc course_segments + 3,y
    clc
    adc SAVED_Y
    sta SAVED_Y
    +sub16 SAVED_X, DY_WIDE, SAVED_X
projection_compare:
    lda SAVED_X + 1
    bmi projection_invalid
    ldx #7
projection_length:
    asl SAVED_Y
    rol SAVED_Y + 1
    dex
    bne projection_length
    lda SAVED_X + 1
    cmp SAVED_Y + 1
    bcc projection_valid
    bne projection_invalid
    lda SAVED_Y
    cmp SAVED_X
    bcc projection_invalid
projection_valid:
    sec
    rts
projection_invalid:
    clc
    rts

; Circle sweeps examine the closest point along the entire displacement,
; then bisect the entry interval. Checking only the end position would miss
; a grazing entry-and-exit within a single subinterval.
try_circle:
    ; Frame-origin bounds reject remote vertices before wide subtraction.
    lda POINT_X + 2
    lsr
    lda POINT_X + 1
    ror
    sta M_A
    lda BOUNDS_X
    sec
    sbc M_A
    bpl circle_packed_x
    eor #$ff
    clc
    adc #1
circle_packed_x:
    cmp #4
    bcc circle_packed_y_test
    clc
    rts
circle_packed_y_test:
    lda POINT_Y + 1
    lsr
    sta M_A
    lda BOUNDS_Y
    sec
    sbc M_A
    bpl circle_packed_y
    eor #$ff
    clc
    adc #1
circle_packed_y:
    cmp #4
    bcc circle_vertex_near
    clc
    rts
circle_vertex_near:
    jsr relative_point
    lda DX_WIDE + 2
    beq circle_x_positive
    cmp #$ff
    beq collision_branch_6
    jmp circle_no_contact
collision_branch_6:
circle_x_positive:
    +copy16 DX_WIDE, QX
    +copy16 DY_WIDE, QY
    +copy16 QX, M_A
    lda M_A + 1
    bpl circle_x_absolute
    +negate16 M_A
circle_x_absolute:
    lda M_A + 1
    cmp #7
    bcc collision_branch_7
    jmp circle_no_contact
collision_branch_7:
    +copy16 QY, M_A
    lda M_A + 1
    bpl circle_y_absolute
    +negate16 M_A
circle_y_absolute:
    lda M_A + 1
    cmp #7
    bcc collision_branch_8
    jmp circle_no_contact
collision_branch_8:
    +copy16 QX, SAVED_X
    +copy16 QY, SAVED_Y
    jsr circle_motion_away
    bcc circle_may_approach
    clc
    rts
circle_may_approach:
    +copy16 QX, M_A
    +copy16 STEP_X, M_B
    jsr swept_axis_near
    bcs circle_swept_x
    jmp circle_no_contact
circle_swept_x:
    +copy16 QY, M_A
    +copy16 STEP_Y, M_B
    jsr swept_axis_near
    bcs circle_swept_y
    jmp circle_no_contact
circle_swept_y:
    lda STEP_SQUARE_VALID
    bne circle_square_ready
    +copy16 STEP_X, QX
    +copy16 STEP_Y, QY
    jsr square_q
    +copy32 M_PRODUCT, STEP_SQUARED
    lda #1
    sta STEP_SQUARE_VALID
circle_square_ready:
    +copy16 SAVED_X, QX
    +copy16 SAVED_Y, QY
    +copy16 QX, M_A
    +copy16 STEP_X, M_B
    jsr multiply_signed
    +copy32 M_PRODUCT, DX_WIDE
    +copy16 QY, M_A
    +copy16 STEP_Y, M_B
    jsr multiply_signed
    clc
    lda M_PRODUCT
    adc DX_WIDE
    sta M_PRODUCT
    lda M_PRODUCT + 1
    adc DX_WIDE + 1
    sta M_PRODUCT + 1
    lda M_PRODUCT + 2
    adc DX_WIDE + 2
    sta M_PRODUCT + 2
    lda M_PRODUCT + 3
    adc DX_WIDE + 3
    sta M_PRODUCT + 3
    bmi collision_branch_9
    jmp circle_no_contact
collision_branch_9:
    sec
    lda #0
    sbc M_PRODUCT
    sta M_REM
    lda #0
    sbc M_PRODUCT + 1
    sta M_REM + 1
    lda #0
    sbc M_PRODUCT + 2
    sta M_REM + 2
    +copy16 STEP_SQUARED, M_DEN
    lda STEP_SQUARED + 2
    sta M_DEN + 2
    lda M_REM + 2
    cmp M_DEN + 2
    bcc circle_closest_fraction
    bne circle_closest_end
    lda M_REM + 1
    cmp M_DEN + 1
    bcc circle_closest_fraction
    bne circle_closest_end
    lda M_REM
    cmp M_DEN
    bcc circle_closest_fraction
circle_closest_end:
    lda #255
    bne circle_closest_ready
circle_closest_fraction:
    jsr divide_fraction
    lda M_QUOT
circle_closest_ready:
    ldx HIT
    beq circle_prefix_ready
    cmp BEST_T
    bcc circle_prefix_ready
    lda BEST_T
circle_prefix_ready:
    sta BISECT_HI
    sta TRIAL_T
    jsr circle_at_trial
    bcs collision_branch_10
    jmp circle_no_contact
collision_branch_10:
    lda #0
    sta BISECT_LO
circle_bisect:
    lda BISECT_HI
    sec
    sbc BISECT_LO
    cmp #2
    bcc circle_entry
    lsr
    clc
    adc BISECT_LO
    sta TRIAL_T
    jsr circle_at_trial
    bcc circle_outside
    lda TRIAL_T
    sta BISECT_HI
    jmp circle_bisect
circle_outside:
    lda TRIAL_T
    sta BISECT_LO
    jmp circle_bisect
circle_entry:
    lda BISECT_LO
    sta TRIAL_T
    jsr circle_at_trial
    bcc circle_entry_outside
    lda BISECT_LO
    beq circle_entry_outside
    dec BISECT_LO
    jmp circle_entry
circle_entry_outside:
    +copy16 TRIAL_X, NX
    +copy16 TRIAL_Y, NY
    lda NX + 1
    asl
    ror NX + 1
    ror NX
    lda NY + 1
    asl
    ror NY + 1
    ror NY
    jmp record_contact
circle_no_contact:
    clc
    rts

incoming_normal:
    lda NORMAL_CODE
    and #2
    beq incoming_x
    +copy16 STEP_Y, DOT_STEP
    jmp incoming_axis_sign
incoming_x:
    +copy16 STEP_X, DOT_STEP
incoming_axis_sign:
    lda NORMAL_CODE
    and #1
    bne incoming_diagonal
    lda NORMAL_CODE
    and #4
    beq incoming_test
    +negate16 DOT_STEP
    jmp incoming_test
incoming_diagonal:
    +copy16 STEP_X, DOT_STEP
    lda NORMAL_CODE
    cmp #3
    beq incoming_negative_x
    cmp #5
    bne incoming_diagonal_y
incoming_negative_x:
    +negate16 DOT_STEP
incoming_diagonal_y:
    lda NORMAL_CODE
    cmp #5
    bcc incoming_positive_y
    +sub16 DOT_STEP, STEP_Y, DOT_STEP
    jmp incoming_test
incoming_positive_y:
    +add16 DOT_STEP, STEP_Y, DOT_STEP
incoming_test:
    lda DOT_STEP + 1
    bpl incoming_away
    sec
    rts
incoming_away:
    clc
    rts

; Axis-wall projection can be rejected in integer pixels before computing
; the exact fractional contact. A full frame travels at most 4 pixels.
axis_projection_near:
    lda NORMAL_CODE
    and #1
    bne axis_projection_possible
    ldy SEG_OFFSET
    lda NORMAL_CODE
    and #2
    beq axis_projection_y
    lda BALL_POS_X + 2
    lsr
    lda BALL_POS_X + 1
    ror
    sta M_A
    lda course_segments,y
    sta M_B
    lda course_segments + 2,y
    jmp axis_projection_range
axis_projection_y:
    lda BALL_POS_Y + 1
    lsr
    sta M_A
    lda course_segments + 1,y
    sta M_B
    lda course_segments + 3,y
axis_projection_range:
    cmp M_B
    bcs axis_projection_ordered
    tax
    lda M_B
    sta M_B + 1
    stx M_B
    jmp axis_projection_limits
axis_projection_ordered:
    sta M_B + 1
axis_projection_limits:
    lda M_A
    clc
    adc #3
    cmp M_B
    bcc axis_projection_impossible
    lda M_B + 1
    clc
    adc #3
    cmp M_A
    bcc axis_projection_impossible
axis_projection_possible:
    sec
    rts
axis_projection_impossible:
    clc
    rts

circle_motion_away:
    lda STEP_X
    ora STEP_X + 1
    beq circle_away_y
    lda SAVED_X
    ora SAVED_X + 1
    beq circle_away_y
    lda SAVED_X + 1
    eor STEP_X + 1
    bmi circle_approaching
circle_away_y:
    lda STEP_Y
    ora STEP_Y + 1
    beq circle_moving_away
    lda SAVED_Y
    ora SAVED_Y + 1
    beq circle_moving_away
    lda SAVED_Y + 1
    eor STEP_Y + 1
    bmi circle_approaching
circle_moving_away:
    sec
    rts
circle_approaching:
    clc
    rts

circle_at_trial:
    jsr displacement_at_t
    +add16 SAVED_X, TRIAL_X, TRIAL_X
    +add16 SAVED_Y, TRIAL_Y, TRIAL_Y
    +copy16 TRIAL_X, QX
    +copy16 TRIAL_Y, QY
    jsr square_q
compare_circle_radius:
    lda M_PRODUCT + 3
    cmp RADIUS_SQUARED + 3
    bcc circle_inside
    bne circle_outside_radius
    lda M_PRODUCT + 2
    cmp RADIUS_SQUARED + 2
    bcc circle_inside
    bne circle_outside_radius
    lda M_PRODUCT + 1
    cmp RADIUS_SQUARED + 1
    bcc circle_inside
    bne circle_outside_radius
    lda M_PRODUCT
    cmp RADIUS_SQUARED
    bcs circle_outside_radius
circle_inside:
    sec
    rts
circle_outside_radius:
    clc
    rts

; A swept AABB test for one circle axis. M_A = starting offset,
; M_B = displacement. C is set only when this interval can approach within
; the radius. This avoids multiplying distant or tangential corner data.
swept_axis_near:
    +add16 M_A, M_B, M_MULTIPLICAND
    lda RADIUS_SQUARED + 2
    cmp #9
    lda #2
    bcc swept_radius
    lda #3
swept_radius:
    sta M_COUNT
    lda M_A + 1
    bmi swept_negative
    cmp M_COUNT
    bcc swept_near
    lda M_MULTIPLICAND + 1
    bmi swept_near
    cmp M_COUNT
    bcc swept_near
    clc
    rts
swept_negative:
    +negate16 M_A
    lda M_A + 1
    cmp M_COUNT
    bcc swept_near
    lda M_MULTIPLICAND + 1
    bpl swept_near
    +negate16 M_MULTIPLICAND
    lda M_MULTIPLICAND + 1
    cmp M_COUNT
    bcc swept_near
    clc
    rts
swept_near:
    sec
    rts

record_contact:
    lda HIT
    beq contact_record
    lda TRIAL_T
    cmp BEST_T
    bcs contact_rejected
contact_record:
    lda TRIAL_T
    sta BEST_T
    +copy16 NX, BEST_NX
    +copy16 NY, BEST_NY
    lda #1
    sta HIT
    sec
    rts
contact_rejected:
    clc
    rts

test_cup:
    lda #0
    sta POINT_X
    sta POINT_Y
    lda #<CUP_X
    sta POINT_X + 1
    lda #>CUP_X
    sta POINT_X + 2
    lda #CUP_Y
    sta POINT_Y + 1
    lda #9                    ; (3 * 256)^2
    sta RADIUS_SQUARED + 2
    jsr try_circle
    bcc cup_not_caught
    lda #1
    sta FRAME_CUP
cup_not_caught:
    rts
