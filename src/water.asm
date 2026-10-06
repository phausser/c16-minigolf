; Moving water. Every water cell runs through the same cycle: none, none,
; 1 px, 2 px, 2 px, 1 px of solid shadow on its left and top edge, and its
; luminance drops by the same 0, 0, 1, 2, 2, 1 below the water colour.
; The phase is (row + column) mod 6, so the pattern runs diagonally
; down-right at constant speed. Six characters, one per phase.
; Colours: water_init generates one small program per phase from STA
; instructions for its cells' attributes (4 cycles a cell) in the renderer
; scratch, free once the hole is drawn. Each step patches its two colours.
; Physics finds water by the cell hue, which never changes.
WATER_PHASES = 6
WATER_STEP_FRAMES = 8         ; frames per step, at least WATER_PHASES
!if WATER_STEP_FRAMES < WATER_PHASES { !error "a step redraws one phase per frame" }
WATER_CODE = SCRATCH_BASE + 64     ; below: ball cells off the playfield
WATER_CODE_END = SCRATCH_END - 32  ; room for every phase's LDA, LDA, RTS

; Display off, after draw_course: glyphs, cell codes and colour programs.
water_init:
    ldx #WATER_PHASES - 1
water_init_glyphs:
    jsr water_glyph
    dex
    bpl water_init_glyphs
    lda #1
    sta TEMP                  ; row; water lies in rows 1..20
water_init_row:
    jsr water_row_pointers
    ldy #0
water_init_cell:
    lda (COPY_TARGET),y
    and #15
    cmp #WATER_HUE
    bne water_init_next
    lda (COPY_SOURCE),y
    cmp solid_code
    bne water_init_next
    tya
    clc
    adc TEMP                  ; row + column, below 60
water_init_mod:
    cmp #WATER_PHASES
    bcc water_init_phase
    sbc #WATER_PHASES
    bcs water_init_mod
water_init_phase:
    tax
    lda water_codes,x
    sta (COPY_SOURCE),y
water_init_next:
    iny
    cpy #40
    bne water_init_cell
    inc TEMP
    lda TEMP
    cmp #21
    bne water_init_row
    ; One program per phase: LDA #even, STA cells..., LDA #odd, STA..., RTS.
    lda #<WATER_CODE
    sta BITMAP_PTR
    lda #>WATER_CODE
    sta BITMAP_PTR + 1
    ldx #0
water_program:
    stx water_index
    lda BITMAP_PTR
    sta water_runs_lo,x
    lda BITMAP_PTR + 1
    sta water_runs_hi,x
    lda #0
    sta water_parity
    jsr water_emit_parity
    ldx water_index
    lda BITMAP_PTR
    sta water_odd_lo,x
    lda BITMAP_PTR + 1
    sta water_odd_hi,x
    inc water_parity
    jsr water_emit_parity
    lda #$60                  ; RTS
    jsr water_emit_byte
    ldx water_index
    jsr water_colours
    jsr water_run_phase       ; the colours of the current step at once
    inx
    cpx #WATER_PHASES
    bne water_program
    rts

; LDA #0 (patched later), then STA attribute for every cell of phase
; water_index whose (row + column) parity is water_parity.
water_emit_parity:
    lda #$a9                  ; LDA #
    jsr water_emit_byte
    lda #0
    jsr water_emit_byte
    lda #1
    sta TEMP
water_emit_row:
    jsr water_row_pointers
    ldy #0
water_emit_cell:
    ldx water_index
    lda (COPY_SOURCE),y
    cmp water_codes,x
    bne water_emit_next
    tya
    eor TEMP
    and #1
    cmp water_parity
    bne water_emit_next
    lda BITMAP_PTR + 1        ; full: further cells keep their colour
    cmp #>WATER_CODE_END
    bcc water_emit_room
    lda BITMAP_PTR
    cmp #<WATER_CODE_END
    bcs water_emit_next
water_emit_room:
    lda #$8d                  ; STA absolute
    jsr water_emit_byte
    tya
    clc
    adc COPY_TARGET
    php
    jsr water_emit_byte
    plp
    lda COPY_TARGET + 1
    adc #0
    jsr water_emit_byte
water_emit_next:
    iny
    cpy #40
    bne water_emit_cell
    inc TEMP
    lda TEMP
    cmp #21
    bne water_emit_row
    rts

; Store A at BITMAP_PTR and advance. X, Y and carry are preserved.
water_emit_byte:
    sty water_temp
    ldy #0
    sta (BITMAP_PTR),y
    inc BITMAP_PTR
    bne water_emit_done
    inc BITMAP_PTR + 1
water_emit_done:
    ldy water_temp
    rts

; COPY_SOURCE = screen row TEMP, COPY_TARGET = its attributes.
water_row_pointers:
    ldx TEMP
    lda screen_rows_lo,x
    sta COPY_SOURCE
    lda screen_rows_hi,x
    sta COPY_SOURCE + 1
    sec
    lda COPY_SOURCE
    sbc #<(SCREEN_BASE - ATTR_BASE)
    sta COPY_TARGET
    lda COPY_SOURCE + 1
    sbc #>(SCREEN_BASE - ATTR_BASE)
    sta COPY_TARGET + 1
    rts

; Once per frame: in the first six frames of a step redraw one phase,
; glyph and colours; after the last one the cycle advances.
water_tick:
    ldx water_frame
    inx
    cpx #WATER_STEP_FRAMES
    bcc water_frame_ready
    ldx #0
water_frame_ready:
    stx water_frame
    cpx #WATER_PHASES
    bcs water_tick_done
    jsr water_glyph
    jsr water_colours
    jsr water_run_phase
    cpx #WATER_PHASES - 1
    bne water_tick_done
    inc water_step
    lda water_step
    cmp #WATER_PHASES
    bcc water_tick_done
    lda #0
    sta water_step
water_tick_done:
    rts
; X = phase: run its colour program. X preserved.
water_run_phase:
    lda water_runs_lo,x
    sta water_vector
    lda water_runs_hi,x
    sta water_vector + 1
    jsr water_run
    ldx water_index
    rts
water_run:
    jmp (water_vector)

; X = phase 0..5: Y = its position in the cycle for the current step.
water_position:
    txa
    sec
    sbc water_step            ; phase - step mod WATER_PHASES
    bcs water_position_done
    adc #WATER_PHASES
water_position_done:
    tay
    rts

; X = phase: patch both colours of its program. X preserved.
water_colours:
    stx water_index
    jsr water_position
    lda water_luminance,y
    sta water_temp
    lda water_runs_lo,x
    sta COPY_TARGET
    lda water_runs_hi,x
    sta COPY_TARGET + 1
    ldy #1
    lda water_temp
    clc
    adc #WATER_COLOR_EVEN
    sta (COPY_TARGET),y
    lda water_odd_lo,x
    sta COPY_TARGET
    lda water_odd_hi,x
    sta COPY_TARGET + 1
    lda water_temp
    clc
    adc #WATER_COLOR_ODD
    sta (COPY_TARGET),y
    rts

; X = phase character 0..5: its shadow for the current step. X preserved.
water_glyph:
    stx water_index
    jsr water_position
    lda water_cycle,y
    sta water_temp            ; offset of the shadow glyph
    lda water_codes,x
    jsr charset_address
    ldx water_temp
    ldy #0
water_glyph_copy:
    lda water_shadow_glyphs,x
    sta (FONT_PTR),y
    inx
    iny
    cpy #8
    bne water_glyph_copy
    ldx water_index
    rts

water_step:
!byte 0
water_frame:                  ; frame within the step
!byte 0
water_index:
!byte 0
water_temp:
!byte 0
water_parity:
!byte 0
water_vector:
!word 0
!if <water_vector = $ff { !error "JMP (indirect) must not cross a page" }
water_runs_lo:
!fill WATER_PHASES
water_runs_hi:
!fill WATER_PHASES
water_odd_lo:
!fill WATER_PHASES
water_odd_hi:
!fill WATER_PHASES

; Free screen codes: not the bar, HUD strip or dynamic glyphs.
water_codes:
!byte 3,4,6,7,9,10

; Cycle position -> glyph offset and luminance step:
; none, none, 1 px, 2 px, 2 px, 1 px.
water_cycle:
!byte 0,0,8,16,16,8
water_luminance:              ; added modulo 256: lower luminance
!byte 0,0,<-$10,<-$20,<-$20,<-$10
!if water_luminance - water_cycle != WATER_PHASES | * - water_luminance != WATER_PHASES {
    !error "water_codes, water_cycle and water_luminance need WATER_PHASES entries"
}
!if water_cycle - water_codes != WATER_PHASES { !error "water_codes needs WATER_PHASES entries" }

; Blue water (set bits); shadow pixels clear at the left and top edge.
water_shadow_glyphs:
; none
!byte %11111111
!byte %11111111
!byte %11111111
!byte %11111111
!byte %11111111
!byte %11111111
!byte %11111111
!byte %11111111
; 1 px
!byte %00000000
!byte %01111111
!byte %01111111
!byte %01111111
!byte %01111111
!byte %01111111
!byte %01111111
!byte %01111111
; 2 px11111
!byte %00000000
!byte %00000000
!byte %00111111
!byte %00111111
!byte %00111111
!byte %00111111
!byte %00111111
!byte %00111111
