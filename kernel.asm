; Kernel x86 untuk bootloader FAT12
; Nama file: SYSTEM.DAT (11 karakter uppercase)
; Dimuat di 2000h:0000h (ORG 0x0000 karena segmen 2000h)
; Format: Binary flat (NASM syntax)

[BITS 16]
[ORG 0x0000]

; Entry point (dipanggil oleh bootloader dengan DL = boot device)
start:
    ; Setup segment registers
    mov ax, 2000h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE      ; Stack pointer di real mode

    ; Simpan boot device
    mov [boot_device], dl

    ; Tampilkan pesan persiapan
    mov si, msg_prepare
    call print_string_rm

    ; Aktifkan A20 line
    call enable_a20
    jnc .a20_ok
    mov si, msg_a20_fail
    call print_string_rm
    jmp $

.a20_ok:
    ; Load GDT
    lgdt [gdt_descriptor]

    ; Nonaktifkan interrupt
    cli

    ; Masuk ke protected mode
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax

    ; Jauh jump untuk flush pipeline dan set CS
    jmp CODE_SEG:init_pm

[BITS 32]
init_pm:
    ; Setup segment registers untuk protected mode
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Setup stack pointer 32-bit
    mov esp, 0x90000

    ; Clear screen dengan warna biru tua
    call clear_screen_pm

    ; Tampilkan pesan di protected mode
    mov esi, msg_pm_active
    mov edi, 0xB8000 + (0 * 80 * 2) ; Baris pertama
    call print_string_pm

    mov esi, msg_hello
    mov edi, 0xB8000 + (1 * 80 * 2) ; Baris kedua
    call print_string_pm

    mov esi, msg_wkwkwk
    mov edi, 0xB8000 + (2 * 80 * 2) ; Baris ketiga
    call print_string_pm

    ; Halt (loop tak berujung)
    cli
.hlt_loop:
    hlt
    jmp .hlt_loop

[BITS 16]
; Fungsi untuk mengaktifkan A20 line
enable_a20:
    ; Coba metode BIOS
    mov ax, 0x2401
    int 0x15
    jnc .success

    ; Coba metode keyboard controller
    call .wait_kbc
    mov al, 0xAD
    out 0x64, al        ; Nonaktifkan keyboard

    call .wait_kbc
    mov al, 0xD0
    out 0x64, al        ; Baca output port

    call .wait_kbc_data
    in al, 0x60
    push eax

    call .wait_kbc
    mov al, 0xD1
    out 0x64, al        ; Tulis output port

    call .wait_kbc
    pop eax
    or al, 2            ; Set A20 bit
    out 0x60, al

    call .wait_kbc
    mov al, 0xAE
    out 0x64, al        ; Aktifkan keyboard

    call .wait_kbc

    ; Verifikasi A20 aktif
    call check_a20
    jc .fail
.success:
    clc
    ret
.fail:
    stc
    ret

.wait_kbc:
    in al, 0x64
    test al, 2
    jnz .wait_kbc
    ret

.wait_kbc_data:
    in al, 0x64
    test al, 1
    jz .wait_kbc_data
    ret

; Fungsi untuk memeriksa A20 line
check_a20:
    push es
    push di
    push si

    xor ax, ax
    mov es, ax
    mov di, 0x0500

    mov ax, 0xFFFF
    mov ds, ax
    mov si, 0x0510

    mov al, [es:di]
    push ax

    mov al, [ds:si]
    push ax

    mov byte [es:di], 0x00
    mov byte [ds:si], 0xFF

    cmp byte [es:di], 0xFF

    pop ax
    mov [ds:si], al

    pop ax
    mov [es:di], al

    je .a20_off
    clc
    jmp .done
.a20_off:
    stc
.done:
    pop si
    pop di
    pop es
    ret

; Fungsi untuk mencetak string di real mode
; SI = alamat string (null-terminated)
print_string_rm:
    pusha
    mov ah, 0x0E        ; BIOS teletype function
    mov bh, 0x00        ; Page number
    mov bl, 0x07        ; Attribute (light gray on black)
.loop:
    lodsb
    or al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    popa
    ret

[BITS 32]
; Fungsi untuk mencetak string di protected mode
; ESI = alamat string (null-terminated)
; EDI = alamat VGA buffer
print_string_pm:
    pusha
    mov ah, 0x1F        ; Attribute: putih (0x0F) di biru tua (0x10)
.loop:
    lodsb
    or al, al
    jz .done
    stosw               ; Simpan karakter + attribute
    jmp .loop
.done:
    popa
    ret

; Fungsi untuk membersihkan layar di protected mode
clear_screen_pm:
    pusha
    mov edi, 0xB8000
    mov ecx, 80 * 25     ; Jumlah karakter di layar
    mov ah, 0x10         ; Background biru tua
    mov al, ' '          ; Karakter spasi
.clear_loop:
    stosw
    loop .clear_loop
    popa
    ret

; Data dan variabel
boot_device db 0

; Pesan-pesan
msg_prepare db 'Switching to 32 bit...', 0
msg_a20_fail db 'A20 activation failed!', 0
msg_pm_active db 'Protected mode active!', 0
msg_hello db 'Hello', 0
msg_wkwkwk db 'wkwkwk', 0

; GDT (Global Descriptor Table)
gdt_start:
gdt_null:               ; Null descriptor
    dd 0x0
    dd 0x0

gdt_code:               ; Code segment descriptor
    dw 0xFFFF           ; Limit (bits 0-15)
    dw 0x0              ; Base (bits 0-15)
    db 0x0              ; Base (bits 16-23)
    db 10011010b        ; 1st flags, type flags
    db 11001111b        ; 2nd flags, Limit (bits 16-19)
    db 0x0              ; Base (bits 24-31)

gdt_data:               ; Data segment descriptor
    dw 0xFFFF           ; Limit (bits 0-15)
    dw 0x0              ; Base (bits 0-15)
    db 0x0              ; Base (bits 16-23)
    db 10010010b        ; 1st flags, type flags
    db 11001111b        ; 2nd flags, Limit (bits 16-19)
    db 0x0              ; Base (bits 24-31)

gdt_end:

; GDT descriptor
gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; Size of GDT
    dd gdt_start                ; Start address of GDT

; Definisikan konstanta untuk segment descriptor offsets
CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

; Padding untuk memastikan ukuran file kelipatan 512 byte
times 1024 - ($-$$) db 0