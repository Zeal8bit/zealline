; SPDX-FileCopyrightText: 2025 Zeal 8-bit Computer <contact@zeal8bit.com>, Martin Barth (github:ufobat)
;
; SPDX-License-Identifier: Apache-2.0

        INCLUDE "zos_sys.asm"
        INCLUDE "zealline_configuration.asm"
        INCLUDE "strutils_h.asm"

        SECTION TEXT

        ; ---------------------------------------------------------------------
        ; PUBLIC INTERFACE
        ; ---------------------------------------------------------------------
        PUBLIC zealline_reset_history_search
        PUBLIC zealline_history_search_backward
        PUBLIC zealline_history_search_forward
        ;PUBLIC zealline_history_search_backward_substr
        ;PUBLIC zealline_history_search_backward_substr
        PUBLIC zealline_add_history

        ; History
        ASSERT(HISTORY_SIZE >= 512)     ; the ring buffer must be at least big enough to store 2 commands
                                        ; just to be super save that deleting (some) entries will always create
                                        ; sufficient space for the next new entry
        DEFVARS 0 {
                history_entry_next      DS.W 1
                history_entry_line_len  DS.B 1
                history_entry_line_ptr  DS.W 1
        }

        ; Performs ADD HL, A
        ; Alters: HL
        MACRO ADD_HL_A _
                add l
                ld l, a
                adc h
                sub l
                ld h, a
        ENDM

        ; Adds the history alignment to Register A
        ;   Increases the value in A till it is a muliple of 4
        ; Alters: A
        MACRO ADD_HISTORY_ALIGNMENT _
                add history_entry_line_ptr      ; add offset for the header, until the string actually begins
                or 3                            ; set the last 2 bits to high and add 1
                add 1                           ; so we end on the address of the next item in a aligned way
        ENDM

        ; Checks if the adress in HL is beyond the history ringbuffer. Jumps if valid.
        ; Alters: A
        MACRO ON_REG_VALID_GOTO upper, lower, valid_label
                ld a, upper                             ; Compare high byte of HL with high byte of history_ringbuffer_end
                cp history_ringbuffer_end >> 8
                jr c, valid_label

                ld a, lower                             ; Compare low byte of HL with low byte of history_ringbuffer_end
                cp history_ringbuffer_end & 0xFF
                jr c, valid_label
                ; Fall-through
        ENDM

        ; Tests if HL is a null byte
        ; Alters: A
        MACRO ON_HL_IS_NULL_GOTO label
                ld a, h
                cp l
                jp z, label
        ENDM


        ; Setup HL and BC for all zealline_history_search*
        ; Returns: HL and BC, the result values
        MACRO SETUP_SEARCH_RESULT _
                ld hl, (history_iterator_ptr)
                ; Point to the length
                inc l
                inc l
                ld b, 0
                ld c, (hl)
                dec c                                   ; dec c because remove nullbyte from length
                ld hl, history_search_result
        ENDM


        ; Align HL on a 4-byte bound
align_hl:
        ; HL = (HL + 3) & ~3
        inc hl
        inc hl
        inc hl
        ld a, 0xFC
        and l
        ld l, a
        ret

        ; Resets the history serach iterator
        ; Alters: HL
zealline_reset_history_search:
        ld hl, 0
        ld (history_iterator_ptr), hl
        ret

        ; Searches backward through the history, retrieving the previous line.
        ; Returns: HL - the pointer to the line
        ;          BC - length of the line
        ; Alters: A, HL
zealline_history_search_backward:
        push de
        ld bc, 0
        ld hl, (history_current_ptr)
        ON_HL_IS_NULL_GOTO(_history_search_backward_return)
        call history_iterator_back
        call copy_iterator_to_search_result
        SETUP_SEARCH_RESULT()
_history_search_backward_return:
        pop de
        ret


        ; Searches forward through the history, revriving the next line
        ; Returns: HL - the pointer to the line
        ;          BC - length of the line
        ; Alters: IX, A, HL
zealline_history_search_forward:
        push de
        ld bc, 0
        ld hl, (history_current_ptr)
        ON_HL_IS_NULL_GOTO(_history_search_forward_return)
        call history_iterator_forward
        call copy_iterator_to_search_result
        SETUP_SEARCH_RESULT()
_history_search_forward_return:
        pop de
        ret


        ; "zealline_add_history" stores a command to the history
        ;   Stores the NULL-terminated string from HL as into the ringbuffer.
        ;   In the case the ringbuffer is full old values will be removed from
        ;   in order to create space for the new line.
        ;
        ;   There is some kind of alignment for the history_entry struct that is
        ;   written to the ringbuffer which ensures that the "header" of the string
        ;   is never going across the end of the ringbuffer. This is achieved by
        ;   ensuring that the starting address of each entry is aligned to a 4-byte
        ;   boundary. Since the header is 3 bytes long (next pointer + length byte),
        ;   it will always fit within the remaining space before the boundary.
        ; Parameter:
        ;       HL - Pointer to the NULL-terminated string
        ; Alters: A, IX, IY
        ; Returns:
        ;   A  - ERR_SUCCESS on success, error value else
zealline_add_history:
        push hl
        push de
        push bc
        ld de, history_ringbuffer
        call strlen                                     ; BC is stringlength
        ld a, b
        or a
        jp nz, _add_history_error
        ld a, c                                         ; C is stringlength
        cp MAX_LINE_LENGTH
        jp nc, _add_history_error
        inc c                                           ; line length: Add 1 for NULL Byte
        ex de, hl                                       ; store line in DE
        ld hl, (history_current_ptr)
        ON_HL_IS_NULL_GOTO(_add_history_first_entry)    ; Add the first Element
        ; regular insert into the ringbuffer
        ; Keep the buffer and length on the stack
        push de
        push bc
        ; Calculate the address were we are going to write to
        ld hl, (history_current_ptr)                    ; Load the address of the entry into HL and IX
        ASSERT(history_entry_line_len == 2)
        ; HL is aligned on 4 for sure
        inc l
        inc l
        ld a, (hl)                                      ; Load the length of that entry into A
        inc l                                           ; Point on the string
        ; ADD_HISTORY_ALIGNMENT()
        ADD_HL_A()                                      ; => HL points to the next address we want to write to
        call align_hl
        ON_REG_VALID_GOTO(H, L, _add_history_check_for_space)
        ld a, b
        ld bc, -HISTORY_SIZE
        add hl, bc                                      ; subtract rinbuffer_size from HL
_add_history_check_for_space:
        ld b, a                                         ; Put the size back is B
        call is_history_space_available                 ; checks if we have enough space in the ringbuffer
        or a
        jp z, _add_history_add_entry
        ; Drop the element - Because of the alignment this is happening without potential wrap-around
        ; Save HL in BC
        ld b, h
        ld c, l
        ; Performs `current.next = current.next.next`
        ld hl, (history_current_ptr)
        push hl
        ld a, (hl)
        inc l
        ld h, (hl)
        ld l, a
        ; HL points to the "next"'s next entry, copy it to the current's next
        pop de
        ldi
        ldi
        ; Restore HL
        ld h, b
        ld l, c
        jp _add_history_check_for_space
_add_history_add_entry:
        ; Append history element to HL
        ; Get the former current entry in HL and the new entry in DE
        ex de, hl
        ld hl, (history_current_ptr)
        ; Set the new entry as the current
        ld (history_current_ptr), de
        ; Copy the "next" field from the former current to the new entry
        ; new_entry.next[0] = former_entry.next[0]
        ASSERT history_entry_next==0
        ld a, (hl)
        ld (de), a
        ; former_entry.next[0] = E
        ld (hl), e
        ; A = former_entry.next[1]
        ; former_entry.next[1] = D
        inc hl
        ld a, (hl)
        ld (hl), d
        ; new_entry.next[1] = A
        inc de
        ld (de), a
        ; copy line (with wrap-around handling and null terminator check)
        ; put the new entry in DE, and the string in HL
        inc de
        ; DE points to the size
        pop bc
        ld a, c
        ld (de), a
        inc de
        ; DE points to the new entry char array, get the string from the stack
        pop hl
_add_history_add_entry_copy_loop:
        ld a, (hl)                              ; Load a byte from the string
        ldi                                     ; Copy from HL to DE
        or a
        jr z, _add_history_success              ; Return from the function if null terminator is encountered
        ON_REG_VALID_GOTO(D, E, _add_history_add_entry_copy_loop)
        ld hl, history_ringbuffer               ; Wrap around to the beginning of the buffer
        jr _add_history_add_entry_copy_loop
_add_history_first_entry:
        ld hl, history_ringbuffer
        ld (history_current_ptr), hl                        ; point to the first entry
        ld (history_ringbuffer + history_entry_next), hl    ; copy address to self
        ld a, c
        ld (history_ringbuffer + history_entry_line_len), a ; line length with NULL byte
        ; copy line
        ld hl, history_ringbuffer + history_entry_line_ptr  ; hl - dest & de - string to copy
        ex de, hl                                           ; de - dest & hl - string to copy
        ; B should already be 0 here
        ldir
_add_history_success:
        call zealline_reset_history_search
        ld a, ERR_SUCCESS
_add_history_ret:
        pop bc
        pop de
        pop hl
        ret
_add_history_error:
        ld a, ERR_FAILURE
        jr _add_history_ret


        ; ---------------------------------------------------------------------
        ; PRIVATE_FUNCTIONS (all to be call'ed)
        ; ---------------------------------------------------------------------

        ; Turns the iterator one entry backwards
        ; Returns: BC - value of (history_iterator_pr)
        ; Alters: A, BC, DE, HL
history_iterator_back:
        ld hl, (history_iterator_ptr)
        ld a, h
        or l
        jr z, _history_iterator_back_use_current_ptr
        ld d, h                                         ; store HL in DE, our destination if the prev element was found
        ld e, l
        ASSERT history_entry_next==0                    ; so we can short-cut and use (hl) to load the next node
_history_iterator_back_loop:
        ld b, h
        ld c, l
        ; current = current.next where current is HL
        ld a, (hl)
        inc l
        ld h, (hl)
        ld l, a
        ; Compare HL and DE, A already contains L
        cp e
        jr nz, _history_iterator_back_loop
        ld a, h
        cp d
        jr nz, _history_iterator_back_loop              ; if next node is equal to DE then we have found it
        ; BC is the previous node address
        ld (history_iterator_ptr), bc
        ret
_history_iterator_back_use_current_ptr:
        ld hl, (history_current_ptr)
        ld (history_iterator_ptr), hl
        ret


        ; Turns the iterator one entry forward
        ; Alters: A, BC, HL
history_iterator_forward:
        ld hl, (history_iterator_ptr)
        ld a, h
        or l
        jp nz, _history_iterator_forward_get_next
        ld hl, (history_current_ptr)
_history_iterator_forward_get_next:
        ld a, (hl)
        inc l                                           ; HL is aligned on 4 for sure
        ld h, (hl)
        ld l, a
        ld (history_iterator_ptr), hl
        ret


        ; Copy the current iterator entry to history_search_result
        ; Alters: A, BC, DE, HL, IX
copy_iterator_to_search_result:
        ld hl, (history_iterator_ptr)
        ; HL is algined on 4 for sure
    REPT history_entry_line_len
        inc l
    ENDR
        ld c, (hl)
        ld b, 0
        ASSERT(history_entry_line_ptr == history_entry_line_len + 1)
        inc l
        ld de, history_search_result
_copy_iterator_to_search_result_copy_loop:
        ldi
        ld a, c
        or a
        ret z
        ON_REG_VALID_GOTO(H, L, _copy_iterator_to_search_result_copy_loop)
        ld hl, history_ringbuffer
        jr _copy_iterator_to_search_result_copy_loop


        ; is_history_space_available
        ; Parameters:
        ;       HL - Address want to write to
        ;       B - required space
        ; Returns:
        ;       A - 0 if we have enough space
        ;       A - non-zero if we dont have enough space
        ; Alters:
        ;       DE
is_history_space_available:
        push hl
        ASSERT history_entry_next==0
        ; Put the address we want to write to in DE
        ex hl, de
        ld hl, (history_current_ptr)            ; Address of current Node
        ld a, (hl)
        inc l                                   ; HL was aligned on 4 for sure
        ld h, (hl)
        ld l, a
        or a                                    ; Remove carry flag
        sbc hl, de                              ; Calculate the difference between DE (start address) and HL (oldest element)
        jp p, _history_space_available_positive ; If the result is negative, we need to wrap around
        add hl, HISTORY_SIZE                    ; therefore we add HISTORY_SIZE, now HL is the number of free bytes
_history_space_available_positive:
        ; Compare the available space (HL) with the required space (B)
        ld a, h
        or a
        jp nz, _history_space_available
        ld a, l            ; Compare the low byte of HL with B
        cp b
        jr c, _history_space_not_available  ; Not enough space, A is not 0 for sure
_history_space_available:
        xor a              ; Set A to 0
_history_space_not_available:
        pop hl
        ret


        ; ---------------------------------------------------------------------
        SECTION BSS
        ; ---------------------------------------------------------------------

history_ringbuffer:         defs HISTORY_SIZE, 0
history_ringbuffer_end:
history_current_ptr:        defw 0 ; pointer into the history ringbuffer
history_iterator_ptr:       defw 0 ; pointer for the search iterator
history_search_result:      defs MAX_LINE_LENGTH, 0
