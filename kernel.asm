[BITS 32]
[ORG 0x1000]           ; Set the origin point where bootloader will load the kernel

VIDEO_MEMORY equ 0xb8000
DARK_GREEN_GRAY equ 0x2F    ; Dark green (2) background with light gray (F) text

start:
    ; Set up registers
    mov edi, VIDEO_MEMORY
    mov ah, DARK_GREEN_GRAY  ; Color attribute
    
    ; Display initial message
    mov esi, hello_msg
    call print_string
    
    ; Initialize cursor position
    mov dword [cursor_x], 0
    mov dword [cursor_y], 1  ; Start on the line after hello message

input_loop:
    ; Wait for keypress
    mov ah, 0
    int 0x16        ; BIOS keyboard interrupt
    
    cmp al, 0x0D    ; Check if Enter key (carriage return)
    je new_line
    
    ; Display character
    mov ah, DARK_GREEN_GRAY
    mov word [edi + (cursor_y * 160) + (cursor_x * 2)], ax
    
    ; Update cursor
    inc dword [cursor_x]
    cmp dword [cursor_x], 80
    jl input_loop
    
new_line:
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    cmp dword [cursor_y], 25
    jl input_loop
    mov dword [cursor_y], 0
    jmp input_loop

print_string:
    ; Print string pointed to by ESI
.loop:
    lodsb           ; Load character from ESI into AL
    test al, al     ; Check if end of string (null terminator)
    jz .done
    mov ah, DARK_GREEN_GRAY
    mov word [edi], ax
    add edi, 2
    jmp .loop
.done:
    ret

; Data section
hello_msg: db 'Hello user!', 0

; BSS section (variables)
cursor_x: dd 0
cursor_y: dd 0

; Pad to make sure we have enough space
times 4096-($-$$) db 0   ; Pad to 4KB