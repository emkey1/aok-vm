// kmovtest: AVX-512's opmask moves between general registers and k registers, every width, with the low and the
// extended (REX) general registers, which OpenSSL's AVX-512 RSA uses (kmovb %r14d, %k1). x86-64 with AVX512F,
// DQ and BW; each line prints what came back, which must be what went in, cut to the width.
#include <stdint.h>
#include <stdio.h>

static int bad;

static void check(const char *what, uint64_t got, uint64_t want)
{
    printf("KMOV %-28s %016llx %s\n", what, (unsigned long long)got, got == want ? "ok" : "BAD");
    bad |= got != want;
}

int main(void)
{
    uint64_t v = 0x8badf00ddeadbeefull, a, b, c, d;

    __asm__ volatile("kmovb %k[v], %%k1\n kmovb %%k1, %k[a]" : [a] "=r" (a) : [v] "r" (v));
    check("kmovb r32 -> k1 -> r32", a, v & 0xff);
    __asm__ volatile("mov %[v], %%r14\n kmovb %%r14d, %%k1\n kmovb %%k1, %%r9d\n mov %%r9, %[a]"
                     : [a] "=r" (a) : [v] "r" (v) : "r9", "r14");
    check("kmovb r14d -> k1 -> r9d", a, v & 0xff);
    __asm__ volatile("mov %[v], %%r12\n kmovw %%r12d, %%k7\n kmovw %%k7, %%r15d\n mov %%r15, %[a]"
                     : [a] "=r" (a) : [v] "r" (v) : "r12", "r15");
    check("kmovw r12d -> k7 -> r15d", a, v & 0xffff);
    __asm__ volatile("mov %[v], %%r8\n kmovd %%r8d, %%k2\n kmovd %%k2, %%r10d\n mov %%r10, %[a]"
                     : [a] "=r" (a) : [v] "r" (v) : "r8", "r10");
    check("kmovd r8d -> k2 -> r10d", a, v & 0xffffffff);
    __asm__ volatile("mov %[v], %%r13\n kmovq %%r13, %%k3\n kmovq %%k3, %%r11\n mov %%r11, %[a]"
                     : [a] "=r" (a) : [v] "r" (v) : "r11", "r13");
    check("kmovq r13 -> k3 -> r11", a, v);
    __asm__ volatile("kmovq %[v], %%k4\n kmovq %%k4, %%k5\n kmovq %%k5, %[a]" : [a] "=r" (a) : [v] "r" (v));
    check("kmovq k4 -> k5", a, v);
    /* the four widths from the same k: a k register holds 64 bits, a narrower move zero-extends */
    __asm__ volatile("kmovq %[v], %%k6\n kmovb %%k6, %k[a]\n kmovw %%k6, %k[b]\n kmovd %%k6, %k[c]\n"
                     " kmovb %k[v], %%k6\n kmovq %%k6, %[d]"
                     : [a] "=&r" (a), [b] "=&r" (b), [c] "=&r" (c), [d] "=&r" (d) : [v] "r" (v));
    check("kmovb k6 -> r32", a, v & 0xff);
    check("kmovw k6 -> r32", b, v & 0xffff);
    check("kmovd k6 -> r32", c, v & 0xffffffff);
    check("kmovb r32 -> k6 zero-extends", d, v & 0xff);
    /*
     * As OpenSSL's RSA has it: an insn the gadget engine leaves to TCG (an 8-bit adc) a few before a kmovb, so
     * that TCG's TB, which starts at the adc, comes to the kmovb, which TCG has not got (#UD, SIGILL).
     */
    __asm__ volatile("mov %[v], %%r14\n xor %%r12d, %%r12d\n adc %%r14b, %%r12b\n xor %%r14b, %%r12b\n"
                     " kmovb %%r14d, %%k1\n kmovb %%k1, %k[a]"
                     : [a] "=r" (a) : [v] "r" (v) : "r12", "r14", "cc");
    check("adc r14b, then kmovb", a, v & 0xff);
    printf("KMOV %s\n", bad ? "FAIL" : "ok");
    return bad;
}
