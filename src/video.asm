clear_hud_bitmap:
    ; Clear visible rows 22 and 24, preserving arithmetic in row 23.
    lda #0
    ldx #0
clear_hud_main:
    sta $3b80,x
    sta $3e00,x
    inx
    bne clear_hud_main
    ldx #63
clear_hud_tail:
    sta $3c80,x
    sta $3f00,x
    dex
    bpl clear_hud_tail
    rts

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

; BITMAP + (y / 8) * 320 + (x / 8) * 8 + (y & 7).
; PIXEL_X is a word: right-hand cells at x >= 256 must NOT wrap.
point_pixel:
    lda PIXEL_Y
    lsr
    lsr
    lsr
    tax
    lda bitmap_rows_lo,x
    sta BITMAP_PTR
    lda bitmap_rows_hi,x
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
    ora BITMAP_PTR           ; row bases and x offsets are multiples of 8
    sta BITMAP_PTR
    lda PIXEL_X
    and #7
    tax
    lda pixel_masks,x
    sta PIXEL_MASK
    ldy #0
    rts

plot_pixel:
    lda PIXEL_Y
    cmp #8
    bcc plot_outside_playfield
    cmp #168
    bcs plot_outside_playfield
    jsr point_pixel
    lda (BITMAP_PTR),y
    ora PIXEL_MASK
    sta (BITMAP_PTR),y
plot_outside_playfield:
    rts

; Save bytes even if multiple points share them. Reverse restoration
; unwinds those writes exactly, including ball/aim/background overlaps.
plot_dynamic:
    lda PIXEL_Y
    cmp #8
    bcc dynamic_outside_playfield
    cmp #168
    bcs dynamic_outside_playfield
    jsr point_pixel
save_dynamic_byte:
    ldx DYNAMIC_COUNT
    lda BITMAP_PTR
    sta DYNAMIC_LO,x
    lda BITMAP_PTR + 1
    sta DYNAMIC_HI,x
    lda (BITMAP_PTR),y
    sta DYNAMIC_OLD,x
    ora PIXEL_MASK
    sta (BITMAP_PTR),y
    inc DYNAMIC_COUNT
dynamic_outside_playfield:
    rts

restore_dynamic:
    ldy #0
restore_next:
    lda DYNAMIC_COUNT
    beq restore_done
    dec DYNAMIC_COUNT
    ldx DYNAMIC_COUNT
    lda DYNAMIC_LO,x
    sta BITMAP_PTR
    lda DYNAMIC_HI,x
    sta BITMAP_PTR + 1
    lda DYNAMIC_OLD,x
    sta (BITMAP_PTR),y
    jmp restore_next
restore_done:
    rts

pixel_masks:
!byte $80,$40,$20,$10,$08,$04,$02,$01

