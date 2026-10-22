# ---- config ----
OUT      := output
LIB      := lib

IMG      := $(OUT)/os.img
STAGE1   := $(OUT)/boot.bin
STAGE2   := $(OUT)/stage2.bin

BOOTSZ   := 512
FLOPPY   := 1474560          # 1.44 MB

QEMU     := qemu-system-x86_64
QFLAGS   := -drive format=raw,file=$(IMG)

NASM     := nasm
NFLAGS   := -f bin -I $(LIB)/

.PHONY: all run debug check clean

all: $(IMG)

# ---- build dir ----
$(OUT):
	mkdir -p $(OUT)

# ---- stage1: must be exactly 512 bytes ----
$(STAGE1): boot.asm $(LIB)/lib.asm | $(OUT)
	$(NASM) $(NFLAGS) $< -o $@
	@sz=$$(stat -c%s $@); \
	if [ $$sz -ne $(BOOTSZ) ]; then \
		echo "ERROR: boot.bin is $$sz bytes, must be $(BOOTSZ)"; \
		rm -f $@; exit 1; \
	fi

# ---- stage2: pad to a whole sector ----
$(STAGE2): stage2.asm $(LIB)/lib.asm | $(OUT)
	$(NASM) $(NFLAGS) $< -o $@
	@sz=$$(stat -c%s $@); pad=$$(( (512 - sz % 512) % 512 )); \
	if [ $$pad -ne 0 ]; then truncate -s $$((sz+pad)) $@; fi

# ---- stitch the image ----
$(IMG): $(STAGE1) $(STAGE2)
	cat $(STAGE1) $(STAGE2) > $@
	@sz=$$(stat -c%s $@); \
	if [ $$sz -gt $(FLOPPY) ]; then \
		echo "ERROR: stage2 too big ($$sz > $(FLOPPY))"; rm -f $@; exit 1; \
	fi
	truncate -s $(FLOPPY) $@

# ---- targets ----
run: $(IMG)
	$(QEMU) $(QFLAGS)

debug: $(IMG)
	$(QEMU) -s -S $(QFLAGS)

check: $(IMG)
	@echo "boot.bin: $$(stat -c%s $(STAGE1)) bytes"
	@echo "os.img  : $$(stat -c%s $(IMG)) bytes"
	@xxd -s -2 -l 2 $(STAGE1) | grep -q "55aa" && echo "signature: OK" || echo "signature: MISSING"
	@xxd -s 512 -l 16 $(IMG)

clean:
	rm -rf $(OUT)