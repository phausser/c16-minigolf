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
    jsr class_row_pointer
    lda PIXEL_X + 1
    lsr
    lda PIXEL_X
    ror
    lsr
    lsr                       ; column = x >> 3, including x >= 256
    clc
    adc COURSE_PTR
    sta LINE_X
    lda COURSE_PTR + 1
    adc #0
    sec
    sbc #>ATTR_BASE
    sta LINE_X + 1
    clc
    lda LINE_X
    adc #<SCREEN_BASE
    sta COPY_TARGET
    lda LINE_X + 1
    adc #>SCREEN_BASE
    sta COPY_TARGET + 1
    jsr find_dynamic_slot
    lda PIXEL_Y
    and #7
    tay
    lda (FONT_PTR),y
    ora PIXEL_MASK
    eor PIXEL_MASK             ; byte AND NOT mask
    sta (FONT_PTR),y
punch_done:
    rts

find_dynamic_slot:
    ldx DYNAMIC_COUNT
    beq dynamic_alloc
dynamic_search:
    lda DYNAMIC_LO - 1,x
    cmp LINE_X
    bne dynamic_search_next
    lda DYNAMIC_HI - 1,x
    cmp LINE_X + 1
    beq dynamic_found
dynamic_search_next:
    dex
    bne dynamic_search
dynamic_alloc:
    ldx DYNAMIC_COUNT
    cpx #MAX_DYNAMIC_CELLS
    bcs dynamic_overflow
    lda LINE_X
    sta DYNAMIC_LO,x
    lda LINE_X + 1
    sta DYNAMIC_HI,x
    ldy #0
    lda (COPY_TARGET),y
    sta DYNAMIC_OLD,x
    inc DYNAMIC_COUNT
    txa
    clc
    adc #DYNAMIC_CHAR
    sta (COPY_TARGET),y
    pha
    lda DYNAMIC_OLD,x
    jsr charset_address
    lda FONT_PTR
    sta COPY_SOURCE
    lda FONT_PTR + 1
    sta COPY_SOURCE + 1
    pla
    jsr charset_address
    ldy #7
dynamic_copy:
    lda (COPY_SOURCE),y
    sta (FONT_PTR),y
    dey
    bpl dynamic_copy
    rts
dynamic_found:
    dex
    txa
    clc
    adc #DYNAMIC_CHAR
    jmp charset_address
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
restore_next:
    clc
    lda DYNAMIC_LO - 1,x
    adc #<SCREEN_BASE
    sta BITMAP_PTR
    lda DYNAMIC_HI - 1,x
    adc #>SCREEN_BASE
    sta BITMAP_PTR + 1
    ldy #0
    lda DYNAMIC_OLD - 1,x
    sta (BITMAP_PTR),y
    dex
    bne restore_next
    stx DYNAMIC_COUNT
restore_done:
    rts

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

