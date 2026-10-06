ball_screen_position:
    lda BALL_POS_X
    cmp #128
    lda BALL_POS_X + 1
    adc #0
    sta BALL_SCREEN_X
    lda BALL_POS_X + 2
    adc #0
    sta BALL_SCREEN_X + 1
    lda BALL_POS_Y
    cmp #128
    lda BALL_POS_Y + 1
    adc #0
    sta BALL_SCREEN_Y
    rts

; 33-entry quarter wave, Q1.8. A is angle 0..127; output is M_A.
cosine_unit:
    and #127
    sta PHYS_INDEX
    and #31
    tax
    lda PHYS_INDEX
    and #32
    beq cosine_index
    stx M_COUNT
    lda #32
    sec
    sbc M_COUNT
    tax
cosine_index:
    lda unit_cos_lo,x
    sta M_A
    lda unit_cos_hi,x
    sta M_A + 1
    lda PHYS_INDEX
    clc
    adc #32
    and #64
    beq cosine_done
    jsr negate_math_a
cosine_done:
    rts

start_shot:
    lda ANGLE
    jsr cosine_unit
    +copy16 M_A, UNIT_X
    lda ANGLE
    sec
    sbc #32
    jsr cosine_unit
    +copy16 M_A, UNIT_Y
    lda POWER
    sta SPEED
    lda #0
    sta SPEED + 1
    ldx #5
shot_speed:
    asl SPEED
    rol SPEED + 1
    dex
    bne shot_speed
    inc SHOTS
    lda #1
    sta ROLLING
    lda #2
    sta HUD_DIRTY
    ldx #SOUND_SHOT           ; physics_tick derives VELOCITY in this frame
    jmp play_sound

; VELOCITY = round(SPEED * UNIT / 256) per axis: rounding to the nearest
; Q8.8 unit (not floor) keeps opposite directions symmetric.
; Y = 2 (y component), then 0 (x); the multiplies preserve Y.
velocity_from_unit:
    ldy #2
velocity_axis:
    +copy16 SPEED, M_A
    lda UNIT_X,y
    sta M_B
    lda UNIT_X + 1,y
    sta M_B + 1
    jsr multiply_unit
    lda M_PRODUCT
    cmp #$80                  ; carry = round half up
    lda M_PRODUCT + 1
    adc #0
    sta VELOCITY_X,y
    lda M_PRODUCT + 2
    adc #0
    sta VELOCITY_X + 1,y
    dey
    dey
    bpl velocity_axis
    rts

physics_tick:
    lda PAUSED
    ora HOLED
    bne physics_rest
    lda ROLLING
    bne physics_branch_2
physics_rest:
    rts
physics_branch_2:
    lda HAZARD_COUNT
    beq physics_dry_course
    ldx #4
physics_save_start:
    lda BALL_POS_X,x
    sta FRAME_START,x
    dex
    bpl physics_save_start
physics_dry_course:
    jsr velocity_from_unit
    jsr collect_candidates
    ; A continuous finite-segment/circle sweep covers the whole frame path.
    ; Contacts split time, not pixels; no endpoint sampling or tunneling.
    lda #1
    sta DIRTY
physics_substep:
    lda #0
    sta REMAINING_TIME
    lda #1
    sta REMAINING_TIME + 1
    lda #MAX_CONTACTS
    sta CONTACTS_LEFT
physics_remainder:
    jsr make_step
    lda STEP_X
    ora STEP_X + 1
    ora STEP_Y
    ora STEP_Y + 1
    bne physics_has_step
    jmp physics_substep_done
physics_has_step:
    jsr find_first_contact
    ; Cup is another swept circle; try_circle's packed bounds reject it
    ; cheaply when far away, considered only below catch speed.
    ; reflect_unit updates SPEED at once, so it is current after a bounce.
    lda SPEED + 1
    bne physics_wall
    lda SPEED
    cmp #193
    bcs physics_wall
physics_cup_ready:
    jsr test_cup
    lda FRAME_CUP
    beq physics_wall
    jmp finish_hole
physics_wall:
    lda HIT
    bne physics_hit
    jsr accept_full_step
    jmp physics_substep_done
physics_hit:
    lda BEST_MOVE
    sta TRIAL_T
    jsr displacement_at_t
    jsr accept_trial
    ldx #SOUND_WALL
    jsr play_sound
    ldx #3
physics_best_normal:
    lda BEST_NX,x
    sta NX,x
    dex
    bpl physics_best_normal
    lda BEST_VERTEX
    beq physics_face
    jsr vertex_normal
    jmp physics_reflect
physics_face:
    ldx BEST_TIE
    beq physics_reflect
    lda joint_normal_x_lo - 1,x
    sta NX
    lda joint_normal_x_hi - 1,x
    sta NX + 1
    lda joint_normal_y_lo - 1,x
    sta NY
    lda joint_normal_y_hi - 1,x
    sta NY + 1
physics_reflect:
    jsr reflect_unit
    ; residual time *= (256 - contact fraction) / 256
    lda BEST_MOVE
    beq physics_time_unchanged
    +copy16 REMAINING_TIME, M_A
    lda #0
    sec
    sbc BEST_MOVE
    sta M_B
    jsr multiply_fraction
    +copy16 M_PRODUCT + 1, REMAINING_TIME
physics_time_unchanged:
    dec CONTACTS_LEFT
    beq physics_contact_limit
    jmp physics_remainder
physics_contact_limit:
    inc CONTACT_LIMIT_HITS
physics_substep_done:
physics_steps_finished:
    ; Water: foreground hue of the cell under the ball centre. The ball goes
    ; back to where this frame began, at most 4 pixels from the edge, and rests.
    lda HAZARD_COUNT
    beq physics_dry
    lda BALL_POS_Y + 1
    lsr
    lsr
    lsr
    jsr class_row_pointer
    lda BALL_POS_X + 2
    lsr
    lda BALL_POS_X + 1
    ror
    lsr
    lsr
    tay
    lda (COURSE_PTR),y
    and #15
    cmp #WATER_HUE
    bne physics_dry
    jsr ashore
    inc SHOTS                 ; one penalty stroke; the stroke limit below applies
    jsr stop_ball
    ldx #SOUND_WATER
    jmp play_sound
physics_dry:
    jsr cup_rim
    ; Constant radial resistance preserves the unit direction. There is
    ; no independent x/y braking and no asymptotic never-ending creep.
    lda SPEED + 1
    bne physics_brake
    lda SPEED
    cmp #ROLL_DECEL + 1
    bcc stop_ball
physics_brake:
    sec
    lda SPEED
    sbc #ROLL_DECEL
    sta SPEED
    lda SPEED + 1
    sbc #0
    sta SPEED + 1
physics_idle:
    rts
stop_ball:
    lda #0
    sta SPEED
    sta SPEED + 1
    sta VELOCITY_X
    sta VELOCITY_X + 1
    sta VELOCITY_Y
    sta VELOCITY_Y + 1
    sta ROLLING
    ; After 12 strokes without holing, the hole counts 13 and ends.
    lda SHOTS
    cmp #12
    bcc stop_status
    lda HOLED
    bne stop_status
    lda #13
    sta SHOTS
    sta HOLED
stop_status:
    lda #2
    sta HUD_DIRTY
    ; Fall through: the next stroke starts aimed at the cup.

; ANGLE = round(atan2(cup - ball) * 64 / pi) from the rounded pixel
; positions: |dy|/|dx| within one octant against 16 tangent thresholds.
aim_at_cup:
    lda HOLED
    bne aim_cup_done
    jsr ball_screen_position
    sec
    lda COURSE_CUP_X
    sbc BALL_SCREEN_X
    sta QX
    lda COURSE_CUP_X_HI
    sbc BALL_SCREEN_X + 1
    sta QX + 1
    sec
    lda COURSE_CUP_Y
    sbc BALL_SCREEN_Y
    sta QY
    lda #0
    sbc #0
    sta QY + 1
    ldx #2                    ; DX_WIDE = |dx|, DX_WIDE + 2 = |dy|
aim_abs:
    lda QX,x
    sta DX_WIDE,x
    lda QX + 1,x
    sta DX_WIDE + 1,x
    bpl aim_abs_next
    sec
    lda #0
    sbc DX_WIDE,x
    sta DX_WIDE,x
    lda #0
    sbc DX_WIDE + 1,x
    sta DX_WIDE + 1,x
aim_abs_next:
    dex
    dex
    bpl aim_abs
    lda DX_WIDE
    cmp DX_WIDE + 2
    lda DX_WIDE + 1
    sbc DX_WIDE + 3
    bcc aim_steep
    lda DX_WIDE
    ora DX_WIDE + 1
    beq aim_cup_done          ; on the cup centre: keep the angle
    ldx #2                    ; |dy| / |dx|
    ldy #0
    jsr aim_octant
    jmp aim_quadrant
aim_steep:
    ldx #0                    ; |dx| / |dy|
    ldy #2
    jsr aim_octant
    sta TEMP
    lda #32
    sec
    sbc TEMP
aim_quadrant:
    bit QX + 1
    bpl aim_right
    sta TEMP
    lda #64
    sec
    sbc TEMP
aim_right:
    bit QY + 1
    bpl aim_store
    eor #$ff
    clc
    adc #1
aim_store:
    and #127
    sta ANGLE
aim_cup_done:
    rts

; A = round(atan(n / d) * 64 / pi) for n = DX_WIDE + X <= d = DX_WIDE + Y.
aim_octant:
    lda DX_WIDE,x
    sta M_REM
    cmp DX_WIDE,y
    lda DX_WIDE + 1,x
    sta M_REM + 1
    sbc DX_WIDE + 1,y
    bcs aim_diagonal          ; n = d
    lda DX_WIDE,y
    sta M_DEN
    lda DX_WIDE + 1,y
    sta M_DEN + 1
    lda #0
    sta M_REM + 2
    sta M_DEN + 2
    jsr divide_fraction       ; M_QUOT = floor(256 * n / d)
    ldx #0
aim_count:
    lda M_QUOT
    cmp aim_tangents,x
    bcc aim_counted
    inx
    cpx #16
    bne aim_count
aim_counted:
    txa
    rts
aim_diagonal:
    lda #16
    rts

; ceil(256 * tan((j - 0.5) * pi / 64)), j = 1..16
aim_tangents:
!byte 7,19,32,45,58,71,85,99,114,129,146,163,181,200,221,244

; Back ashore from the water cell the ball centre ended in: on each axis
; whose cell boundary this frame crossed, three free pixels lie between the
; ball (centre +-2) and the water; otherwise the frame start coordinate
; stays. A frame moves at most 4 px, so the crossing is one cell.
ashore:
    jsr ball_cell_x
    sta M_A                   ; water cell
    lda BALL_POS_Y + 1
    lsr
    lsr
    lsr
    sta M_A + 1
    ldx #4
ashore_restore:
    lda FRAME_START,x
    sta BALL_POS_X,x
    dex
    bpl ashore_restore
    jsr ball_cell_x
    cmp M_A
    beq ashore_y
    bcc ashore_right
    jsr cell_times_8          ; water on the left: x = start cell * 8 + 5
    clc
    lda M_B
    adc #5
    sta BALL_POS_X + 1
    lda M_B + 1
    adc #0
    jmp ashore_x_store
ashore_right:
    lda M_A                   ; water on the right: x = water cell * 8 - 6
    jsr cell_times_8
    sec
    lda M_B
    sbc #6
    sta BALL_POS_X + 1
    lda M_B + 1
    sbc #0
ashore_x_store:
    sta BALL_POS_X + 2
    lda #0
    sta BALL_POS_X
ashore_y:
    lda BALL_POS_Y + 1
    lsr
    lsr
    lsr
    cmp M_A + 1
    beq ashore_done
    bcc ashore_down
    asl                       ; water above: y = start cell * 8 + 5
    asl
    asl
    adc #5                    ; carry clear from the shifts (y < 256)
    bne ashore_y_store
ashore_down:
    lda M_A + 1               ; water below: y = water cell * 8 - 6
    asl
    asl
    asl
    sbc #6 - 1                ; carry clear from the shifts: subtracts 6
ashore_y_store:
    sta BALL_POS_Y + 1
    lda #0
    sta BALL_POS_Y
ashore_done:
    rts

; A = column of the cell under the ball centre, 0..39.
ball_cell_x:
    lda BALL_POS_X + 2
    lsr
    lda BALL_POS_X + 1
    ror
    lsr
    lsr
    rts

; M_B = A * 8.
cell_times_8:
    ldx #0
    stx M_B + 1
    asl
    rol M_B + 1
    asl
    rol M_B + 1
    asl
    rol M_B + 1
    sta M_B
    rts

; Cup rim: while the ball overlaps the cup (centre within 5.5 px of it)
; without being caught, its direction turns about 0.9 degrees per frame
; towards the cup centre: a ball passing left of the cup bends right.
; Slow balls stay longer on the rim and curl more; a ball over the
; centre line goes straight. Rim drag SPEED/128 + 1 outweighs the unit
; rounding of the turn (< 0.3 %), so the rim never adds speed.
; Frames with a wall contact skip the rim: the two worst costs never add.
rim_far:
    rts
cup_rim:
    lda CONTACTS_LEFT
    cmp #MAX_CONTACTS
    bne rim_far
    sec
    lda BALL_POS_X + 1
    sbc COURSE_CUP_X
    tax
    lda BALL_POS_X + 2
    sbc COURSE_CUP_X_HI
    beq rim_x_positive
    cmp #$ff
    bne rim_far
    cpx #$fa
    bcc rim_far
    bcs rim_x_ready
rim_x_positive:
    cpx #6
    bcs rim_far
rim_x_ready:
    stx QX + 1                ; QX/QY = ball - cup, Q8.8, |q| < 6 px
    lda BALL_POS_X
    sta QX
    sec
    lda BALL_POS_Y + 1
    sbc COURSE_CUP_Y
    cmp #6
    bcc rim_y_ready
    cmp #$fa
    bcc rim_far
rim_y_ready:
    sta QY + 1
    lda BALL_POS_Y
    sta QY
    jsr square_q              ; d^2 in Q16.16, below 72 px^2
    lda M_PRODUCT + 2
    cmp #$1e                  ; 5.5^2 = $1e.40
    bcc rim_inside
    bne rim_far
    lda M_PRODUCT + 1
    cmp #$40
    bcs rim_far
rim_inside:
    ; s = ux*qy - uy*qx; its sign tells on which side the cup lies.
    +copy16 QY, M_A
    +copy16 UNIT_X, M_B
    jsr multiply_unit
    +copy32 M_PRODUCT, DX_WIDE
    +copy16 QX, M_A
    +copy16 UNIT_Y, M_B
    jsr multiply_unit
    sec
    lda DX_WIDE
    sbc M_PRODUCT
    sta DX_WIDE
    lda DX_WIDE + 1
    sbc M_PRODUCT + 1
    sta DX_WIDE + 1
    lda DX_WIDE + 2
    sbc M_PRODUCT + 2
    sta DX_WIDE + 2
    lda DX_WIDE + 3
    sbc M_PRODUCT + 3
    sta DX_WIDE + 3
    ora DX_WIDE
    ora DX_WIDE + 1
    ora DX_WIDE + 2
    beq rim_drag              ; heading straight over the centre
    ; Turn by 1/64 rad: s < 0 gives u += (-uy, ux)/64, s > 0 the opposite.
    lda UNIT_Y
    ldx UNIT_Y + 1
    jsr rim_share
    sta M_A
    lda UNIT_X
    ldx UNIT_X + 1
    jsr rim_share
    sta M_B
    lda DX_WIDE + 3
    bmi rim_turn_left
    lda #0
    sec
    sbc M_B
    sta M_B
    jmp rim_turn
rim_turn_left:
    lda #0
    sec
    sbc M_A
    sta M_A
rim_turn:
    ldx #0
    lda M_A
    jsr rim_add
    ldx #2
    lda M_B
    jsr rim_add
rim_drag:
    lda SPEED
    asl
    lda SPEED + 1
    rol
    sta TEMP                  ; SPEED / 128
    clc                       ; borrow: one more
    lda SPEED
    sbc TEMP
    sta SPEED
    lda SPEED + 1
    sbc #0
    sta SPEED + 1
    bcs rim_none
    lda #0
    sta SPEED
    sta SPEED + 1
rim_none:
    rts

; A = round(v / 64) for the unit component v = X:A, |v| <= 288.
rim_share:
    sta M_REM
    stx M_REM + 1
    txa
    php
    bpl rim_share_positive
    +negate16 M_REM
rim_share_positive:
    clc
    lda M_REM
    adc #32
    sta M_REM
    lda M_REM + 1
    adc #0
    asl M_REM
    rol
    asl M_REM
    rol
    plp
    bpl rim_share_done
    eor #$ff
    clc
    adc #1
rim_share_done:
    rts

; UNIT_X + X += sign-extended A.
rim_add:
    ldy #0
    ora #0
    bpl rim_add_positive
    dey
rim_add_positive:
    clc
    adc UNIT_X,x
    sta UNIT_X,x
    tya
    adc UNIT_X + 1,x
    sta UNIT_X + 1,x
    ; Keep |component| <= 256: multiply_unit requires it.
    bmi rim_add_negative
    cmp #1
    bcc rim_add_done          ; 0..255
    lda #0
    sta UNIT_X,x
    lda #1
    bne rim_add_clamp
rim_add_negative:
    cmp #$ff
    beq rim_add_done          ; -256..-1
    lda #0
    sta UNIT_X,x
    lda #$ff
rim_add_clamp:
    sta UNIT_X + 1,x
rim_add_done:
    rts

finish_hole:
    lda #0
    sta BALL_POS_X
    sta BALL_POS_Y
    lda COURSE_CUP_X
    sta BALL_POS_X + 1
    lda COURSE_CUP_X_HI
    sta BALL_POS_X + 2
    lda COURSE_CUP_Y
    sta BALL_POS_Y + 1
    lda #1
    sta HOLED
    jsr stop_ball
    sta DIRTY
    ldx #SOUND_CUP
    lda SHOTS
    cmp #1
    bne finish_sound
    ldx #SOUND_ACE            ; hole in one
finish_sound:
    jmp play_sound

make_step:
    ldx #3
    lda REMAINING_TIME + 1
    beq step_residual
step_full:
    lda VELOCITY_X,x
    sta STEP_X,x
    dex
    bpl step_full
    rts
step_residual:
    ; STEP = VELOCITY * REMAINING_TIME / 256 truncated towards zero, y then
    ; x. Flooring would turn a tiny remainder of a negative component into
    ; -1/256 and fake an approach to the wall just left.
    ldy #2
step_axis:
    lda VELOCITY_X,y
    sta M_A
    lda VELOCITY_X + 1,y
    sta M_A + 1
    lda REMAINING_TIME
    sta M_B
    jsr multiply_fraction
    lda M_PRODUCT + 2
    bpl step_truncated
    lda M_PRODUCT
    beq step_truncated        ; exact: floor is the truncation
    inc M_PRODUCT + 1
    bne step_truncated
    inc M_PRODUCT + 2
step_truncated:
    lda M_PRODUCT + 1
    sta STEP_X,y
    lda M_PRODUCT + 2
    sta STEP_X + 1,y
    dey
    dey
    bpl step_axis
    rts

displacement_at_t:
    ; Unrolled: called for every contact and bisection trial.
    +copy16 STEP_X, M_A
    lda TRIAL_T
    sta M_B
    jsr multiply_fraction
    +copy16 M_PRODUCT + 1, TRIAL_X
    +copy16 STEP_Y, M_A
    lda TRIAL_T
    sta M_B
    jsr multiply_fraction
    +copy16 M_PRODUCT + 1, TRIAL_Y
    rts

accept_full_step:
    ldx #3
accept_copy:
    lda STEP_X,x
    sta TRIAL_X,x
    dex
    bpl accept_copy
accept_trial:
    clc
    lda BALL_POS_X
    adc TRIAL_X
    sta BALL_POS_X
    lda BALL_POS_X + 1
    adc TRIAL_X + 1
    sta BALL_POS_X + 1
    lda TRIAL_X + 1
    bpl accept_x_positive
    lda #$ff
    bne accept_x_high
accept_x_positive:
    lda #0
accept_x_high:
    adc BALL_POS_X + 2
    sta BALL_POS_X + 2
    +add16 BALL_POS_Y, TRIAL_Y, BALL_POS_Y
    rts

; Mirror UNIT about the contact normal and take the restitution loss from
; SPEED: e = 15/16 on the normal share gives |v'|/|v| ~= 1 - d^2 * 31/512
; with d = u.n, plus a small contact friction. Axis and 45-degree walls
; mirror UNIT and VELOCITY exactly; the frame remainder keeps the old speed
; there, the next tick rebuilds VELOCITY from SPEED. Corner normals have
; |n| <= 1, so |u| never grows; components are clamped to +/-256.
reflect_unit:
    lda NY
    ora NY + 1
    beq reflect_axis_x
    lda NX
    ora NX + 1
    bne reflect_not_axis
    ldx #2
    bne reflect_axis
reflect_axis_x:
    ldx #0
reflect_axis:
    lda UNIT_X,x
    sta M_A
    lda UNIT_X + 1,x
    sta M_A + 1
    jsr negate_vector_x
    txa
    clc
    adc #UNIT_X - VELOCITY_X
    tax
    jsr negate_vector_x
    jsr square_small          ; d^2 = u^2 / 256
    +copy16 M_PRODUCT + 1, M_B
    jmp reflect_speed_loss
reflect_not_axis:
    ldx #2
reflect_diagonal_check:
    lda NX,x
    ldy NX + 1,x
    bmi reflect_check_negative
    cmp #181
    bne reflect_general
    cpy #0
    bne reflect_general
    beq reflect_check_next
reflect_check_negative:
    cmp #<-181
    bne reflect_general
reflect_check_next:
    dex
    dex
    bpl reflect_diagonal_check
    jmp reflect_diagonal
reflect_general:
    +copy16 NX, M_A
    +copy16 UNIT_X, M_B
    jsr multiply_unit
    +copy32 M_PRODUCT, DX_WIDE
    +copy16 NY, M_A
    +copy16 UNIT_Y, M_B
    jsr multiply_unit
    clc
    lda M_PRODUCT
    adc DX_WIDE
    lda M_PRODUCT + 1
    adc DX_WIDE + 1
    sta SAVED_DOT
    lda M_PRODUCT + 2
    adc DX_WIDE + 2
    sta SAVED_DOT + 1
    ldx #0
reflect_component:
    ; u -= floor(2 * d * n / 256), first x (X = 0), then y (X = 2).
    stx REFLECT_INDEX
    lda SAVED_DOT
    asl
    sta M_A
    lda SAVED_DOT + 1
    rol
    sta M_A + 1
    lda NX,x
    sta M_B
    lda NX + 1,x
    sta M_B + 1
    jsr multiply_unit
    ldx REFLECT_INDEX
    sec
    lda UNIT_X,x
    sbc M_PRODUCT + 1
    sta UNIT_X,x
    lda UNIT_X + 1,x
    sbc M_PRODUCT + 2
    sta UNIT_X + 1,x
    bmi reflect_negative
    cmp #1
    bcc reflect_clamped       ; 0..255
    lda #0                    ; >= 256 becomes exactly 256
    sta UNIT_X,x
    lda #1
    bne reflect_clamp_store
reflect_negative:
    cmp #$ff
    beq reflect_clamped       ; -256..-1
    lda #0                    ; < -256 becomes exactly -256
    sta UNIT_X,x
    lda #$ff
reflect_clamp_store:
    sta UNIT_X + 1,x
reflect_clamped:
    inx
    inx
    cpx #4
    bne reflect_component
    +copy16 SAVED_DOT, M_A
    jsr square_small          ; d^2 = dot^2 / 256
    +copy16 M_PRODUCT + 1, M_B
    jsr reflect_speed_loss
    jmp velocity_from_unit

reflect_diagonal:
    ; n = (sx, sy)/sqrt(2), p = sx*sy: u' = -p * (uy, ux).
    lda NX + 1
    eor NY + 1
    sta SAVED_SPEED
    bmi reflect_diagonal_difference
    +add16 UNIT_X, UNIT_Y, M_A
    jmp reflect_diagonal_swap
reflect_diagonal_difference:
    +sub16 UNIT_X, UNIT_Y, M_A
reflect_diagonal_swap:
    ldx #UNIT_X - VELOCITY_X
reflect_diagonal_vector:
    lda VELOCITY_X,x
    ldy VELOCITY_Y,x
    sta VELOCITY_Y,x
    sty VELOCITY_X,x
    lda VELOCITY_X + 1,x
    ldy VELOCITY_Y + 1,x
    sta VELOCITY_Y + 1,x
    sty VELOCITY_X + 1,x
    bit SAVED_SPEED
    bmi reflect_diagonal_next
    jsr negate_vector_x
    inx
    inx
    jsr negate_vector_x
    dex
    dex
reflect_diagonal_next:
    txa
    sec
    sbc #UNIT_X - VELOCITY_X
    tax
    bcs reflect_diagonal_vector
    ; d^2 = (ux +/- uy)^2 / 2 in Q1.8: square / 512.
    jsr square_small
    lda M_PRODUCT + 2
    lsr
    sta M_B + 1
    lda M_PRODUCT + 1
    ror
    sta M_B
    jmp reflect_speed_loss

; M_B = d^2 in Q1.8: SPEED -= SPEED * d^2 * 31/512 + SPEED/128 + 1.
reflect_speed_loss:
    +copy16 SPEED, M_A
    jsr multiply_unit
    lda M_PRODUCT + 2
    lsr
    sta TEMP
    lda M_PRODUCT + 1
    ldx #4
reflect_loss:
    lsr M_PRODUCT + 2
    ror
    dex
    bne reflect_loss
    sec
    sbc TEMP
    sta TEMP
    ; Contact friction SPEED/128 + 1 outweighs unit rounding (< 0.5%),
    ; so even grazing contacts never gain speed.
    lda SPEED
    asl
    lda SPEED + 1
    rol
    sec
    adc TEMP
    sta TEMP
    sec
    lda SPEED
    sbc TEMP
    sta SPEED
    lda SPEED + 1
    sbc #0
    sta SPEED + 1
    rts

; Negate the word at VELOCITY_X + X.
negate_vector_x:
    sec
    lda #0
    sbc VELOCITY_X,x
    sta VELOCITY_X,x
    lda #0
    sbc VELOCITY_X + 1,x
    sta VELOCITY_X + 1,x
    rts
