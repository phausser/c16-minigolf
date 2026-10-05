; TED's low raster byte wraps again at line 256. Crossing line 205 from
; below still occurs exactly once per PAL frame. A frame's drawing has to
; finish before the next crossing; VICE smoke measures this independently.
wait_for_frame:
wait_before_border:
    lda TED_RASTER_LO
    cmp #205
    bcs wait_before_border
wait_at_border:
    lda TED_RASTER_LO
    cmp #205
    bcc wait_at_border
    rts

; Scratch bitmap of the three cell rows under window_row:
; SCRATCH + slot * 320 + (x / 8) * 8 + (y & 7).
; PIXEL_X is a word: right-hand cells at x >= 256 must NOT wrap.
; The slot bases are multiples of 8, so the row byte can be ORed in.
point_pixel:
    lda PIXEL_Y
    lsr
    lsr
    lsr
    sec
    sbc window_row
    tax
    lda scratch_lo,x
    sta BITMAP_PTR
    lda scratch_hi,x
    clc
    adc PIXEL_X + 1
    sta BITMAP_PTR + 1
    lda PIXEL_X
    and #$f8
    clc
    adc BITMAP_PTR
    sta BITMAP_PTR
    bcc point_no_carry
    inc BITMAP_PTR + 1
point_no_carry:
    lda PIXEL_Y
    and #7
    ora BITMAP_PTR
    sta BITMAP_PTR
    lda PIXEL_X
    and #7
    tax
    lda pixel_masks,x
    sta PIXEL_MASK
    ldy #0
    rts

; Cup rows outside the row being emitted are ignored. The bitmap still
; uses old polarity here: a set bit is black.
plot_pixel:
    lda PIXEL_Y
    cmp #8
    bcc plot_outside_playfield
    cmp #168
    bcs plot_outside_playfield
    lsr
    lsr
    lsr
    cmp emit_row
    bne plot_outside_playfield
    jsr point_pixel
    lda (BITMAP_PTR),y
    ora PIXEL_MASK
    sta (BITMAP_PTR),y
plot_outside_playfield:
    rts

; A = character code 0..127. FONT_PTR points at its eight bytes.
charset_address:
    sta FONT_PTR
    lda #0
    sta FONT_PTR + 1
    asl FONT_PTR
    rol FONT_PTR + 1
    asl FONT_PTR
    rol FONT_PTR + 1
    asl FONT_PTR
    rol FONT_PTR + 1
    clc
    lda FONT_PTR
    adc #<CHARSET_BASE
    sta FONT_PTR
    lda FONT_PTR + 1
    adc #>CHARSET_BASE
    sta FONT_PTR + 1
    rts

; Clear the ink bit. The static glyph is copied into a dynamic character
; the first time a cell is touched; later dots share that character.
; Preserves GLYPH, TEMP, POINT_INDEX and the pixel coordinates.
punch_pixel:
    lda PIXEL_Y
    cmp #8
    bcc punch_done
    cmp #168
    bcs punch_done
    lsr
    lsr
    lsr
    jsr dynamic_cell
    lda PIXEL_Y
    and #7
    tay
    lda (FONT_PTR),y
    ora PIXEL_MASK
    eor PIXEL_MASK             ; byte AND NOT mask
    sta (FONT_PTR),y
punch_done:
    rts

; A = cell row 1..20, column from PIXEL_X. FONT_PTR = the cell's dynamic
; character, copied from its static glyph on first use. Clobbers X and Y.
dynamic_cell:
    tax
    lda PIXEL_X + 1
    lsr
    lda PIXEL_X
    ror
    lsr
    lsr                       ; column = x >> 3, including x >= 256
    clc
    adc screen_rows_lo,x
    sta COPY_TARGET
    lda screen_rows_hi,x
    adc #0
    sta COPY_TARGET + 1       ; screen address of the cell
    ldx DYNAMIC_COUNT
    beq dynamic_alloc
dynamic_search:
    lda DYNAMIC_LO - 1,x
    cmp COPY_TARGET
    bne dynamic_search_next
    lda DYNAMIC_HI - 1,x
    cmp COPY_TARGET + 1
    beq dynamic_found
dynamic_search_next:
    dex
    bne dynamic_search
dynamic_alloc:
    ldx DYNAMIC_COUNT
    cpx #MAX_DYNAMIC_CELLS
    bcs dynamic_overflow
    inc DYNAMIC_COUNT
    lda COPY_TARGET
    sta DYNAMIC_LO,x
    lda COPY_TARGET + 1
    sta DYNAMIC_HI,x
    ldy #0
    lda (COPY_TARGET),y
    sta DYNAMIC_OLD,x
    ; Static glyph at CHARSET_BASE + code * 8; code < 128.
    pha
    asl
    asl
    asl
    sta COPY_SOURCE
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    ora #>CHARSET_BASE
    sta COPY_SOURCE + 1
    lda dynamic_codes,x
    sta (COPY_TARGET),y
    lda dynamic_glyphs_lo,x
    sta FONT_PTR
    lda dynamic_glyphs_hi,x
    sta FONT_PTR + 1
!for glyph_row, 0, 7 {
    ldy #glyph_row
    lda (COPY_SOURCE),y
    sta (FONT_PTR),y
}
    rts
dynamic_found:
    lda dynamic_glyphs_lo - 1,x
    sta FONT_PTR
    lda dynamic_glyphs_hi - 1,x
    sta FONT_PTR + 1
    rts
dynamic_overflow:
    lda #0
    sta PIXEL_MASK
    lda #<SCRATCH_BASE
    sta FONT_PTR
    lda #>SCRATCH_BASE
    sta FONT_PTR + 1
    rts

restore_dynamic:
    ldx DYNAMIC_COUNT
    beq restore_done
    ldy #0
restore_next:
    lda DYNAMIC_LO - 1,x
    sta BITMAP_PTR
    lda DYNAMIC_HI - 1,x
    sta BITMAP_PTR + 1
    lda DYNAMIC_OLD - 1,x
    sta (BITMAP_PTR),y
    dex
    bne restore_next
    stx DYNAMIC_COUNT
restore_done:
    rts

!if CHARSET_BASE & $3ff { !error "glyph address math needs a 1 KB charset" }
screen_rows_lo:
!for cell_row, 0, 24 { !byte <(SCREEN_BASE + cell_row * 40) }
screen_rows_hi:
!for cell_row, 0, 24 { !byte >(SCREEN_BASE + cell_row * 40) }
dynamic_codes:
!for slot, 0, MAX_DYNAMIC_CELLS - 1 { !byte DYNAMIC_CHAR + slot }
dynamic_glyphs_lo:
!for slot, 0, MAX_DYNAMIC_CELLS - 1 { !byte <(CHARSET_BASE + (DYNAMIC_CHAR + slot) * 8) }
dynamic_glyphs_hi:
!for slot, 0, MAX_DYNAMIC_CELLS - 1 { !byte >(CHARSET_BASE + (DYNAMIC_CHAR + slot) * 8) }

scratch_lo:
!byte <SCRATCH_BASE,<SCRATCH_BASE + 320,<SCRATCH_BASE + 640
scratch_hi:
!byte >SCRATCH_BASE,>SCRATCH_BASE + 320,>SCRATCH_BASE + 640

; COURSE_PTR = COLOR_BASE + A * 40, A = cell row 0..24. X is clobbered.
class_row_pointer:
    asl
    asl
    asl                       ; row * 8 <= 192
    sta COURSE_PTR
    ldx #>COLOR_BASE >> 2
    stx COURSE_PTR + 1
    asl
    rol COURSE_PTR + 1
    asl
    rol COURSE_PTR + 1        ; COLOR_BASE + row * 32, carry clear
    adc COURSE_PTR
    sta COURSE_PTR
    bcc class_row_ready
    inc COURSE_PTR + 1
class_row_ready:
    rts

pixel_masks:
!byte $80,$40,$20,$10,$08,$04,$02,$01

