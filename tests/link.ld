OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.* .sdata .sdata.*) }
  .tohost ALIGN(64) : { *(.tohost) }
  .bss ALIGN(16) : { *(.bss .bss.* .sbss .sbss.*) *(COMMON) }
}
