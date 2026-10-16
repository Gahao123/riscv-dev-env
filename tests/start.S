.section .text.init
.globl _start
.option norelax
_start:
    csrr t0, mhartid
    bnez t0, park
    la sp, stack_top
    call test_main
    slli a0, a0, 1
    ori a0, a0, 1
    la t0, tohost
    sd a0, 0(t0)
park:
    wfi
    j park

.section .tohost,"aw",@progbits
.balign 64
.globl tohost
tohost: .dword 0
.balign 64
.globl fromhost
fromhost: .dword 0

.section .bss
.balign 16
stack_bottom: .space 4096
stack_top:
