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
clear_charset:                ; up to the font image (copied by start)
    sta CHARSET_BASE,x
    sta CHARSET_BASE + $100,x
    sta CHARSET_BASE + $200,x
    cpx #<FONT_STORE
    bcs clear_charset_next
    sta CHARSET_BASE + $300,x
clear_charset_next:
    inx
    bne clear_charset
    jsr install_bar_glyphs
    lda #0                    ; white glyphs on black
    jsr install_font

    ldx #0
    lda #BLANK_CHAR           ; until draw_course and the HUD write
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
; Row 24 as the HUD: blank cells in HUD colours. The title screen paints
; the row as lawn; the game calls this again.
install_hud_row:
    ldx #39
hud_row_clear:
    lda #BLANK_CHAR
    sta SCREEN_BASE + 24 * 40,x
    lda #HUD_FOREGROUND_COLOR
    sta ATTR_BASE + 24 * 40,x
    dex
    bpl hud_row_clear
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

; Font image to its charset cells; start runs this once after relocation.
!if >FONT_STORE != >(CHARSET_BASE + $3ff) { !error "the font store must lie in the last charset page" }
copy_font_image:
    ldx #font_image_end - font_image
copy_font_byte:
    lda font_image - 1,x
    sta FONT_STORE - 1,x
    dex
    bne copy_font_byte
    rts

; A = $00: white glyphs on black (HUD), $ff: black on the white floor
; (title). Expands the font image into codes 0..FONT_GLYPHS-1, pixel
; rows 1..5 (code 0 blank), and the big figure's two cells.
install_font:
    sta TEMP
    lda #<(FONT_STORE - 6)    ; rows 1..5 of code c: FONT_STORE + 5c - 6
    sta COPY_SOURCE
    lda #>(FONT_STORE - 6)
    sta COPY_SOURCE + 1
    ldx #0
font_glyph:
    txa
    jsr charset_address
    ldy #7
font_row:
    lda TEMP
    cpx #BLANK_CHAR
    beq font_put
    cpy #6
    bcs font_put
    cpy #1
    bcc font_put
    eor (COPY_SOURCE),y
font_put:
    sta (FONT_PTR),y
    dey
    bpl font_row
    lda COPY_SOURCE
    clc
    adc #5
    sta COPY_SOURCE
    bcc font_next
    inc COPY_SOURCE + 1
font_next:
    inx
    cpx #FONT_GLYPHS
    bne font_glyph
    ldx #15
font_figure:
    lda FONT_STORE + (FONT_GLYPHS - 1) * 5,x
    eor TEMP
    sta CHARSET_BASE + FIGURE_CHAR * 8,x
    dex
    bpl font_figure
    rts
