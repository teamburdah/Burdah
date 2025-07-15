[BITS 32]
[ORG 0x1000]

VIDEO_MEMORY equ 0xb8000
DARK_GREEN_GRAY equ 0x2F    ; Dark green (2) background with light gray (F) text
SCREEN_WIDTH equ 80
SCREEN_HEIGHT equ 25
BUFFER_SIZE equ 4000        ; Buffer for storing text (80x50 lines)

start:
    ; Clear screen with dark green background
    mov edi, VIDEO_MEMORY
    mov ecx, SCREEN_WIDTH * SCREEN_HEIGHT
    mov ax, 0x200F          ; Space character with color attribute
    rep stosw
    
    ; Reset video memory pointer
    mov edi, VIDEO_MEMORY
    mov ah, DARK_GREEN_GRAY
    
    ; Display initial message
    mov esi, hello_msg
    call print_string
    
    ; Initialize variables
    mov dword [cursor_x], 0
    mov dword [cursor_y], 1      ; Start below hello message
    mov dword [screen_offset], 0 ; Starting screen offset
    mov dword [total_lines], 1   ; Current number of lines

main_loop:
    ; Wait for keypress
    mov ah, 0
    int 0x16
    
    cmp al, 0x0D    ; Enter key
    je handle_enter
    
    ; Regular character input
    mov ah, DARK_GREEN_GRAY
    call store_char
    call update_screen
    jmp main_loop

handle_enter:
    ; Move to next line
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    inc dword [total_lines]
    
    ; Check if we need to scroll
    mov eax, [cursor_y]
    cmp eax, SCREEN_HEIGHT
    jl no_scroll
    
    ; Scroll screen
    inc dword [screen_offset]
    dec dword [cursor_y]
    
no_scroll:
    call update_screen
    jmp main_loop

; Store character in text buffer
store_char:
    push eax
    mov ebx, [cursor_y]
    sub ebx, [screen_offset]  ; Adjust for scrolling
    imul ebx, SCREEN_WIDTH
    add ebx, [cursor_x]
    mov [text_buffer + ebx * 2], ax
    inc dword [cursor_x]
    
    ; Wrap text if reached end of line
    cmp dword [cursor_x], SCREEN_WIDTH
    jl .done
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    inc dword [total_lines]
    
    ; Check for scrolling
    mov eax, [cursor_y]
    cmp eax, SCREEN_HEIGHT
    jl .done
    inc dword [screen_offset]
    dec dword [cursor_y]
    
.done:
    pop eax
    ret

; Update screen contents
update_screen:
    pusha
    mov edi, VIDEO_MEMORY
    
    ; Display hello message at top
    mov esi, hello_msg
    call print_string
    
    ; Calculate starting position in buffer
    mov eax, [screen_offset]
    imul eax, SCREEN_WIDTH * 2
    mov esi, text_buffer
    add esi, eax
    
    ; Copy visible portion of buffer to screen
    mov ecx, SCREEN_HEIGHT - 1  ; Reserve first line for hello message
    mov edx, SCREEN_WIDTH * 2   ; Skip first line of video memory
    add edi, edx
    
.copy_line:
    push ecx
    mov ecx, SCREEN_WIDTH
    
.copy_char:
    mov ax, [esi]
    or ax, ax
    jz .blank_char
    mov word [edi], ax
    jmp .next_char
    
.blank_char:
    mov ax, 0x200F          ; Space with color attribute
    mov word [edi], ax
    
.next_char:
    add esi, 2
    add edi, 2
    loop .copy_char
    
    pop ecx
    loop .copy_line
    
    popa
    ret

print_string:
    push eax
    push edi
.loop:
    lodsb
    test al, al
    jz .done
    mov ah, DARK_GREEN_GRAY
    mov word [edi], ax
    add edi, 2
    jmp .loop
.done:
    pop edi
    pop eax
    ret

; Data
hello_msg: db 'Hello user!', 0

; Variables
cursor_x: dd 0
cursor_y: dd 0
screen_offset: dd 0      ; Current scroll position
total_lines: dd 0        ; Total number of lines in buffer

; Text buffer
align 4
text_buffer: times BUFFER_SIZE dw 0

; Padding
times 16384-($-$$) db 0  ; Increased padding for larger kernel