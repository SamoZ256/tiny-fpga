RT := ../externals/riscv-tests

RV32UI := simple add addi and andi auipc beq bge bgeu blt bltu bne fence_i jal jalr \
	lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti sltiu sltu \
	sra srai srl srli sub xor xori
RV32UM := mul mulh mulhsu mulhu div divu rem remu
FAULT := ebreak misaligned illegal

RTL := ../rv32_cpu/alu.sv ../rv32_cpu/mdu.sv ../rv32_cpu/div.sv ../rv32_cpu/cpu.sv ../common/ram.sv
CC := zig cc -target riscv32-freestanding-none -mcpu=generic_rv32+m
CFLAGS := -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -fno-pic \
	-Ienv -I$(RT)/isa/macros/scalar -T ../firmware/link.ld

ISA_HEX := $(RV32UI:%=build/rv32ui-%.hex) $(RV32UM:%=build/rv32um-%.hex)
FAULT_HEX := $(FAULT:%=build/fault-%.hex)

test: unit isa fault firmware

build:
	mkdir -p $@

build/rv32ui-%.elf: env/riscv_test.h ../firmware/link.ld | build
	$(CC) $(CFLAGS) -o $@ $(RT)/isa/rv32ui/$*.S

build/rv32um-%.elf: env/riscv_test.h ../firmware/link.ld | build
	$(CC) $(CFLAGS) -o $@ $(RT)/isa/rv32um/$*.S

build/fault-%.elf: fault/%.S env/riscv_test.h ../firmware/link.ld | build
	$(CC) $(CFLAGS) -o $@ $<

build/%.hex: build/%.elf
	riscv64-unknown-elf-objcopy -O binary $< $(<:.elf=.bin)
	hexdump -v -e '1/4 "%08x" "\n"' $(<:.elf=.bin) > $@

build/tb_cpu.vvp: tb_cpu.sv $(RTL) | build
	iverilog -g2012 -o $@ $(RTL) tb_cpu.sv

build/tb_alu.vvp: tb_alu.sv ../rv32_cpu/alu.sv | build
	iverilog -g2012 -o $@ ../rv32_cpu/alu.sv tb_alu.sv

build/tb_mdu.vvp: tb_mdu.sv ../rv32_cpu/mdu.sv | build
	iverilog -g2012 -o $@ ../rv32_cpu/mdu.sv tb_mdu.sv

build/tb_div.vvp: tb_div.sv ../rv32_cpu/div.sv | build
	iverilog -g2012 -o $@ ../rv32_cpu/div.sv tb_div.sv

../firmware/firmware.hex: ../firmware/main.zig ../firmware/link.ld
	$(MAKE) -C ../firmware

unit: build/tb_alu.vvp build/tb_mdu.vvp build/tb_div.vvp
	vvp -n build/tb_alu.vvp | tee build/alu.log
	@grep -q '^errors=0$$' build/alu.log
	vvp -n build/tb_mdu.vvp | tee build/mdu.log
	@grep -q '^errors=0$$' build/mdu.log
	vvp -n build/tb_div.vvp | tee build/div.log
	@grep -q '^errors=0$$' build/div.log

isa: build/tb_cpu.vvp $(ISA_HEX)
	@rm -f build/isa.log
	@for h in $(ISA_HEX); do \
		r=$$(vvp -n build/tb_cpu.vvp +hex=$$h | grep -E '^(PASS|FAIL|FAULT|TIMEOUT)'); \
		printf '%-20s %s\n' $$(basename $$h .hex) "$$r" | tee -a build/isa.log; \
	done
	@! grep -qv ' PASS$$' build/isa.log

fault: build/tb_cpu.vvp $(FAULT_HEX)
	@rm -f build/fault.log
	@for h in $(FAULT_HEX); do \
		r=$$(vvp -n build/tb_cpu.vvp +hex=$$h | grep -E '^(PASS|FAIL|FAULT|TIMEOUT)'); \
		printf '%-20s %s\n' $$(basename $$h .hex) "$$r" | tee -a build/fault.log; \
	done
	@! grep -qv ' FAULT' build/fault.log

firmware: build/tb_cpu.vvp ../firmware/firmware.hex
	vvp -n build/tb_cpu.vvp +hex=../firmware/firmware.hex +smoke | grep -E '^(PASS|FAIL|FAULT|TIMEOUT)' | tee build/firmware.log
	@grep -q '^PASS' build/firmware.log

clean:
	rm -rf build

.PHONY: test unit isa fault firmware clean
.SECONDARY:
