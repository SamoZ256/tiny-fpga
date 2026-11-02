#ifndef RISCV_TEST_H
#define RISCV_TEST_H

#define TESTNUM gp
#define TOHOST 0x10000100

#define RVTEST_RV32U
#define RVTEST_RV32M
#define RVTEST_RV64U
#define RVTEST_RV64M

#define RVTEST_CODE_BEGIN \
        .section .text.start; \
        .globl _start; \
_start:

#define RVTEST_CODE_END unimp

#define RVTEST_PASS \
        li t0, TOHOST; \
        li t1, 1; \
        sw t1, 0(t0); \
1:      j 1b;

#define RVTEST_FAIL \
        sll TESTNUM, TESTNUM, 1; \
        or TESTNUM, TESTNUM, 1; \
        li t0, TOHOST; \
        sw TESTNUM, 0(t0); \
1:      j 1b;

#define RVTEST_DATA_BEGIN .align 4;
#define RVTEST_DATA_END .align 4;

#endif
