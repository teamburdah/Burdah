; Bootloader ini untuk Burdah (CLI Mode) 1.0 beta – hingga seterusnya
; Kompatibel dengan prosesor 32-bit (ini tujuan utama dari OS ini, karena sistem 16-bit hanya pada Burdah 0.x saja yang berbasis FreeDOS)
; Dihasilkan oleh Blackbox AI (direvisi hingga 10 Juli 2025 dan akan direvisi ulang kedepannya)
; Proyek ini sangat menantang karena akan banyak menggunakan AI dalam memprogramnya
: ===================================

[BITS 16]                ; Bootloader berjalan dalam mode real (16-bit)
[ORG 0x7C00]             ; Lokasi memory dimana BIOS akan memuat bootloader

jmp short start          ; Lompat ke kode start
nop                      ; Padding untuk header BPB

; BIOS Parameter Block (BPB) untuk floppy disk 1.44MB
bpb_oem:            db "BURDAH10"
bpb_bytes_per_sect: dw 512
bpb_sect_per_clust: db 1
bpb_reserved_sects: dw 1
bpb_num_fats:       db 2
bpb_root_entries:   dw 224
bpb_total_sects:    dw 2880
bpb_media:          db 0xF0
bpb_sect_per_fat:   dw 9
bpb_sect_per_track: dw 18
bpb_heads:          dw 2
bpb_hidden_sects:   dd 0
bpb_total_sects_lg: dd 0
bs_drive_num:       db 0
bs_reserved:        db 0
bs_ext_boot_sig:    db 0x29
bs_serial_num:      dd 0x12345678
bs_volume_label:    db "COREDISK   "
bs_file_system:     db "FAT12   "

start:
    ; Setup segment registers
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Simpan nomor drive
    mov [bs_drive_num], dl

    ; Tampilkan pesan loading
    mov si, msg_loading
    call print_string

    ; Memuat Root Directory
    call load_root_directory

    ; Cari file kernel (SYSTEM.DAT)
    mov cx, word [bpb_root_entries]
    mov di, 0x0200            ; Lokasi Root Directory yang dimuat
.search_kernel:
    push cx
    push di
    mov cx, 11                ; Panjang nama file FAT12
    mov si, kernel_name
    push di
    rep cmpsb
    pop di
    je .found_kernel
    pop di
    add di, 32                ; Berpindah ke entry berikutnya (32 bytes per entry)
    pop cx
    loop .search_kernel

    ; Kernel tidak ditemukan
    mov si, msg_kernel_missing
    call print_string
    jmp $                     ; Hentikan eksekusi

.found_kernel:
    pop di
    pop cx

    ; Dapatkan cluster pertama dari kernel
    mov dx, word [di + 26]    ; Offset 26 dalam directory entry adalah cluster pertama
    mov word [cluster], dx

    ; Muat FAT ke memory
    call load_fat

    ; Muat kernel ke memory di 0x1000:0x0000 (ES:BX)
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

.load_kernel_loop:
    ; Baca sebuah cluster dari kernel
    mov ax, word [cluster]
    call read_cluster

    ; Hitung lokasi cluster berikutnya
    mov ax, [cluster]
    mov cx, ax
    mov dx, ax
    shr dx, 1
    add cx, dx                ; cluster * 1.5
    mov si, fat_buffer
    add si, cx
    mov dx, word [si]
    test ax, 1
    jnz .odd_cluster
.even_cluster:
    and dx, 0x0FFF            ; Ambil 12 bit pertama
    jmp .done
.odd_cluster:
    shr dx, 4                 ; Ambil 12 bit berikutnya
.done:
    mov word [cluster], dx
    cmp dx, 0x0FF8            ; Apakah ini cluster terakhir?
    jae .kernel_loaded
    add bx, [bytes_per_sect]
    jmp .load_kernel_loop

.kernel_loaded:
    ; Set video mode ke VGA text 80x25
    mov ax, 0x0003
    int 0x10

    ; Jalankan kernel
    mov dl, byte [bs_drive_num] ; Berikan nomor drive ke kernel
    jmp 0x1000:0x0000          ; Lompat ke kernel

    ; Tidak akan pernah sampai di sini
    jmp $

; Fungsi-fungsi pembantu
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

load_root_directory:
    ; Hitung ukuran root directory
    mov ax, word [bpb_root_entries]
    mov bx, 32
    mul bx
    div word [bpb_bytes_per_sect]
    xchg ax, cx               ; cx = jumlah sektor root directory

    ; Hitung lokasi root directory
    mov al, byte [bpb_num_fats]
    mul word [bpb_sect_per_fat]
    add ax, word [bpb_hidden_sects]
    add ax, word [bpb_reserved_sects]
    mov word [datasector], ax ; Simpan awal data sector

    ; Muat root directory ke 0x0200:0x0000
    mov bx, 0x0200
    mov es, bx
    xor bx, bx
    call read_sectors
    ret

load_fat:
    ; Hitung lokasi FAT
    mov ax, word [bpb_hidden_sects]
    add ax, word [bpb_reserved_sects]
    mov bx, 0x0200
    mov es, bx
    xor bx, bx

    ; Muat FAT
    mov cx, word [bpb_sect_per_fat]
    call read_sectors
    ret

read_cluster:
    ; Konversi cluster ke LBA
    sub ax, 2
    xor ch, ch
    mov cl, byte [bpb_sect_per_clust]
    mul cx
    add ax, word [datasector]

    ; Baca cluster
    mov cx, 1
    call read_sectors
    ret

read_sectors:
    ; AX = LBA, CX = jumlah sektor, ES:BX = buffer tujuan
    mov di, 5                 ; Maksimal 5 percobaan
.retry:
    pusha
    sub ax, 1                 ; LBA ke CHS mulai dari 0
    xor dx, dx
    div word [bpb_sect_per_track]
    mov cx, dx
    add cx, 1                 ; Sektor = (LBA % SectorsPerTrack) + 1
    xor dx, dx
    div word [bpb_heads]
    mov dh, dl                ; Kepala = (LBA / SectorsPerTrack) % Heads
    mov ch, al                ; Silinder = (LBA / SectorsPerTrack) / Heads
    mov dl, byte [bs_drive_num]
    mov al, cl                ; Jumlah sektor untuk dibaca
    mov ah, 0x02              ; Fungsi BIOS baca sektor
    int 0x13
    popa
    jnc .done                 ; Jika tidak ada error, selesai

    ; Reset disk
    xor ax, ax
    int 0x13

    ; Coba lagi
    dec di
    jnz .retry
    jmp disk_error
.done:
    ret

disk_error:
    mov si, msg_disk_error
    call print_string
    jmp $

; Variabel
kernel_name       db "SYSTEM  DAT"
msg_loading       db "starting burdah...", 0x0D, 0x0A, 0
msg_kernel_missing db 0x0D, 0x0A, "Sorry... please check your system disk. Kernel is missing :(", 0x0D, 0x0A, 0
msg_disk_error    db "Disk error! Replace disk :((", 0x0D, 0x0A, 0
cluster           dw 0
bytes_per_sect    dw 512
datasector        dw 0
fat_buffer        equ 0x0200

; Padding dan signature bootloader
times 510-($-$$) db 0
dw 0xAA55