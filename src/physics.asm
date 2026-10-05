reset_ball:
    lda #0
    sta BALL_POS_X
    sta BALL_POS_Y
    sta ROLLING
    sta HOLED
    sta SHOTS
    sta CHARGING
    sta CHARGE_TICKS
    sta POWER
    sta VELOCITY_X
    sta VELOCITY_X + 1
    sta VELOCITY_Y
    sta VELOCITY_Y + 1
    lda COURSE_START_X
    sta BALL_POS_X + 1
    lda COURSE_START_X_HI
    sta BALL_POS_X + 2
    lda COURSE_START_Y
    sta BALL_POS_Y + 1
    lda #1
    sta FIRE_LOCK
    sta DIRTY
    lda #3
    sta HUD_DIRTY
    rts

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
    rts                       ; physics_tick derives VELOCITY in this frame

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
    lda M_PRODUCT + 1
    sta VELOCITY_X,y
    lda M_PRODUCT + 2
    sta VELOCITY_X + 1,y
    dey
    dey
    bpl velocity_axis
    rts

physics_tick:
    lda PAUSED
    ora HOLED
    beq physics_branch_1
    jmp physics_idle
physics_branch_1:
    lda ROLLING
    bne physics_branch_2
    jmp physics_idle
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
    lda BEST_T
    sta TRIAL_T
    jsr displacement_at_t
    jsr accept_trial
    ldx #3
physics_best_normal:
    lda BEST_NX,x
    sta NX,x
    dex
    bpl physics_best_normal
    jsr reflect_unit
    ; residual time *= (256 - contact fraction) / 256
    lda BEST_T
    beq physics_time_unchanged
    +copy16 REMAINING_TIME, M_A
    lda #0
    sec
    sbc BEST_T
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
    ; Water: when the ball centre ends a frame in a blue cell, it goes back
    ; to where this frame began, at most 4 pixels from the edge, and rests.
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
    ldx #4
physics_ashore:
    lda FRAME_START,x
    sta BALL_POS_X,x
    dex
    bpl physics_ashore
    jmp stop_ball
physics_dry:
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
    rts

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
    ; STEP = floor(VELOCITY * REMAINING_TIME / 256), y then x.
    ldy #2
step_axis:
    lda VELOCITY_X,y
    sta M_A
    lda VELOCITY_X + 1,y
    sta M_A + 1
    lda REMAINING_TIME
    sta M_B
    jsr multiply_fraction
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
