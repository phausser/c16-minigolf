reset_ball:
    lda #0
    sta BALL_POS_X
    sta BALL_POS_Y
    sta ROLLING
    sta HOLED
    sta SHOTS
    sta VELOCITY_X
    sta VELOCITY_X + 1
    sta VELOCITY_Y
    sta VELOCITY_Y + 1
    lda #<START_X
    sta BALL_POS_X + 1
    lda #>START_X
    sta BALL_POS_X + 2
    lda #START_Y
    sta BALL_POS_Y + 1
    lda #1
    sta DIRTY
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
    +negate16 M_A
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
    jmp velocity_from_unit

velocity_from_unit:
    +copy16 UNIT_X, M_A
    +copy16 SPEED, M_B
    jsr multiply_signed
    +copy16 M_PRODUCT + 1, VELOCITY_X
    +copy16 UNIT_Y, M_A
    +copy16 SPEED, M_B
    jsr multiply_signed
    +copy16 M_PRODUCT + 1, VELOCITY_Y
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
    jsr velocity_from_unit
    jsr collect_candidates
    ; A continuous finite-segment/circle sweep covers the whole frame path.
    ; Contacts split time, not pixels; no endpoint sampling or tunneling.
    lda #0
    sta SUBSTEP_SHIFT
    lda #1
    sta SUBSTEPS_LEFT
substeps_ready:
    lda #1
    sta DIRTY
    lda #0
    sta CONTACT_CHANGED
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
    beq physics_substep_done
    jsr find_first_contact
    ; Cup is another swept circle, considered only below catch speed.
    lda SPEED + 1
    bne physics_wall
    lda SPEED
    cmp #193
    bcs physics_wall
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
    +copy16 BEST_NX, NX
    +copy16 BEST_NY, NY
    jsr reflect_velocity
    lda #1
    sta CONTACT_CHANGED
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
    dec SUBSTEPS_LEFT
    beq physics_steps_finished
    jmp physics_substep
physics_steps_finished:
    lda CONTACT_CHANGED
    beq physics_no_normalization
    jsr normalize_velocity
physics_no_normalization:
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
    lda #2
    sta HUD_DIRTY
    rts

finish_hole:
    lda #0
    sta BALL_POS_X
    sta BALL_POS_Y
    lda #<CUP_X
    sta BALL_POS_X + 1
    lda #>CUP_X
    sta BALL_POS_X + 2
    lda #CUP_Y
    sta BALL_POS_Y + 1
    lda #1
    sta HOLED
    jsr stop_ball
    sta DIRTY
    rts

make_step:
    +copy16 VELOCITY_X, BASE_STEP_X
    +copy16 VELOCITY_Y, BASE_STEP_Y
    ldx SUBSTEP_SHIFT
    beq step_divided
step_shift:
    lda BASE_STEP_X + 1
    asl                     ; sign into carry for arithmetic shift
    ror BASE_STEP_X + 1
    ror BASE_STEP_X
    lda BASE_STEP_Y + 1
    asl
    ror BASE_STEP_Y + 1
    ror BASE_STEP_Y
    dex
    bne step_shift
step_divided:
    lda REMAINING_TIME + 1
    beq step_residual
    +copy16 BASE_STEP_X, STEP_X
    +copy16 BASE_STEP_Y, STEP_Y
    rts
step_residual:
    +copy16 BASE_STEP_X, M_A
    +copy16 REMAINING_TIME, M_B
    jsr multiply_fraction
    +copy16 M_PRODUCT + 1, STEP_X
    +copy16 BASE_STEP_Y, M_A
    +copy16 REMAINING_TIME, M_B
    jsr multiply_fraction
    +copy16 M_PRODUCT + 1, STEP_Y
    rts

displacement_at_t:
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
    +copy16 STEP_X, TRIAL_X
    +copy16 STEP_Y, TRIAL_Y
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

; Generic normal reflection, restitution 15/16. NX/NY unit Q1.8.
reflect_velocity:
    lda NX
    ora NX + 1
    bne reflect_check_x
    jmp reflect_axis_y
reflect_check_x:
    lda NY
    ora NY + 1
    bne reflect_general
    jmp reflect_axis_x
reflect_general:
    +copy16 VELOCITY_X, M_A
    +copy16 NX, M_B
    jsr multiply_signed
    +copy32 M_PRODUCT, STEP_SQUARED
    +copy16 VELOCITY_Y, M_A
    +copy16 NY, M_B
    jsr multiply_signed
    clc
    lda M_PRODUCT
    adc STEP_SQUARED
    lda M_PRODUCT + 1
    adc STEP_SQUARED + 1
    sta SAVED_DOT
    lda M_PRODUCT + 2
    adc STEP_SQUARED + 2
    sta SAVED_DOT + 1
    ; dot * 31/16 = dot*2 - dot/16; inward dot is negative.
    +copy16 SAVED_DOT, M_A
    ldx #4
reflect_loss:
    lda M_A + 1
    asl
    ror M_A + 1
    ror M_A
    dex
    bne reflect_loss
    asl SAVED_DOT
    rol SAVED_DOT + 1
    +sub16 SAVED_DOT, M_A, SAVED_DOT
    +copy16 SAVED_DOT, M_A
    +copy16 NX, M_B
    jsr multiply_signed
    +sub16 VELOCITY_X, M_PRODUCT + 1, VELOCITY_X
    +copy16 SAVED_DOT, M_A
    +copy16 NY, M_B
    jsr multiply_signed
    +sub16 VELOCITY_Y, M_PRODUCT + 1, VELOCITY_Y
    rts
reflect_axis_y:
    ldx #VELOCITY_Y
    bne reflect_axis
reflect_axis_x:
    ldx #VELOCITY_X
reflect_axis:
    lda 0,x
    sta M_A
    lda 1,x
    sta M_A + 1
    ldy #4
reflect_axis_loss:
    lda M_A + 1
    asl
    ror M_A + 1
    ror M_A
    dey
    bne reflect_axis_loss
    sec
    lda #0
    sbc 0,x
    sta 0,x
    lda #0
    sbc 1,x
    sta 1,x
    clc
    lda 0,x
    adc M_A
    sta 0,x
    lda 1,x
    adc M_A + 1
    sta 1,x
    rts

normalize_velocity:
    lda VELOCITY_X
    ora VELOCITY_X + 1
    beq normalize_vertical
    lda VELOCITY_Y
    ora VELOCITY_Y + 1
    beq normalize_horizontal
    +copy16 VELOCITY_X, QX
    +copy16 VELOCITY_Y, QY
    jsr square_q
    jsr sqrt_u32
    +copy16 M_QUOT, SPEED
    lda SPEED
    ora SPEED + 1
    beq normalize_done
    +copy16 VELOCITY_X, M_A
    jsr normalize_component
    +copy16 M_QUOT, UNIT_X
    +copy16 VELOCITY_Y, M_A
    jsr normalize_component
    +copy16 M_QUOT, UNIT_Y
normalize_done:
    rts
normalize_vertical:
    +copy16 VELOCITY_Y, SPEED
    lda #0
    sta UNIT_X
    sta UNIT_X + 1
    sta UNIT_Y
    lda #1
    sta UNIT_Y + 1
    lda SPEED + 1
    bpl normalize_done
    +negate16 SPEED
    lda #$ff
    sta UNIT_Y + 1
    rts
normalize_horizontal:
    +copy16 VELOCITY_X, SPEED
    lda #0
    sta UNIT_Y
    sta UNIT_Y + 1
    sta UNIT_X
    lda #1
    sta UNIT_X + 1
    lda SPEED + 1
    bpl normalize_done
    +negate16 SPEED
    lda #$ff
    sta UNIT_X + 1
    rts

normalize_component:
    lda M_A + 1
    sta M_SIGN
    bpl normalize_positive
    +negate16 M_A
normalize_positive:
    +copy16 M_A, M_REM
    +copy16 SPEED, M_DEN
    lda #0
    sta M_REM + 2
    sta M_DEN + 2
    lda M_REM
    cmp M_DEN
    bne normalize_fraction
    lda M_REM + 1
    cmp M_DEN + 1
    bne normalize_fraction
    lda #0
    sta M_QUOT
    lda #1
    sta M_QUOT + 1
    bne normalize_sign
normalize_fraction:
    jsr divide_fraction
normalize_sign:
    lda M_SIGN
    bpl normalize_return
    +negate16 M_QUOT
normalize_return:
    rts
