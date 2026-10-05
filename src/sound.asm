; Short effects on TED voice 2 (square or noise); $FF12 stays untouched.
; One control byte serves both registers: bits 0-1 are frequency bits 8-9
; in $FF10, and in $FF11 bit 3 makes the volume maximal whatever bits 0-2
; hold (9..15 equal 8), bit 5 selects the square wave, bit 6 noise.
; f = 110840 / (1024 - N) Hz on PAL.
SOUND_SHOT = 0
SOUND_WALL = 1
SOUND_CUP = 2
SOUND_WATER = 4
SOUND_CHAIN = 4               ; control bit 2: the next tone follows

; X = tone index. Callers do not need X afterwards.
play_sound:
    lda sound_lo,x
    sta TED_VOICE2_LO
    lda sound_control,x
    sta TED_VOICE2_HI
    sta TED_SOUND
    lda sound_frames,x
    sta SOUND_TIME
    stx SOUND_TONE
    rts

; Once per frame: count down, chain to the next tone or switch off.
sound_tick:
    lda SOUND_TIME
    beq sound_done
    dec SOUND_TIME
    bne sound_done
    ldx SOUND_TONE
    lda sound_control,x
    and #SOUND_CHAIN
    beq sound_off
    inx
    bne play_sound
sound_off:
    sta TED_SOUND             ; A = 0: voices off
sound_done:
    rts

; Shot "plopp" 150 Hz, wall "tok" 1.2 kHz, cup 523 + 784 Hz, water noise.
SOUND_N0 = 1024 - 739
SOUND_N1 = 1024 - 92
SOUND_N2 = 1024 - 212
SOUND_N3 = 1024 - 141
SOUND_N4 = 1024 - 400
sound_lo:
!byte <SOUND_N0, <SOUND_N1, <SOUND_N2, <SOUND_N3, <SOUND_N4
sound_control:
!byte $28 + >SOUND_N0, $28 + >SOUND_N1, $28 + SOUND_CHAIN + >SOUND_N2
!byte $28 + >SOUND_N3, $48 + >SOUND_N4
sound_frames:
!byte 4, 2, 6, 12, 14
