[BITS 16]                ; Bootloader berjalan dalam mode real (16-bit)
[ORG 0x7C00]            ; Lokasi memory dimana BIOS akan memuat bootloader

jmp short start         ; Lompat ke kode start
nop                     ; Padding untuk identifier

;; El Torito Boot Record
boot_record:
    db 0x00                    ; Boot Record Indicator
    db 'CD001'                ; Standard Identifier
    db 0x01                    ; Version
    db 'EL TORITO'            ; El Torito Identifier
    times 32 db 0             ; Reserved
    dd boot_catalog           ; Boot Catalog Location

;; Disk Address Packet structure
dap:
    db 0x10                   ; DAP size
    db 0                      ; unused
    .count:    dw 1           ; number of sectors to read
    .offset:   dw 0           ; destination offset
    .segment:  dw 0           ; destination segment
    .lba:      dq 0           ; starting LBA

start:
    ; Setup segment registers
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Simpan drive number
    mov [drive_num], dl

    ; Cek support Extended Read
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [drive_num]
    int 0x13
    jc no_extended_support

    ; Tampilkan pesan loading
    mov si, msg_loading
    call print_string

    ; Load kernel
    call load_kernel

    ; Jika berhasil, lompat ke kernel
    mov dl, [drive_num]      ; Pass drive number ke kernel
    jmp 0x1000:0x0000

no_extended_support:
    mov si, msg_no_ext
    call print_string
    jmp $

;; Fungsi-fungsi utama
load_kernel:
    ; Setup DAP untuk membaca kernel
    mov word [dap.count], 32      ; Baca 32 sektor (64KB)
    mov word [dap.offset], 0
    mov word [dap.segment], 0x1000
    mov dword [dap.lba], 20       ; Mulai dari sektor 20 (setelah boot record)

    ; Baca kernel menggunakan Extended Read
    mov ah, 0x42
    mov dl, [drive_num]
    mov si, dap
    int 0x13
    jc read_error
    ret

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

read_error:
    mov si, msg_disk_error
    call print_string
    jmp $

;; Data
drive_num:          db 0
msg_loading:        db 'Starting Burdah CD', 0x0D, 0x0A, 0
msg_disk_error:     db 'Error reading disk!', 0x0D, 0x0A, 0
msg_no_ext:         db 'Extended read not supported!', 0x0D, 0x0A, 0

;; Boot Catalog
align 4
boot_catalog:
    ; Validation Entry
    db 0x01                    ; Header ID
    db 0x00                    ; Platform ID
    dw 0x0000                 ; Reserved
    db 'BURDAH              ' ; ID String
    dw 0xAA55                 ; Checksum
    db 0x55, 0xAA             ; Signature

    ; Initial/Default Entry
    db 0x88                    ; Bootable
    db 0x00                    ; Boot media type
    dw 0x0000                 ; Load segment
    db 0x00                    ; System type
    db 0x00                    ; Unused
    dw 0x0001                 ; Sector count
    dd 0x00000014             ; Load RBA
    times 20 db 0             ; Unused

; Padding dan signature
times 2048-($-$$) db 0        ; Pad to 2048 bytes (CD sector size)
dw 0xAA55                     ; Boot signature