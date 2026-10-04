initialise_video:
    lda #$0b                  ; display off while clearing/drawing
    sta TED_CONTROL1
    lda #$08                  ; PAL, 40 columns, hires, zero x-scroll
    sta TED_CONTROL2
    lda #$08                  ; bitmap at $2000, dot fetches from RAM
    sta TED_BITMAP
    lda #0                    ; allow TED's clock doubling in blanking
    sta TED_CLOCK
    sta TED_BACKGROUND
    sta TED_BORDER
    lda #$18                  ; attributes $1800, color matrix $1c00
    sta TED_VIDEO

    ; All 1024 attributes use foreground white/luminance 7, background black.
    ldx #0
video_attributes:
    lda #$07
    sta LUMINANCE_BASE,x
    sta LUMINANCE_BASE + $100,x
    sta LUMINANCE_BASE + $200,x
    sta LUMINANCE_BASE + $300,x
    lda #$10
    sta COLOR_BASE,x
    sta COLOR_BASE + $100,x
    sta COLOR_BASE + $200,x
    sta COLOR_BASE + $300,x
    inx
    bne video_attributes

    lda #0
    sta BITMAP_PTR
    lda #>BITMAP_BASE
    sta BITMAP_PTR + 1
    ldx #32
    ldy #0
    lda #0
video_clear_page:
    sta (BITMAP_PTR),y
    iny
    bne video_clear_page
    inc BITMAP_PTR + 1
    dex
    bne video_clear_page
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
    jsr point_pixel
    lda (BITMAP_PTR),y
    ora PIXEL_MASK
    sta (BITMAP_PTR),y
    rts

; Save bytes even if multiple points share them. Reverse restoration
; unwinds those writes exactly, including ball/aim/background overlaps.
plot_dynamic:
    jsr point_pixel
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
