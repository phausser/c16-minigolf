initialise_video:
    lda #$0b                  ; display off while clearing/drawing
    sta TED_CONTROL1
    lda #$08                  ; PAL, 40 columns, hires, zero x-scroll
    sta TED_CONTROL2
    lda #$08                  ; bitmap at $2000, dot fetches from RAM
    sta TED_BITMAP
    lda #0                    ; allow TED's clock doubling in blanking
    sta TED_CLOCK
    lda #BORDER_COLOR
    sta TED_BACKGROUND
    sta TED_BORDER
    lda #$18                  ; attributes $1800, color matrix $1c00
    sta TED_VIDEO

    ; Default HUD palette; draw_course colors rows 0..23.
    ldx #0
video_attributes:
    lda #(HUD_BACKGROUND_COLOR & $70) + ((HUD_FOREGROUND_COLOR & $70) >> 4)
    sta LUMINANCE_BASE,x
    sta LUMINANCE_BASE + $100,x
    sta LUMINANCE_BASE + $200,x
    sta LUMINANCE_BASE + $300,x
    lda #((HUD_FOREGROUND_COLOR & $0f) << 4) + (HUD_BACKGROUND_COLOR & $0f)
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
    ; HUD cells 7..14 and 25..30 hold loaded course data: black on black.
    lda #0
    ldx #7
video_hud_data:
    sta LUMINANCE_BASE + 960 + 7,x
    sta COLOR_BASE + 960 + 7,x
    cpx #6
    bcs video_hud_data_next
    sta LUMINANCE_BASE + 960 + 25,x
    sta COLOR_BASE + 960 + 25,x
video_hud_data_next:
    dex
    bpl video_hud_data
    lda #24
    sta TEXT_ROW
; Rows 1..20 plus the hidden-code gap below are cleared from $2140 up to
; $3a3f; rows 0, 21..24 keep lookup data, code and the loaded HUD row.
clear_playfield:
    lda #$40
    sta BITMAP_PTR
    lda #$21
    sta BITMAP_PTR + 1
    ldx #25
    ldy #0
    lda #0                   ; clear playfield; draw_course fills the floor
video_clear_page:
    sta (BITMAP_PTR),y
    iny
    bne video_clear_page
    inc BITMAP_PTR + 1
    dex
    bne video_clear_page
    rts
