OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* Must match RAM_ADDR_WIDTH in main.sv: 2^11 words = 8 KiB */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
}

STACK_SIZE = 1K;

SECTIONS
{
    /* _start must be the first instruction: the CPU boots at PC = 0 */
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4) {
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
    } > RAM

    /* Everything runs from RAM preloaded by $readmemh, so .data needs no copy */
    .data : ALIGN(4) {
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        *(.data .data.*)
    } > RAM

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    ASSERT(__bss_end <= __stack_top - STACK_SIZE, "firmware + stack do not fit in RAM")

    /* No unwinder on this target; keep these out of the image */
    /DISCARD/ : {
        *(.eh_frame) *(.eh_frame_hdr)
        *(.comment)
    }
}
