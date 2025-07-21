[BITS 16]                ; Bootloader berjalan dalam mode real (16-bit)
[ORG 0x7C00]            ; Lokasi memory dimana BIOS akan memuat bootloader

jmp short start         ; Lompat ke kode start
nop                     ; Padding untuk identifier

;; Konstanta ISO 9660
SECTOR_SIZE     equ 2048
PVD_SECTOR      equ 16        ; Primary Volume Descriptor biasanya di sector 16
ROOT_DIR_OFFSET equ 156       ; Offset ke root directory dalam PVD

;; Struktur Directory Record
struc DIR_RECORD
    .length:     resb 1
    .ext_length: resb 1
    .extent:     resd 1
    .size:       resd 1
    .date:       resb 7
    .flags:      resb 1
    .unit_size:  resb 1
    .gap_size:   resb 1
    .vol_seq:    resw 1
    .name_len:   resb 1
    .name:       resb 32
endstruc

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

    ; Tampilkan pesan loading
    mov si, msg_loading
    call print_string

    ; Baca Primary Volume Descriptor
    mov eax, PVD_SECTOR
    mov bx, buffer
    call read_sector

    ; Dapatkan lokasi root directory
    mov eax, [buffer + ROOT_DIR_OFFSET]    ; Load extent location
    mov [current_sector], eax

; Dapatkan memory map biar nantinya bisa mendapatkan informasi tentang RAM. (Kalau gak bisa dicompile, coba pindah baris)
get_memory_map:
    mov di, 0x8000          ; Lokasi penyimpanan memory map
    xor ebx, ebx            ; Harus 0 untuk panggilan pertama
    mov edx, 0x534D4150     ; 'SMAP' signature
    mov eax, 0xE820         ; Fungsi BIOS
    mov [es:di + 20], dword 1 ; Force valid ACPI 3.X entry
    mov ecx, 24             ; Ukuran buffer untuk tiap entry
    int 0x15               ; BIOS interrupt
    jc .failed             ; Carry flag = error

    ; Simpan jumlah entry di 0x7E00
    mov [0x7E00], dword eax  

    ; Cari SYSTEM.DAT
    call find_system_dat
    jc .error_no_system

    ; Load SYSTEM.DAT ke memory
    call load_system_dat

    ; Jika berhasil, lompat ke kernel
    mov dl, [drive_num]
    jmp 0x1000:0000

.error_no_system:
    mov si, msg_no_system
    call print_string
    jmp $

;; Fungsi untuk membaca satu sektor
read_sector:
    ; eax = LBA sector to read
    ; es:bx = buffer to read into
    push si
    push ax
    push cx
    push dx

    mov [dap.lba], eax
    mov [dap.segment], es
    mov [dap.offset], bx

    mov ah, 0x42
    mov dl, [drive_num]
    mov si, dap
    int 0x13
    
    pop dx
    pop cx
    pop ax
    pop si
    ret

;; Fungsi untuk mencari SYSTEM.DAT
find_system_dat:
    mov bx, buffer
.next_record:
    ; Periksa apakah ini akhir direktori
    cmp byte [bx], 0
    je .not_found

    ; Bandingkan nama file
    mov si, system_dat_name
    mov cx, 11              ; Panjang "SYSTEM.DAT;1"
    mov di, bx
    add di, DIR_RECORD.name
    push bx
    repe cmpsb
    pop bx
    je .found

    ; Pindah ke record berikutnya
    movzx ax, byte [bx]    ; Panjang record
    add bx, ax
    jmp .next_record

.found:
    ; Simpan lokasi dan ukuran file
    mov eax, [bx + DIR_RECORD.extent]
    mov [system_dat_sector], eax
    mov eax, [bx + DIR_RECORD.size]
    mov [system_dat_size], eax
    clc
    ret

.not_found:
    stc
    ret

;; Fungsi untuk load SYSTEM.DAT
load_system_dat:
    mov eax, [system_dat_sector]
    mov bx, 0
    mov es, bx
    mov bx, 0x10000        ; Load ke 0x1000:0000

.load_loop:
    call read_sector
    add bx, SECTOR_SIZE
    inc eax
    mov ecx, [system_dat_size]
    sub ecx, SECTOR_SIZE
    mov [system_dat_size], ecx
    jg .load_loop
    ret

;; Data
drive_num:           db 0
current_sector:      dd 0
system_dat_sector:   dd 0
system_dat_size:     dd 0
system_dat_name:     db 'SYSTEM.DAT;1'
msg_loading:         db 'Starting Burdah...', 13, 10, 0
msg_no_system:       db 'SYSTEM.DAT not found! Check this CD', 13, 10, 0

;; Disk Address Packet
dap:
    db 0x10                   ; size of DAP
    db 0                      ; unused
    .count:    dw 1           ; number of sectors
    .offset:   dw 0           ; destination offset
    .segment:  dw 0           ; destination segment
    .lba:      dd 0           ; LBA to read
    .lba_high: dd 0           ; high 32-bits of LBA (not used)

;; Buffer untuk membaca data
buffer:

; Padding dan signature
times 2048-($-$$) db 0
dw 0xAA55