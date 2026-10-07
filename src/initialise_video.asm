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
; Row 24 as the HUD: blanks in HUD colours, then the strip characters.
; The title screen paints the row as lawn; the game calls this again.
install_hud_row:
    ldx #39
hud_row_clear:
    lda #32
    sta SCREEN_BASE + 24 * 40,x
    lda #HUD_FOREGROUND_COLOR
    sta ATTR_BASE + 24 * 40,x
    dex
    bpl hud_row_clear
    ldx #HUD_LEFT_CELLS - 1
hud_codes_left:
    txa
    clc
    adc #HUD_CHAR
    sta SCREEN_BASE + 24 * 40,x
    dex
    bpl hud_codes_left
    ldx #HUD_CELLS - HUD_LEFT_CELLS - 1
hud_codes_right:
    txa
    clc
    adc #HUD_CHAR + HUD_LEFT_CELLS
    sta SCREEN_BASE + 24 * 40 + HUD_RIGHT_COLUMN,x
    dex
    bpl hud_codes_right
    rts

; draw_course repaints rows 0..23. Row 24 keeps the HUD colours from above.
clear_playfield:
    rts

; Six bar shapes: rows 1 and 5 outline the frame, rows 2..4 hold
; bar_glyph_rows. The charset is already clear.
install_bar_glyphs:
    ldx #0
build_bar:
    txa
    clc
    adc #BAR_CHAR
    jsr charset_address
    lda #$ff
    ldy #1
    sta (FONT_PTR),y
    ldy #5
    sta (FONT_PTR),y
    lda bar_glyph_rows,x
    dey
build_bar_row:
    sta (FONT_PTR),y
    dey
    cpy #1
    bne build_bar_row
    inx
    cpx #BAR_GLYPHS
    bne build_bar
    rts
