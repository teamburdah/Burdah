[BITS 16]
[ORG 0x7C00]

jmp short start
nop

; ISO 9660 Primary Volume Descriptor
iso_pvd:
    db 0x01                    ; Volume Descriptor Type
    db "CD001"                 ; Standard Identifier
    db 0x01                    ; Version
    ; ... (tambahkan field ISO 9660 lainnya)

; El Torito Boot Record
boot_record:
    db 0x00                    ; Boot Record Indicator
    db "EL TORITO SPECIFICATION" ; ISO 9660 Identifier
    ; ... (tambahkan field El Torito lainnya)

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
    mov [drive_number], dl

    ; Gunakan Extended Read untuk membaca sektor
    mov ah, 0x42
    mov dl, [drive_number]
    mov si, disk_address_packet
    int 0x13
    
    ; ... (lanjutkan dengan kode boot)

; Disk Address Packet untuk Extended Read
disk_address_packet:
    db 0x10                    ; Size of packet
    db 0                       ; Reserved
    dw 1                       ; Number of blocks to transfer
    dw 0                       ; Transfer buffer offset
    dw 0                       ; Transfer buffer segment
    dq 0                       ; Starting LBA

drive_number db 0