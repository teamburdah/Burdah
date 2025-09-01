; Kernel "Hello World" untuk bootloader FAT12
; Compile dengan: nasm -f bin -o SYSTEM.DAT kernel.asm
; Dihasilkan melalui perbudakan Deepseek AI :D

BITS 16
ORG 0x0000      ; Akan di-load di 2000h:0000h (2000h << 4 + 0000h = 20000h)

%include "keyboard.inc"

start:
    ; Set segment registers
    mov ax, 2000h
    mov ds, ax
    mov es, ax
    
    ; Set stack (di bawah kernel)
    mov ax, 0x0000
    mov ss, ax
    mov sp, 0xFFFF
    
    ; set mode teks 80x25
    mov ax, 0x03
    int 10h

    ; clear screen + isi dengan biru tua (background) dan putih (foreground)
    mov ax, 0600h       ; AH=06h scroll up, AL=0 → clear semua
    mov bh, 1Fh         ; atribut: foreground putih (0Fh), background biru tua (1h<<4)
    mov cx, 0000h       ; sudut kiri atas (row=0, col=0)
    mov dx, 184Fh       ; sudut kanan bawah (row=24, col=79)
    int 10h

    ; Print welcome message
    mov si, welcome_msg
    call print_string

 ; Jalankan shell loop (prompt + edit baris + history)
    call kb_shell_loop

    ; Kalau keluar dari loop, berhenti
.halt:
    cli
    hlt
    jmp .halt

; --------------------------------------------
; Subrutin: print_string
; Input: SI = alamat string (null-terminated)
print_string:
    pusha
.print_loop:
    lodsb               ; ambil karakter dari [SI] → AL
    cmp al, 0
    je .done
    cmp al, 0x0A
    je .newline

    mov ah, 0x0E        ; BIOS teletype → otomatis geser kursor
    mov bh, 0x00        ; page 0
    mov bl, 0x0F        ; foreground putih (background tetap biru tua dari langkah 1)
    int 10h
    jmp .print_loop

.newline:
    mov ah, 0x0E
    mov al, 0x0D        ; CR
    int 10h
    mov al, 0x0A        ; LF
    int 10h
    jmp .print_loop

.done:
    popa
    ret

; --------------------------------------------
; Subrutin: print_hex_byte
; Input: AL = byte yang akan dicetak dalam hex
print_hex_byte:
    pusha
    
    mov ah, 0x0E    ; Fungsi BIOS teletype
    mov bh, 0x00    ; Page 0
    mov bl, 0x1F    ; Warna hijau muda di latar hitam
    
    ; Cetak nibble tinggi
    mov dl, al      ; Simpan nilai asli di DL
    shr al, 4
    and al, 0x0F
    mov bx, hex_chars
    xlat
    int 0x10
    
    ; Cetak nibble rendah
    mov al, dl
    and al, 0x0F
    mov bx, hex_chars
    xlat
    int 0x10
    
    popa
    ret

; --------------------------------------------
; Data
welcome_msg:
			db 13, 10, '           #               BURDAH 1.0 ', 13, 10
			db '         #   #             TEST KERNEL', 13, 10
			db '       #       #           ============= ', 13, 10
			db '    ################       COMPILED ON AUG 9, 2025 ', 13, 10
			db '   ##              ##      THANKS :D', 13, 10
			db ' #  #              #  #', 13, 10
			db '#   #                  #', 13, 10
			db ' #  #', 13, 10
			db '   ##', 13, 10
			db '    #', 13, 10
			db '	   #', 13, 10
			db '	     #', 13, 10, 0
			

;bootdev_msg      db 'Boot device: 0x', 0
hex_chars        db '0123456789ABCDEF'
;boot_device      db 0    ; Akan diisi oleh bootloader

; --------------------------------------------
; Padding untuk memastikan ukuran file cukup besar (katanya wajib karena tuntutan bootloader
; (Bootloader mengharapkan file dengan beberapa sector)
times 5120-($-$$) db 0  ; 10 sector (5120 bytes)