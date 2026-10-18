#ifndef ISH_TESTS_ATOMIC_COMMON_H
#define ISH_TESTS_ATOMIC_COMMON_H

#include <stdint.h>
#include "test_common.h"

#define CC_C 0x0001u
#define CC_P 0x0004u
#define CC_A 0x0010u
#define CC_Z 0x0040u
#define CC_S 0x0080u
#define CC_O 0x0800u
#define CC_MASK (CC_C | CC_P | CC_A | CC_Z | CC_S | CC_O)
#define CC_LOGIC_MASK (CC_C | CC_P | CC_Z | CC_S | CC_O)

static uint32_t parity_even8(uint32_t value) {
    value ^= value >> 4;
    value &= 0xf;
    return (0x9669u >> value) & 1u;
}

static uint32_t add_flags32(uint32_t lhs, uint32_t rhs, uint32_t result) {
    uint32_t flags = 0;
    if (((uint64_t) lhs + (uint64_t) rhs) >> 32)
        flags |= CC_C;
    if ((result & 0x80000000u) != 0)
        flags |= CC_S;
    if (result == 0)
        flags |= CC_Z;
    if (((lhs ^ rhs ^ result) & 0x10u) != 0)
        flags |= CC_A;
    if (parity_even8(result & 0xffu))
        flags |= CC_P;
    if (((~(lhs ^ rhs) & (lhs ^ result)) & 0x80000000u) != 0)
        flags |= CC_O;
    return flags;
}

static uint32_t sub_flags32(uint32_t lhs, uint32_t rhs, uint32_t result) {
    uint32_t flags = 0;
    if (lhs < rhs)
        flags |= CC_C;
    if ((result & 0x80000000u) != 0)
        flags |= CC_S;
    if (result == 0)
        flags |= CC_Z;
    if (((lhs ^ rhs ^ result) & 0x10u) != 0)
        flags |= CC_A;
    if (parity_even8(result & 0xffu))
        flags |= CC_P;
    if ((((lhs ^ rhs) & (lhs ^ result)) & 0x80000000u) != 0)
        flags |= CC_O;
    return flags;
}

static uint32_t logic_flags32(uint32_t result) {
    uint32_t flags = 0;
    if ((result & 0x80000000u) != 0)
        flags |= CC_S;
    if (result == 0)
        flags |= CC_Z;
    if (parity_even8(result & 0xffu))
        flags |= CC_P;
    return flags;
}

static uint32_t next_u32(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

#endif
