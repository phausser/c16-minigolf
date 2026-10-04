; Joystick port 1: $FF08 selector $FB, active-low left/right bits 2/3,
; fire bit 6. Keyboard rows stay released while reading the joystick.
; P is read separately with both joystick ports deselected.
scan_keyboard:
    lda #$ff
    sta KEYBOARD_ROW
    lda #$fb
    sta TED_KEYBOARD
    lda TED_KEYBOARD
    eor #$ff
    sta TEMP
    and #12
    lsr
    lsr
    sta KEY_CURRENT
    lda TEMP
    and #$40
    lsr
    ora KEY_CURRENT
    sta KEY_CURRENT
    lda #$df
    sta KEYBOARD_ROW
    lda #$ff
    sta TED_KEYBOARD
    lda TED_KEYBOARD
    and #2
    bne scan_release_rows
    lda KEY_CURRENT
    ora #KEY_PAUSE
    sta KEY_CURRENT
scan_release_rows:
    lda #$ff
    sta KEYBOARD_ROW
    sta TED_KEYBOARD
    rts

; Two equal samples accept a transition. Rotation repeats after 15 frames,
; then every 3 frames. Fire uses the accepted held state, not key repeat.
debounce_keyboard:
    lda #0
    sta KEY_ACTIONS
    lda KEY_CURRENT
    cmp KEY_CANDIDATE
    beq debounce_stable
    sta KEY_CANDIDATE
    lda #1
    sta KEY_DEBOUNCE
    rts
debounce_stable:
    lda KEY_DEBOUNCE
    beq debounce_repeat
    dec KEY_DEBOUNCE
    lda KEY_PREVIOUS
    eor #$ff
    and KEY_CANDIDATE
    sta KEY_ACTIONS
    lda KEY_CANDIDATE
    sta KEY_PREVIOUS
    lda #15
    sta KEY_REPEAT
    rts
debounce_repeat:
    lda KEY_PREVIOUS
    and #3
    beq debounce_done
    dec KEY_REPEAT
    bne debounce_done
    sta KEY_ACTIONS
    lda #3
    sta KEY_REPEAT
debounce_done:
    rts

apply_controls:
    lda KEY_ACTIONS
    and #KEY_PAUSE
    beq control_check_blocked
    lda PAUSED
    eor #1
    sta PAUSED
    lda #1
    sta DIRTY
    jsr cancel_charge
control_check_blocked:
    lda PAUSED
    ora ROLLING
    beq control_fire
    jmp cancel_charge
control_fire:
    lda KEY_PREVIOUS
    and #KEY_SHOT
    bne control_held
    lda #0
    sta FIRE_LOCK
    lda CHARGING
    beq control_direction
    lda #0
    sta CHARGING
    jsr start_shot
    lda #0
    sta POWER
    lda #1
    sta HUD_DIRTY
    sta DIRTY
    rts
control_held:
    lda FIRE_LOCK
    bne controls_done
    lda HOLED
    beq control_charge
    jsr reset_ball
    rts
control_charge:
    lda CHARGING
    bne control_charge_tick
    lda #1
    sta CHARGING
    sta POWER
    lda #2
    sta CHARGE_TICKS
    bne controls_hud_dirty
control_charge_tick:
    lda POWER
    cmp #32
    beq control_direction
    dec CHARGE_TICKS
    bne control_direction
    lda #2
    sta CHARGE_TICKS
    inc POWER
controls_hud_dirty:
    lda #1
    sta HUD_DIRTY
control_direction:
    lda KEY_ACTIONS
    and #3
    cmp #KEY_LEFT
    beq control_left
    cmp #KEY_RIGHT
    bne controls_done
    inc ANGLE
    jmp control_wrap
control_left:
    dec ANGLE
control_wrap:
    lda ANGLE
    and #127
    sta ANGLE
    lda #1
    sta DIRTY
controls_done:
    rts

cancel_charge:
    lda #1
    sta FIRE_LOCK
    lda CHARGING
    beq controls_done
    lda #0
    sta CHARGING
    sta POWER
    lda #1
    sta HUD_DIRTY
    rts
