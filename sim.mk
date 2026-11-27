SIM_TOP := core
SIM_SOURCES := \
	common/delayer.sv \
	common/debouncer.sv \
	common/ram.sv \
	rv32_cpu/alu.sv \
	rv32_cpu/mdu.sv \
	rv32_cpu/div.sv \
	rv32_cpu/cpu.sv \
	vga/constants.sv \
	vga/counter.sv \
	vga/vga.sv \
	spu/common.sv \
	spu/vram.sv \
	spu/multiplier_normalized8.sv \
	spu/color_resolver.sv \
	spu/line_buffer.sv \
	spu/spu.sv \
	core.sv
SIM_CLK_HZ := 50000000
SIM_PIXEL_HZ := 25000000
SIM_BAUD := 115200
SIM_PREBUILD := $(MAKE) firmware/firmware.hex
