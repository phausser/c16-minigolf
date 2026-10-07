!source "src/hardware.inc"
!source "src/palette.inc"
!source "src/memory.inc"

; A normal C16 BASIC program: 10 SYS4109. The load image and runtime are
; separate: the copier MUST run below its destination, not at $100d which
; would be overwritten by a larger runtime.
* = $1001
!word basic_end
!word 10
!byte $9e
!text "4109"
!byte 0
basic_end:
!word 0

loader:
    sei
    cld
    ldx #$ff
    txs
    ldx #relocator_end - relocate - 1
loader_copy:
    lda relocator_image,x
    sta RELOCATOR_BASE,x
    dex
    bpl loader_copy
    jmp RELOCATOR_BASE

relocator_image:
!pseudopc RELOCATOR_BASE {
relocate:
    lda #<payload_image
    sta COPY_SOURCE
    lda #>payload_image
    sta COPY_SOURCE + 1
    lda #<RUNTIME_BASE
    sta COPY_TARGET
    lda #>RUNTIME_BASE
    sta COPY_TARGET + 1
    ldy #0
    ldx #>(runtime_end - RUNTIME_BASE)
    beq relocate_tail
relocate_page:
    lda (COPY_SOURCE),y
    sta (COPY_TARGET),y
    iny
    bne relocate_page
    inc COPY_SOURCE + 1
    inc COPY_TARGET + 1
    dex
    bne relocate_page
relocate_tail:
    cpy #<(runtime_end - RUNTIME_BASE)
    beq relocate_done
    lda (COPY_SOURCE),y
    sta (COPY_TARGET),y
    iny
    bne relocate_tail
relocate_done:
    jmp start
relocator_end:
}
!if relocator_end > RUNTIME_BASE { !error "relocator overlaps runtime" }

payload_image:
!pseudopc RUNTIME_BASE {
start:
    ; Mask every TED source as well as CPU IRQ; polling needs no ROM IRQ.
    lda #0
    sta TED_IRQ_ENABLE
    sta TED_SOUND
    lda #$ff
    sta TED_IRQ_STATUS
    jsr copy_font_image
    jsr initialise_video
!ifdef START_HOLE {           ; make play HOLE=n: begin the round at hole n
    lda #START_HOLE - 1
    sta HOLE
} else {
!ifndef TEST_BUILD {          ; tests and smoke start on the hole directly
    jmp title_screen
}
}
    jsr start_hole
main_loop:
    jsr wait_for_frame
frame_begin:
    inc FRAMES
    bne frame_counter_ready
    inc FRAMES + 1
frame_counter_ready:
    jsr sound_tick
    jsr scan_keyboard
    jsr debounce_keyboard
    jsr apply_controls
    jsr physics_tick
    ; While aiming, the direction dots walk one pixel every four frames.
    lda ROLLING
    ora PAUSED
    ora HOLED
    bne aim_still
    lda FRAMES
    and #3
    bne aim_still
    inc AIM_PHASE
    inc DIRTY
aim_still:
    lda DIRTY
    beq frame_hud
    jsr restore_dynamic
    jsr draw_dynamic
    lda #0
    sta DIRTY
frame_hud:
    ; Bit 0: power bar, bit 1: hole and shot numbers. Shifts leave 0.
    lsr HUD_DIRTY
    bcc frame_status
    jsr draw_power
frame_status:
    lsr HUD_DIRTY
    bcc frame_done
    jsr draw_status
frame_done:
    jsr water_tick
    lda TED_RASTER_LO
    sta FRAME_END_RASTER
    jmp main_loop

; Draw hole HOLE from scratch with the display off. The main loop then
; draws ball, aim and HUD (initialise_state marks them dirty).
start_hole:
    lda #$0b
    sta TED_CONTROL1
    jsr clear_playfield
    jsr initialise_state
    jsr draw_course
    jsr water_init
    lda #$1b                  ; text, display on, 25 rows, y-scroll 3
    sta TED_CONTROL1
    rts

; Fire after holing: add the strokes of the player, then the next player
; on the same hole or the next hole; the summary after the last one.
; Practice returns to the menu after its one hole.
next_hole:
    lda practice
    bne new_round
    ldx player
    clc
    lda totals,x
    adc SHOTS
    sta totals,x
    inx
    cpx player_count
    bcc next_player
    ldx #0
    stx player
    inc HOLE
    lda HOLE
    cmp #COURSE_COUNT
    bcc start_hole
    jmp summary_screen
new_round:
    jmp title_screen
; The hole is drawn already: only the ball goes back to the tee.
next_player:
    stx player
    jsr restore_dynamic
    jmp initialise_state

; Clears per-hole state (HOLE lies beyond it), unpacks HOLE and
; puts the ball on the tee; fire must be released before the first shot.
; The accepted keys survive, so fire held into a new hole still needs a
; release before it charges.
initialise_state:
    lda KEY_PREVIOUS
    pha
    lda #0
    ldx #STATE_END - STATE_BEGIN - 1
clear_state:
    sta STATE_BEGIN,x
    dex
    bpl clear_state
    pla
    sta KEY_PREVIOUS
    sta KEY_CANDIDATE
    ldx HOLE
    jsr decode_course
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

!source "src/video.asm"
!source "src/input.asm"
!source "src/math.asm"
!source "src/render.asm"
!source "src/physics.asm"
!source "src/collision.asm"
!source "src/course_decoder.asm"
!source "src/sound.asm"
!source "src/course_renderer.asm"
!source "src/wide_math.asm"
!source "src/initialise_video.asm"
!source "src/circle_diagonal_guard.asm"
!source "src/water.asm"
!source "src/title.asm"
square_lo:
!for square_index, 0, 255 { !byte <(square_index*square_index) }
square_hi:
!for square_index, 0, 255 { !byte >(square_index*square_index) }
!source "src/normals.inc"
!ifdef TEST_BUILD {
!source "build/assets-test.inc"
} else {
!source "build/assets.inc"
}
; The assets define TITLE_PATTERNS, so this check follows them.
!if TITLE_PATTERNS > TITLE_CHAR_LIMIT { !error "title frame and a preview page exceed the charset" }
!if TOTAL_PAR > 99 { !error "the summary shows a two-digit par" }
; Test-only stress image: verify the safe copier even after the destination
; grows over the original SYS loader and part of its source image.
!ifdef RELOCATION_TEST_PADDING { !fill RELOCATION_TEST_PADDING, $a5 }
runtime_end:
}
payload_end:
; The font image must not overlap its store at the end of the charset.
!if * < SCRATCH_BASE { !fill SCRATCH_BASE - *, 0 }   ; above the charset
!source "src/font.inc"
load_end:
!if runtime_end > CLASS_SENTINEL { !error "runtime overlaps the class sentinel" }
!if load_end > $4000 { !error "PRG exceeds physical C16 RAM" }
