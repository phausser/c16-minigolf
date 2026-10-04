!source "src/hardware.inc"
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
    jsr initialise_state
    jsr initialise_video
    jsr draw_course
    jsr draw_static_hud
    jsr draw_dynamic
    jsr draw_power
    lda #$3b                  ; bitmap, display on, 25 rows, y-scroll 3
    sta TED_CONTROL1
main_loop:
    jsr wait_for_frame
frame_begin:
    inc FRAMES
    bne frame_counter_ready
    inc FRAMES + 1
frame_counter_ready:
    jsr scan_keyboard
    jsr debounce_keyboard
    jsr apply_controls
    lda DIRTY
    beq frame_done
    jsr restore_dynamic
    jsr draw_dynamic
    jsr draw_power
    lda #0
    sta DIRTY
frame_done:
    lda TED_RASTER_LO
    sta FRAME_END_RASTER
    jmp main_loop

initialise_state:
    lda #0
    ldx #STATE_END - STATE_BEGIN - 1
clear_state:
    sta STATE_BEGIN,x
    dex
    bpl clear_state
    lda #16
    sta POWER
    rts

!source "src/video.asm"
!source "src/input.asm"
!source "src/render.asm"
!source "build/assets.inc"
; Test-only stress image: verify the safe copier even after the destination
; grows over the original SYS loader and part of its source image.
!ifdef RELOCATION_TEST_PADDING { !fill RELOCATION_TEST_PADDING, $a5 }
runtime_end:
}
load_end:
!if runtime_end > RUNTIME_LIMIT { !error "runtime overlaps renderer scratch" }
!if load_end > BITMAP_END { !error "PRG exceeds physical C16 RAM" }
