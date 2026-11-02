include sim.mk

VERILOG_SOURCES := \
	vga/pll1.v
SLANG_SOURCES := \
	$(SIM_SOURCES) \
	vga/vga2tmds.sv \
	vga/tmds_encoder.sv \
	main.sv
SOURCES := $(VERILOG_SOURCES) $(SLANG_SOURCES)
FIRMWARE := firmware/firmware.hex
FIRMWARE_SRCS := $(shell find firmware -type f)

OUTPUT := bitstream
PACKAGE := CABGA256
FPGA_SIZE ?= 25k

all: debug

$(FIRMWARE): $(FIRMWARE_SRCS)
	$(MAKE) -C firmware

%.json: $(SOURCES) $(FIRMWARE)
	rm -f $(OUTPUT).bit $(OUTPUT).config $(OUTPUT).json
	# HACK: disable -Wimplicit-net-port
	yosys -m slang -p '\
		read_verilog $(VERILOG_SOURCES); \
		read_slang -Wextra -Wpedantic -Werror -Wno-implicit-net-port -top top $(SLANG_SOURCES); \
		synth_ecp5 -top top -json $@'

%.config: %.json icepi-zero.lpf
	nextpnr-ecp5 --$(FPGA_SIZE) --package $(PACKAGE) --lpf icepi-zero.lpf --json $< --textcfg $@ # 2> log.txt
	# cat log.txt | grep Device -A 28

%.bit: %.config
	ecppack --compress $< $@

build: $(OUTPUT).bit

debug: build
	openFPGALoader -b icepi-zero $(OUTPUT).bit

install: build
	openFPGALoader -b icepi-zero $(OUTPUT).bit --write-flash

install-bitstream:
	openFPGALoader -b icepi-zero $(OUTPUT).bit --write-flash

test:
	$(MAKE) -C tests

help:
	echo "Usage: make [option]"
	echo "Options:"
	echo "- install: install to flash"
	echo "- debug: install to chip's temp memory (bitstream lost on power loss)"
	echo "- build: builds the bitstream"
	echo "- test: run the test suite"
	echo "- clean: delete all temparary files"

clean:
	rm -f $(OUTPUT).bit $(OUTPUT).config $(OUTPUT).json
	$(MAKE) -C tests clean

.PHONY: all build clean debug install install-bitstream help test
