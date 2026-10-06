; Short step sequences on both TED voices. Shot, wall, cup, water and hole
; in one are effects 51, 38, 53, 72 and 83 of
; https://github.com/phausser/c16-sound-fx (PAL data).
; A step is: frames, voice 1 N lo/hi, voice 2 N lo/hi, $FF11 control
; (bit 4 voice 1 square, bit 5 voice 2 square, bit 6 voice 2 noise,
; bits 0-3 volume). Frame 0 ends the effect. Only bits 0-1 of $FF10 and
; $FF12 are written; $FF12 bit 2 selects the RAM character set.
; f = 110840 / (1024 - N) Hz on PAL, rounded as in c16-sound-fx.
SOUND_CLOCK = 110840

!macro sound_step .frames, .hz1, .hz2, .control {
    .n1 = 1024 - (SOUND_CLOCK + .hz1 / 2) / .hz1
    .n2 = 1024 - (SOUND_CLOCK + .hz2 / 2) / .hz2
    !byte .frames, <.n1, >.n1, <.n2, >.n2, .control
}

; X = offset of the first step. Callers do not need X afterwards.
play_sound:
    lda sound_steps,x
    beq sound_off
    sta SOUND_TIME
    stx SOUND_TONE
    lda sound_steps + 1,x
    sta TED_VOICE1_LO
    lda TED_BITMAP
    and #$fc
    ora sound_steps + 2,x
    sta TED_BITMAP
    lda sound_steps + 3,x
    sta TED_VOICE2_LO
    lda TED_VOICE2_HI
    and #$fc
    ora sound_steps + 4,x
    sta TED_VOICE2_HI
    lda sound_steps + 5,x
    sta TED_SOUND
    rts
sound_off:
    sta SOUND_TIME            ; A = 0
    sta TED_SOUND             ; voices off
    rts

; Once per frame: count down, then the next step or silence.
sound_tick:
    lda SOUND_TIME
    beq sound_done
    dec SOUND_TIME
    bne sound_done
    lda SOUND_TONE
    clc
    adc #6
    tax
    jmp play_sound
sound_done:
    rts

sound_steps:
SOUND_SHOT = * - sound_steps   ; 51 boulder-diamond: 320 Hz pickup
    +sound_step 1, 320, 110, $14
    +sound_step 1, 320, 110, $12
    +sound_step 1, 320, 110, $11
    !byte 0
SOUND_WALL = * - sound_steps   ; 38 switch-click: dry noise click
    +sound_step 2, 110, 2000, $44
    !byte 0
SOUND_CUP = * - sound_steps    ; 53 paradroid-link: rising double tones
    +sound_step 2, 330, 660, $34
    +sound_step 2, 440, 880, $35
    +sound_step 2, 660, 1320, $35
    +sound_step 2, 440, 880, $34
    +sound_step 2, 880, 1760, $34
    +sound_step 3, 1320, 2640, $32
    !byte 0
SOUND_WATER = * - sound_steps  ; 72 flap-double: two noise splashes
    +sound_step 1, 110, 2000, $43
    +sound_step 2, 110, 1200, $42
    +sound_step 2, 110, 110, $00
    +sound_step 1, 110, 1700, $44
    +sound_step 2, 110, 850, $42
    +sound_step 2, 110, 450, $41
    +sound_step 6, 110, 110, $00
    !byte 0
SOUND_ACE = * - sound_steps    ; 83 mario-mushroom: hole in one
    +sound_step 2, 392, 110, $14
    +sound_step 2, 523, 110, $15
    +sound_step 2, 659, 110, $15
    +sound_step 2, 440, 110, $14
    +sound_step 2, 587, 110, $15
    +sound_step 2, 740, 110, $15
    +sound_step 2, 494, 110, $14
    +sound_step 2, 659, 110, $15
    +sound_step 2, 831, 110, $15
    +sound_step 2, 523, 110, $14
    +sound_step 2, 698, 110, $15
    +sound_step 2, 880, 110, $15
    +sound_step 2, 587, 110, $14
    +sound_step 2, 784, 110, $14
    +sound_step 2, 988, 110, $13
    !byte 0
!if * - sound_steps > 256 { !error "sound steps exceed one index page" }
