#!/usr/bin/env bash
#
# bootstrap.sh — generate the Phase 1 boilerplate for a littleosbook-style kernel.
#
# What this gives you: loader.s, link.ld, menu.lst, bochsrc.txt, a Makefile,
# and the GRUB Legacy stage2_eltorito bootloader — everything needed to reach
# the first milestone (EAX = CAFEBABE in the Bochs log).
#
# What this does NOT give you: understanding. Read chapter 2 of the book first;
# run this when you want a clean starting point you already understand,
# or a fresh scratch project to experiment in.
#
# Usage:  ./bootstrap.sh [project-dir]     (default: os-dev)

set -euo pipefail

PROJECT="${1:-os-dev}"
STAGE2_URL="https://github.com/littleosbook/littleosbook/raw/master/files/stage2_eltorito"

# ---------------------------------------------------------------- sanity checks
missing=()
for tool in nasm ld genisoimage bochs make; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing tools: ${missing[*]}"
    echo "Install with:"
    echo "  sudo apt update && sudo apt install build-essential nasm make genisoimage bochs bochs-sdl"
    exit 1
fi

if [ -e "$PROJECT" ]; then
    echo "Refusing to overwrite existing '$PROJECT'. Pick another name or remove it."
    exit 1
fi

mkdir -p "$PROJECT"/iso/boot/grub
cd "$PROJECT"

# ---------------------------------------------------------------- loader.s
cat > loader.s << 'EOF'
global loader                   ; the entry symbol for ELF

MAGIC_NUMBER equ 0x1BADB002     ; multiboot magic number
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; magic + flags + checksum must equal 0

section .text                   ; NOTE: no trailing colon (book PDF has a typo)
align 4                         ; header must be 4-byte aligned,
    dd MAGIC_NUMBER             ; and must appear before any code so GRUB
    dd FLAGS                    ; finds it in the first 8 KB of the file
    dd CHECKSUM

loader:                         ; entry point (named in link.ld)
    mov eax, 0xCAFEBABE         ; the value we grep for in the Bochs log
.loop:
    jmp .loop                   ; loop forever
EOF

# ---------------------------------------------------------------- link.ld
cat > link.ld << 'EOF'
ENTRY(loader)                /* the entry label from loader.s */

SECTIONS {
    . = 0x00100000;          /* load at 1 MB — below is BIOS/GRUB/MMIO */

    .text ALIGN (0x1000) :   /* 4 KB alignment = x86 page size; */
    {                        /* matters once paging exists (ch. 9) */
        *(.text)
    }

    .rodata ALIGN (0x1000) :
    {
        *(.rodata*)
    }

    .data ALIGN (0x1000) :
    {
        *(.data)
    }

    .bss ALIGN (0x1000) :
    {
        *(COMMON)            /* legacy common symbols */
        *(.bss)              /* uninitialized data — your ch. 3 kernel
                                stack will live here */
    }
}
EOF

# ---------------------------------------------------------------- menu.lst
cat > iso/boot/grub/menu.lst << 'EOF'
default=0
timeout=0

title os
kernel /boot/kernel.elf
EOF

# ---------------------------------------------------------------- bochsrc.txt
# ROM paths differ between distro package versions, so detect them.
find_rom() {
    for p in "$@"; do
        [ -f "$p" ] && { echo "$p"; return; }
    done
    echo ""
}
ROMIMAGE=$(find_rom /usr/share/bochs/BIOS-bochs-latest /usr/share/bochs/bios/BIOS-bochs-latest)
VGAROM=$(find_rom /usr/share/bochs/VGABIOS-lgpl-latest /usr/share/vgabios/vgabios.bin /usr/share/bochs/bios/VGABIOS-lgpl-latest)

if [ -z "$ROMIMAGE" ] || [ -z "$VGAROM" ]; then
    echo "WARNING: could not auto-detect Bochs ROM paths."
    echo "Find them with:  dpkg -L bochs bochs-sdl vgabios 2>/dev/null | grep -i bios"
    ROMIMAGE="${ROMIMAGE:-/usr/share/bochs/BIOS-bochs-latest}"
    VGAROM="${VGAROM:-/usr/share/bochs/VGABIOS-lgpl-latest}"
fi

cat > bochsrc.txt << EOF
megs: 32
display_library: sdl
romimage: file=$ROMIMAGE
vgaromimage: file=$VGAROM
ata0-master: type=cdrom, path=os.iso, status=inserted
boot: cdrom
log: bochslog.txt
clock: sync=realtime, time0=local
cpu: count=1, ips=1000000
EOF

# ---------------------------------------------------------------- Makefile
# Real tabs are required in Makefile recipes — this heredoc preserves them.
cat > Makefile << 'EOF'
OBJECTS = loader.o
LDFLAGS = -T link.ld -melf_i386
AS      = nasm
ASFLAGS = -f elf32

# When kmain.c exists (chapter 3), add kmain.o to OBJECTS and uncomment:
# CC     = gcc
# CFLAGS = -m32 -ffreestanding -fno-stack-protector -fno-builtin \
#          -nostdlib -nostdinc -nostartfiles -nodefaultlibs \
#          -Wall -Wextra -Werror -c

all: kernel.elf

kernel.elf: $(OBJECTS)
	ld $(LDFLAGS) $(OBJECTS) -o kernel.elf

os.iso: kernel.elf
	cp kernel.elf iso/boot/kernel.elf
	genisoimage -R \
		-b boot/grub/stage2_eltorito \
		-no-emul-boot \
		-boot-load-size 4 \
		-A os \
		-input-charset utf8 \
		-quiet \
		-boot-info-table \
		-o os.iso \
		iso

run: os.iso
	bochs -f bochsrc.txt -q

check: os.iso
	@echo "Boot the ISO, quit Bochs, then run: make verify"

verify:
	@grep -o "EAX=[0-9a-fA-Fx]*" bochslog.txt | tail -1 | \
		grep -qi cafebabe && echo "SUCCESS: EAX = CAFEBABE" \
		|| echo "Not found — did the kernel boot? Check bochslog.txt"

%.o: %.c
	$(CC) $(CFLAGS) $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

clean:
	rm -f *.o kernel.elf os.iso bochslog.txt com1.out
	rm -f iso/boot/kernel.elf

.PHONY: all run check verify clean
EOF

# ---------------------------------------------------------------- stage2_eltorito
echo "Downloading stage2_eltorito (GRUB Legacy bootloader, ~103 KB)..."
if command -v wget >/dev/null 2>&1; then
    wget -q "$STAGE2_URL" -O iso/boot/grub/stage2_eltorito
else
    curl -sL "$STAGE2_URL" -o iso/boot/grub/stage2_eltorito
fi

if [ ! -s iso/boot/grub/stage2_eltorito ]; then
    echo "WARNING: download failed. Fetch it manually:"
    echo "  wget $STAGE2_URL -O iso/boot/grub/stage2_eltorito"
fi

# ---------------------------------------------------------------- done
echo ""
echo "Project '$PROJECT' created:"
echo ""
echo "  $PROJECT/"
echo "  ├── loader.s          multiboot header + CAFEBABE test"
echo "  ├── link.ld           linker script (kernel at 1 MB)"
echo "  ├── Makefile          make / make os.iso / make run / make verify"
echo "  ├── bochsrc.txt       Bochs config (ROM paths auto-detected)"
echo "  └── iso/boot/grub/"
echo "      ├── menu.lst      GRUB config"
echo "      └── stage2_eltorito"
echo ""
echo "Next:  cd $PROJECT && make run"
echo "Then:  quit Bochs and run 'make verify' to check for CAFEBABE."