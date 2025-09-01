; keyboard.inc
; Mini-shell 16-bit: prompt, edit baris, history, arrow keys, backspace, delete
; Ketergantungan: BIOS int 16h (keyboard), int 10h (video)
; Kompatibel 16-bit NASM (tanpa addressing ilegal)

BITS 16

%define KB_ATTR            1Fh          ; putih di biru
%define KB_MAX_LINE        128
%define KB_HIST_COUNT      8
%define KB_SCREEN_MAX_COL  79           ; kolom terakhir (0..79)

; ------------------------------------------------------------
; State input baris
kb_line_buf:        times KB_MAX_LINE db 0
kb_line_len:        dw 0               ; panjang logis baris
kb_cursor_pos:      dw 0               ; posisi kursor dalam buffer (0..len)
kb_last_drawn_len:  dw 0               ; panjang visual terakhir (untuk clear tail)

; Posisi prompt (row/col) ketika mulai input baris
kb_prompt_row:      db 0
kb_prompt_col:      db 0

; History: ring buffer 8 x 128
kb_hist_buf:        times (KB_HIST_COUNT * KB_MAX_LINE) db 0
kb_hist_count:      db 0               ; jumlah entri valid (0..8)
kb_hist_head:       db 0               ; index next insert (0..7)
kb_hist_view:       db 0FFh            ; 0xFF = tidak sedang view; selain itu index view aktif

; String prompt
kb_prompt_str:      db '> ', 0

; ------------------------------------------------------------
; Public entry: loop shell sederhana
; Cetak prompt → baca baris (edit/history) → echo balik → ulang
kb_shell_loop:
    call kb_init_state
.shell_next:
    call kb_print_prompt
    call kb_read_line

    ; Demo: echo barisnya
    call kb_print_nl
    call kb_print_line_buf
    call kb_print_nl
    jmp .shell_next

; ------------------------------------------------------------
; Init (opsional)
kb_init_state:
    mov word [kb_last_drawn_len], 0
    ret

; ------------------------------------------------------------
; Cetak newline
kb_print_nl:
    pusha
    mov ah, 0Eh
    mov al, 0Dh
    int 10h
    mov al, 0Ah
    int 10h
    popa
    ret

; Cetak prompt dan simpan posisi awal input
kb_print_prompt:
    pusha
    ; ambil posisi kursor saat ini
    mov ah, 03h
    mov bh, 0
    int 10h

    ; cetak prompt via teletype
    mov si, kb_prompt_str
.pr_loop:
    lodsb
    or al, al
    jz .after
    mov ah, 0Eh
    int 10h
    jmp .pr_loop
.after:
    ; simpan posisi awal input (setelah prompt)
    mov ah, 03h
    mov bh, 0
    int 10h
    mov [kb_prompt_row], dh
    mov [kb_prompt_col], dl

    ; reset state baris
    mov word [kb_line_len], 0
    mov word [kb_cursor_pos], 0
    mov word [kb_last_drawn_len], 0
    mov byte [kb_hist_view], 0FFh
    popa
    ret

; ------------------------------------------------------------
; Baca satu baris dengan edit & history
; Hasil: kb_line_buf null-terminated, kb_line_len diset
kb_read_line:
    pusha
.read_key:
    ; tunggu tombol
    mov ah, 00h
    int 16h            ; AL=ASCII (0 jika extended), AH=scan code

    ; Extended? (AL=0)
    cmp al, 0
    jne .check_ascii
    ; gunakan scan code di AH
    mov al, ah
    cmp al, 048h       ; Up
    je .hist_prev
    cmp al, 050h       ; Down
    je .hist_next
    cmp al, 04Bh       ; Left
    je .cursor_left
    cmp al, 04Dh       ; Right
    je .cursor_right
    cmp al, 053h       ; Delete
    je .delete
    jmp .loop

.check_ascii:
    cmp al, 0Dh        ; Enter
    je .enter
    cmp al, 08h        ; Backspace
    je .backspace
    cmp al, 07Fh       ; Delete (ASCII)
    je .delete

    ; printable?
    cmp al, 20h
    jb .loop
    cmp al, 7Eh
    ja .loop
    jmp .printable

.cursor_left:
    call kb_cursor_left
    jmp .loop

.cursor_right:
    call kb_cursor_right
    jmp .loop

.hist_prev:
    call kb_history_prev
    jmp .loop

.hist_next:
    call kb_history_next
    jmp .loop

.backspace:
    call kb_handle_backspace
    jmp .loop

.delete:
    call kb_handle_delete
    jmp .loop

.printable:
    ; AL = karakter
    call kb_insert_char
    jmp .loop

.enter:
    ; null-terminate
    mov bx, [kb_line_len]
    mov byte [kb_line_buf+bx], 0
    ; simpan ke history jika tidak kosong
    cmp bx, 0
    je .done
    call kb_history_add
.done:
    call kb_print_nl
    popa
    ret

.loop:
    jmp .read_key

; ------------------------------------------------------------
; Gerak kursor kiri
kb_cursor_left:
    pusha
    mov ax, [kb_cursor_pos]
    or ax, ax
    jz .out
    dec ax
    mov [kb_cursor_pos], ax
    call kb_move_cursor_visual
.out:
    popa
    ret

; Gerak kursor kanan
kb_cursor_right:
    pusha
    mov ax, [kb_cursor_pos]
    cmp ax, [kb_line_len]
    jae .out
    inc ax
    mov [kb_cursor_pos], ax
    call kb_move_cursor_visual
.out:
    popa
    ret

; ------------------------------------------------------------
; Backspace: hapus char di kiri cursor
kb_handle_backspace:
    pusha
    mov ax, [kb_cursor_pos]
    or ax, ax
    jz .out

    ; pos target setelah backspace
    dec ax
    mov [kb_cursor_pos], ax

    ; shift kiri tail dari pos
    ; count = len - pos - 1 + 1 = len - pos
    mov cx, [kb_line_len]
    sub cx, ax
    jz .shrink
    ; dst = buf + pos
    ; src = buf + pos + 1
    push ds
    push es
    cld
    mov si, kb_line_buf
    mov di, kb_line_buf
    add si, ax
    add di, ax
    inc si
    rep movsb
    pop es
    pop ds
.shrink:
    ; len--
    mov bx, [kb_line_len]
    dec bx
    mov [kb_line_len], bx

    ; redraw full
    call kb_redraw_full
.out:
    popa
    ret

; Delete: hapus char di posisi cursor
kb_handle_delete:
    pusha
    mov ax, [kb_cursor_pos]
    mov bx, [kb_line_len]
    cmp ax, bx
    jae .out

    ; count = len - pos - 1 + 1 = len - pos
    mov cx, bx
    sub cx, ax
    jz .shrink
    ; dst = buf + pos
    ; src = buf + pos + 1
    push ds
    push es
    cld
    mov si, kb_line_buf
    mov di, kb_line_buf
    add si, ax
    add di, ax
    inc si
    rep movsb
    pop es
    pop ds
.shrink:
    dec bx
    mov [kb_line_len], bx
    call kb_redraw_full
.out:
    popa
    ret

; Sisip satu karakter di posisi cursor
kb_insert_char:
    pusha
    ; kapasitas buffer?
    mov bx, [kb_line_len]
    cmp bx, KB_MAX_LINE-1
    jae .beep

    ; batas layar (prompt_col + len <= 79)
    mov dl, [kb_prompt_col]
    xor dh, dh
    mov ax, bx
    add ax, dx
    cmp ax, KB_SCREEN_MAX_COL
    jae .beep

    ; shift kanan tail mulai dari cursor
    ; count = len - cursor
    mov dx, [kb_cursor_pos]
    mov cx, [kb_line_len]
    sub cx, dx
    jz .write_char

    ; backward copy: start di ujung tail
    push ds
    push es
    std
    mov si, kb_line_buf
    mov di, kb_line_buf
    add si, dx
    add di, dx
    add si, cx
    add di, cx
    dec si              ; SI → char terakhir tail
    dec di              ; DI → posisi tujuan terakhir
    rep movsb
    cld
    pop es
    pop ds

.write_char:
    ; tulis char ke pos cursor
    mov bx, [kb_cursor_pos]
    mov [kb_line_buf+bx], al

    ; len++ ; cursor++
    mov bx, [kb_line_len]
    inc bx
    mov [kb_line_len], bx
    mov bx, [kb_cursor_pos]
    inc bx
    mov [kb_cursor_pos], bx

    ; redraw full
    call kb_redraw_full
    jmp .out

.beep:
    mov ah, 0Eh
    mov al, 07h
    int 10h
.out:
    popa
    ret

; ------------------------------------------------------------
; Redraw full-line:
; - Set cursor ke prompt
; - Cetak seluruh buffer dengan atribut
; - Hapus sisa visual lama (jika baris baru lebih pendek)
; - Pulihkan kursor ke posisi logis
kb_redraw_full:
    pusha

    ; set kursor ke prompt
    mov dh, [kb_prompt_row]
    mov dl, [kb_prompt_col]
    mov ah, 02h
    mov bh, 0
    int 10h

    ; cetak seluruh buffer (len bytes)
    mov cx, [kb_line_len]
    jcxz .skip_print
    mov si, kb_line_buf
.print_loop:
    lodsb
    mov ah, 09h
    mov bh, 0
    mov bl, KB_ATTR
    mov cx, 1         ; pinjam DI sebagai CX=1 (safe karena kita push/pop)
    push cx            ; simpan CX total
    mov cx, di
    int 10h
    pop cx
    loop .print_loop

.skip_print:
    ; clear tail kalau sebelumnya lebih panjang
    mov ax, [kb_last_drawn_len]
    mov bx, [kb_line_len]
    cmp ax, bx
    jbe .no_clear
    sub ax, bx         ; ax = jumlah spasi ekstra
    mov cx, ax
    jcxz .no_clear
    mov al, ' '
.clr_loop:
    mov ah, 09h
    mov bh, 0
    mov bl, KB_ATTR
    mov di, 1
    push cx
    mov cx, di
    int 10h
    pop cx
    loop .clr_loop
.no_clear:
    ; update last_drawn_len
    mov ax, [kb_line_len]
    mov [kb_last_drawn_len], ax

    ; pulihkan kursor ke posisi logis
    mov ax, [kb_cursor_pos]
    mov dh, [kb_prompt_row]
    mov dl, [kb_prompt_col]
    add dl, al
    mov ah, 02h
    mov bh, 0
    int 10h

    popa
    ret

; Pindahkan kursor visual ke posisi kb_cursor_pos
kb_move_cursor_visual:
    pusha
    mov ax, [kb_cursor_pos]
    mov dh, [kb_prompt_row]
    mov dl, [kb_prompt_col]
    add dl, al
    mov ah, 02h
    mov bh, 0
    int 10h
    popa
    ret

; Cetak isi kb_line_buf (untuk echo/demo)
kb_print_line_buf:
    pusha
    mov si, kb_line_buf
.plb_loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0Eh
    int 10h
    jmp .plb_loop
.done:
    popa
    ret

; ------------------------------------------------------------
; History: tambah entri terbaru
kb_history_add:
    pusha
    ; target = head
    mov bl, [kb_hist_head]

    ; DI = kb_hist_buf + (bl * 128)
    xor ax, ax
    mov al, bl
    ; ax <<= 7
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    mov di, kb_hist_buf
    add di, ax

    ; copy kb_line_buf → history[head]
    push ds
    push es
    cld
    mov si, kb_line_buf
    mov es, ds
    mov cx, KB_MAX_LINE
.copy_loop:
    lodsb
    stosb
    or al, al
    jz .copied
    loop .copy_loop
.copied:
    pop es
    pop ds

    ; update head
    mov al, [kb_hist_head]
    inc al
    and al, (KB_HIST_COUNT-1)     ; modulo 8
    mov [kb_hist_head], al

    ; update count (maks 8)
    mov al, [kb_hist_count]
    cmp al, KB_HIST_COUNT
    jae .done
    inc al
    mov [kb_hist_count], al
.done:
    popa
    ret

; History: load previous (Arrow Up)
kb_history_prev:
    pusha
    mov al, [kb_hist_count]
    or al, al
    jz .beep

    ; newest = (head - 1) & 7
    mov bl, [kb_hist_head]
    dec bl
    and bl, (KB_HIST_COUNT-1)

    ; oldest = (head - count) & 7
    mov dl, [kb_hist_head]
    mov al, [kb_hist_count]
    ; compute dl = head - count
    sub dl, al
    and dl, (KB_HIST_COUNT-1)

    ; if not viewing → view = newest
    mov al, [kb_hist_view]
    cmp al, 0FFh
    jne .has_view
    mov al, bl
    jmp .set_view

.has_view:
    ; move to previous unless already at oldest
    mov al, [kb_hist_view]
    cmp al, dl
    je .stay
    dec al
    and al, (KB_HIST_COUNT-1)
    jmp .set_view
.stay:
    ; tetap di oldest
    mov al, dl

.set_view:
    mov [kb_hist_view], al
    call kb_history_load_view
    popa
    ret

.beep:
    mov ah, 0Eh
    mov al, 07h
    int 10h
    popa
    ret

; History: load next (Arrow Down)
kb_history_next:
    pusha
    mov al, [kb_hist_view]
    cmp al, 0FFh
    je .beep          ; tidak sedang view

    ; newest = (head - 1) & 7
    mov bl, [kb_hist_head]
    dec bl
    and bl, (KB_HIST_COUNT-1)

    ; jika view == newest → keluar view dan kosongkan baris
    cmp al, bl
    jne .advance
    mov byte [kb_hist_view], 0FFh
    call kb_clear_line
    popa
    ret

.advance:
    inc al
    and al, (KB_HIST_COUNT-1)
    mov [kb_hist_view], al
    call kb_history_load_view
    popa
    ret
	
kb_beep:
    mov ah, 0Eh
    mov al, 07h
    int 10h
    ret

; Muat entry kb_hist_view → kb_line_buf, cursor di akhir, redraw full
kb_history_load_view:
    pusha
    ; DI = kb_hist_buf + (view * 128)
    xor ax, ax
    mov al, [kb_hist_view]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    mov di, kb_hist_buf
    add di, ax

    ; Copy ke kb_line_buf
    push ds
    push es
    cld
    mov si, di
    mov di, kb_line_buf
    mov cx, KB_MAX_LINE
    rep movsb
    pop es
    pop ds

    ; Hitung len
    xor cx, cx
    mov si, kb_line_buf
.len_loop:
    lodsb
    or al, al
    jz .len_done
    inc cx
    jmp .len_loop
.len_done:
    mov [kb_line_len], cx
    mov [kb_cursor_pos], cx

    ; redraw full
    call kb_redraw_full
    popa
    ret

; Kosongkan baris input
kb_clear_line:
    pusha
    mov word [kb_line_len], 0
    mov word [kb_cursor_pos], 0
    call kb_redraw_full
    popa
    ret
