; TED text mode. Display stays off ($0B) until start_hole enables it ($1B).
; $FF12 bit 2 clear: charset comes from RAM. $FF13/$FF14 place the charset
; at $3800 and the screen block at $3000. $FF15 is the global black paper.
initialise_video:
    lda #$0b
    sta TED_CONTROL1
    lda #$08                  ; PAL, 40 columns, hires, zero x-scroll
    sta TED_CONTROL2
    lda #$00                  ; RAM charset; voice 1 stays untouched later
    sta TED_BITMAP
    lda #$38                  ; charset $3800, double clock
    sta TED_CLOCK
    lda #$30                  ; attributes $3000, character codes $3400
    sta TED_VIDEO
    lda #0
    sta TED_BACKGROUND
    lda #BORDER_COLOR
    sta TED_BORDER

    ldx #0
    txa
clear_charset:
    sta CHARSET_BASE,x
    sta CHARSET_BASE + $100,x
    sta CHARSET_BASE + $200,x
    sta CHARSET_BASE + $300,x
    inx
    bne clear_charset
    jsr install_rom_glyphs
    jsr install_bar_glyphs

    ldx #0
    lda #32                   ; space, until draw_course and the HUD write
clear_screen:
    sta SCREEN_BASE,x
    sta SCREEN_BASE + $100,x
    sta SCREEN_BASE + $200,x
    sta SCREEN_BASE + $300,x
    inx
    bne clear_screen
    ldx #0
    lda #HUD_FOREGROUND_COLOR
clear_attributes:
    sta ATTR_BASE,x
    sta ATTR_BASE + $100,x
    sta ATTR_BASE + $200,x
    sta ATTR_BASE + $300,x
    inx
    bne clear_attributes
    lda #24
    sta TEXT_ROW
    rts

; draw_course repaints rows 0..23. Row 24 keeps the HUD colours from above.
clear_playfield:
    rts

; Screen codes whose ROM shapes the HUD uses. Same codes in RAM.
rom_glyph_codes:
!byte 1,2,5,8,11,13,14,16,18,19,20,21
!byte 32
!byte 48,49,50,51,52,53,54,55,56,57
ROM_GLYPH_COUNT = * - rom_glyph_codes

install_rom_glyphs:
    ldx #0
install_one_glyph:
    lda rom_glyph_codes,x
    pha
    jsr charset_address
    pla
    sta COPY_SOURCE
    lda #0
    sta COPY_SOURCE + 1
    asl COPY_SOURCE
    rol COPY_SOURCE + 1
    asl COPY_SOURCE
    rol COPY_SOURCE + 1
    asl COPY_SOURCE
    rol COPY_SOURCE + 1
    clc
    lda COPY_SOURCE + 1
    adc #$d0
    sta COPY_SOURCE + 1
    ldy #7
install_glyph_bytes:
    lda (COPY_SOURCE),y
    sta (FONT_PTR),y
    dey
    bpl install_glyph_bytes
    inx
    cpx #ROM_GLYPH_COUNT
    bne install_one_glyph
    rts

; Nine bar shapes, widths 0..8. Glyph row 3 is the resting line.
install_bar_glyphs:
    ldx #0
build_bar:
    txa
    clc
    adc #BAR_CHAR
    jsr charset_address
    lda bar_masks,x
    ldy #1
    sta (FONT_PTR),y
    ldy #2
    sta (FONT_PTR),y
    ldy #4
    sta (FONT_PTR),y
    ldy #5
    sta (FONT_PTR),y
    lda #$ff
    ldy #3
    sta (FONT_PTR),y
    lda #0
    tay
    sta (FONT_PTR),y
    ldy #6
    sta (FONT_PTR),y
    ldy #7
    sta (FONT_PTR),y
    inx
    cpx #9
    bne build_bar
    rts
