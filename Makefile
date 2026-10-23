# ---- config ----
OUT      := output
LIB      := lib
KERNEL   := kernel

IMG      := $(OUT)/os.img
STAGE1   := $(OUT)/boot.bin
STAGE2   := $(OUT)/stage2.bin
KELF     := $(OUT)/kernel.elf
KIMAGE   := $(OUT)/kernel.bin

BOOTSZ   := 512
FLOPPY   := 1474560          # 1.44 MB = 2880 sectors

KERNEL_LBA     := 64         # frozen contract (todo item 9)
KERNEL_SECTORS := 64         # 32 KiB max kernel for now

QEMU     := qemu-system-x86_64
QFLAGS   := -drive format=raw,file=$(IMG)

NASM     := nasm
NFLAGS   := -f bin

CC       := gcc
CFLAGS   := -m64 -ffreestanding -fno-pie -fno-stack-protector \
            -mno-red-zone -mno-sse -mno-mmx -Os -Wall -Wextra \
            -fno-asynchronous-unwind-tables -fno-unwind-tables \
            -I $(KERNEL)

KOBJS    := $(OUT)/entry.o $(OUT)/main.o

ASMDUMP  := objdump

.PHONY: all run debug check clean

all: $(IMG)

# ---- build dir ----
$(OUT):
	mkdir -p $(OUT)

# ---- stage1: must be exactly 512 bytes ----
$(STAGE1): boot.asm | $(OUT)
	$(NASM) $(NFLAGS) $< -o $@
	@sz=$$(stat -c%s $@); \
	if [ $$sz -ne $(BOOTSZ) ]; then \
		echo "ERROR: boot.bin is $$sz bytes, must be $(BOOTSZ)"; \
		rm -f $@; exit 1; \
	fi

# ---- stage2: pad to a whole sector ----
$(STAGE2): stage2.asm | $(OUT)
	$(NASM) $(NFLAGS) $< -o $@
	@sz=$$(stat -c%s $@); pad=$$(( (512 - sz % 512) % 512 )); \
	if [ $$pad -ne 0 ]; then truncate -s $$((sz+pad)) $@; fi

# ---- kernel: asm entry (elf64) + C ----
$(OUT)/entry.o: $(KERNEL)/entry.asm | $(OUT)
	nasm -f elf64 $< -o $@

$(OUT)/%.o: $(KERNEL)/%.c $(KERNEL)/types.h | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@

$(KELF): $(KOBJS) $(KERNEL)/linker.ld
	ld -m elf_x86_64 -T $(KERNEL)/linker.ld -nostdlib -o $@ $(KOBJS)

$(KIMAGE): $(KELF)
	objcopy -O binary $< $@
	@sz=$$(stat -c%s $@); max=$$(( $(KERNEL_SECTORS) * 512 )); \
	if [ $$sz -gt $$max ]; then \
		echo "ERROR: kernel too big ($$sz > $$max bytes)"; rm -f $@; exit 1; \
	fi; \
	echo "kernel.bin: $$sz bytes (max $$max)"

# ---- stitch the image: boot | stage2 | ... | kernel at LBA 64 ----
$(IMG): $(STAGE1) $(STAGE2) $(KIMAGE)
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(STAGE1) of=$@ conv=notrunc status=none
	dd if=$(STAGE2) of=$@ bs=512 seek=1 conv=notrunc status=none
	dd if=$(KIMAGE) of=$@ bs=512 seek=$(KERNEL_LBA) conv=notrunc status=none

# ---- targets ----
run: $(IMG)
	$(QEMU) $(QFLAGS)

debug: $(IMG)
	$(QEMU) -s -S $(QFLAGS)

check: $(IMG)
	@echo "boot.bin  : $$(stat -c%s $(STAGE1)) bytes"
	@echo "stage2.bin: $$(stat -c%s $(STAGE2)) bytes"
	@echo "kernel.bin: $$(stat -c%s $(KIMAGE)) bytes"
	@echo "os.img    : $$(stat -c%s $(IMG)) bytes"
	@xxd -s -2 -l 2 $(STAGE1) | grep -q "55aa" && echo "signature : OK" || echo "signature : MISSING"
	@echo "--- kernel at LBA $(KERNEL_LBA) (byte $$(( $(KERNEL_LBA) * 512 ))):"
	@xxd -s $$(( $(KERNEL_LBA) * 512 )) -l 16 $(IMG)
	@echo "--- _start must be the first bytes at 0x100000:"
	@$(ASMDUMP) -h $(KELF) | grep -E "\.text|\.bss" | head -4

clean:
	rm -rf $(OUT)