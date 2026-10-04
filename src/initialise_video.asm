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

    ; Default HUD palette; hidden rows and playfield colors are set below.
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

    ; The first bitmap cell row holds 320 bytes of immutable lookup data.
    ldy #0
video_install_lookup:
    lda lookup_image,y
    sta BITMAP_BASE,y
    iny
    bne video_install_lookup
    ldy #63
video_install_lookup_tail:
    lda lookup_image + 256,y
    sta BITMAP_BASE + 256,y
    dey
    bpl video_install_lookup_tail
    lda #$40
    sta BITMAP_PTR
    lda #$21
    sta BITMAP_PTR + 1
    ldx #25
    ldy #0
    lda #$ff                 ; solid black; parity fill opens gray surfaces
video_clear_page:
    sta (BITMAP_PTR),y
    iny
    bne video_clear_page
    inc BITMAP_PTR + 1
    dex
    bne video_clear_page
    ; The static renderer lives in hidden row 21 ($3a40-$3b7f).
    ; Fixed black/black attributes hide instruction bits without multicolor.
    ldx #39
    lda #0
video_hide_code:
    sta LUMINANCE_BASE,x
    sta COLOR_BASE,x
    sta LUMINANCE_BASE + 21*40,x
    sta COLOR_BASE + 21*40,x
    sta LUMINANCE_BASE + 23*40,x
    sta COLOR_BASE + 23*40,x
    dex
    bpl video_hide_code
    jsr initialise_course_colors
    jmp clear_hud_bitmap
