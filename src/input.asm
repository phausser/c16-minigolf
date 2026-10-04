; C16 matrix: A=(1,2), D=(2,2), W=(1,1), S=(1,5), P=(5,1).
; Verified against VICE PLUS4/gtk3_sym.vkm. $FD30 drives active-low rows;
; writing $FF08 latches columns, it does not drive the 6529 row port.
scan_keyboard:
    lda #0
    sta KEY_CURRENT
    lda #$fd
    jsr latch_row
    sta TEMP
    and #4
    bne scan_w
    lda KEY_CURRENT
    ora #KEY_LEFT
    sta KEY_CURRENT
scan_w:
    lda TEMP
    and #2
    bne scan_s
    lda KEY_CURRENT
    ora #KEY_UP
    sta KEY_CURRENT
scan_s:
    lda TEMP
    and #$20
    bne scan_d
    lda KEY_CURRENT
    ora #KEY_DOWN
    sta KEY_CURRENT
scan_d:
    lda #$fb
    jsr latch_row
    and #4
    bne scan_p
    lda KEY_CURRENT
    ora #KEY_RIGHT
    sta KEY_CURRENT
scan_p:
    lda #$df
    jsr latch_row
    and #2
    bne scan_done
    lda KEY_CURRENT
    ora #KEY_PAUSE
    sta KEY_CURRENT
scan_done:
    lda #$ff
    sta KEYBOARD_ROW
    rts
latch_row:
    sta KEYBOARD_ROW
    sta TED_KEYBOARD
    lda TED_KEYBOARD
    rts

; Two equal samples accept a transition. Movement repeats after 15 frames,
; then every 3 frames. P is edge-triggered and never repeats.
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
    and #$0f
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
    beq control_movement
    lda PAUSED
    eor #1
    sta PAUSED
    lda #1
    sta DIRTY
control_movement:
    lda PAUSED
    bne controls_done
    ; Opposing directions cancel, instead of accumulating at the limits.
    lda KEY_ACTIONS
    and #3
    cmp #KEY_LEFT
    beq control_left
    cmp #KEY_RIGHT
    bne control_power
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
control_power:
    lda KEY_ACTIONS
    and #12
    cmp #KEY_UP
    beq control_up
    cmp #KEY_DOWN
    bne controls_done
    lda POWER
    cmp #1
    beq controls_done
    dec POWER
    jmp controls_dirty
control_up:
    lda POWER
    cmp #32
    beq controls_done
    inc POWER
controls_dirty:
    lda #1
    sta DIRTY
controls_done:
    rts
