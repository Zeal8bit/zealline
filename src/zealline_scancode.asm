; SPDX-FileCopyrightText: 2025 Zeal 8-bit Computer <contact@zeal8bit.com>, Martin Barth (github:ufobat)
;
; SPDX-License-Identifier: Apache-2.0


        SECTION TEXT

        ; "zealline_to_uppercase" reads a line/command from STDIN
        ;   Converts a Zeal Scancode in Register B to its uppercase
        ; Parameters:
        ;   B - the lowercase Zeal OS scancode
        ; Returns:
        ;   A  - In uppercase or Null if no uppercase is avaible
        ; Alters:
        ;   A
        PUBLIC zealline_to_uppercase
zealline_to_uppercase:
        push hl
        ld hl, upper_case
        ld a, b
        add l
        ld l, a
        adc h
        sub l
        ld h, a
        ld a, (hl)
        pop hl
        ret


;;; AUTOGENERATED BY zealscancode.py ;;;
;;; US Keyboard Layout
        SECTION DATA
upper_case:
        db  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0
        db  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0
        db ' ',  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0
        db '(', '!', '@', '#', '$', '%', '^', '&', '*',  0 , ';',  0 ,  0 , '+',  0 ,  0
        db  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0
        db  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0 ,  0
        db '"', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O'
        db 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',  0 ,  0 ,  0 ,  0 ,  0
