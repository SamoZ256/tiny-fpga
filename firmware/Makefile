build:
	zig build-exe main.zig -target riscv32-freestanding-none -mcpu=generic_rv32+m -O ReleaseSmall -fno-stack-protector -fno-unwind-tables -T link.ld -femit-bin=firmware.elf
	riscv64-unknown-elf-readelf -h firmware.elf | grep -q 'Entry point address: *0x0$$'
	riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
	riscv64-unknown-elf-objdump -d firmware.elf
	hexdump -v -e '1/4 "%08x" "\n"' firmware.bin > firmware.hex

clean:
	rm -f firmware.elf firmware.bin firmware.hex

.PHONY: build clean
