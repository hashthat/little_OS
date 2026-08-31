global loader                   ; the entry symbol for ELF

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; magic + flags + checksum must equal 0

section .text                   ; start of the text (code) section
align 4                         ; the header must be 4-byte aligned
    dd MAGIC_NUMBER             ; write the magic number,
    dd FLAGS                    ; the flags,
    dd CHECKSUM                 ; and the checksum

loader:                         ; entry point (named in linker script)
    mov eax, 0xCAFEBABE         ; put the test value in eax
.loop:
    jmp .loop                   ; loop forever