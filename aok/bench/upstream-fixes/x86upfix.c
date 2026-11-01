// x86upfix.c -- what QEMU 11.1.3 and tctiSH fixed in TCG's x86, against the AOK front end and the hardware: the x87's
// C1 after each compare, and the 16-bit counts of RET, RETF and ENTER at 0x8000 and up. Prints a transcript to diff
// between a real x86-64 and a guest, QEMU_AOK=1 and 0. Build: gcc -O1 -static -no-pie x86upfix.c (with -m32, the 32-bit forms).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define C1 0x0200

static long double one = 1.0L, two = 2.0L, three = 3.0L, nanv;
static float f2 = 2.0f;
static double d2 = 2.0;
static short i16_2 = 2;
static int i32_2 = 2;

// The environment with C1 as asked and the sticky flags clear; st(0)=a, st(1)=b.
static void setup(long double *a, long double *b, int c1)
{
    struct { uint16_t cw, p0, sw, p1, tw, p2; uint32_t ip, op, dp, ds; } env;
    __asm__ volatile("fninit");
    if (b)
        __asm__ volatile("fldt %0" : : "m"(*b));
    if (a)
        __asm__ volatile("fldt %0" : : "m"(*a));
    __asm__ volatile("fnstenv %0" : "=m"(env));
    env.sw = (env.sw & ~(C1 | 0xff)) | (c1 ? C1 : 0);
    __asm__ volatile("fldenv %0" : : "m"(env));
}

#define REG(name, insn)                                                                            \
    static uint16_t name(void)                                                                     \
    {                                                                                              \
        uint16_t sw;                                                                               \
        __asm__ volatile(insn "\n\tfnstsw %0" : "=a"(sw) : : "cc", "st", "st(1)");                 \
        return sw;                                                                                 \
    }
#define MEM(name, insn, var)                                                                       \
    static uint16_t name(void)                                                                     \
    {                                                                                              \
        uint16_t sw;                                                                               \
        __asm__ volatile(insn " %1\n\tfnstsw %0" : "=a"(sw) : "m"(var) : "cc", "st", "st(1)");     \
        return sw;                                                                                 \
    }
REG(fcom_st1, "fcom %%st(1)")
REG(fcomp_st1, "fcomp %%st(1)")
REG(fcompp_, "fcompp")
REG(fucom_st1, "fucom %%st(1)")
REG(fucomp_st1, "fucomp %%st(1)")
REG(fucompp_, "fucompp")
REG(fcomi_st1, "fcomi %%st(1), %%st")
REG(fcomip_st1, "fcomip %%st(1), %%st")
REG(fucomi_st1, "fucomi %%st(1), %%st")
REG(fucomip_st1, "fucomip %%st(1), %%st")
REG(ftst_, "ftst")
REG(fxam_, "fxam")
MEM(fcom_m32, "fcoms", f2)
MEM(fcomp_m32, "fcomps", f2)
MEM(fcom_m64, "fcoml", d2)
MEM(fcomp_m64, "fcompl", d2)
MEM(ficom_m16, "ficoms", i16_2)
MEM(ficomp_m16, "ficomps", i16_2)
MEM(ficom_m32, "ficoml", i32_2)
MEM(ficomp_m32, "ficompl", i32_2)

static const struct { const char *name; uint16_t (*fn)(void); } cases[] = {
#define C(n) {#n, n}
    C(fcom_st1), C(fcomp_st1), C(fcompp_), C(fucom_st1), C(fucomp_st1), C(fucompp_), C(fcomi_st1), C(fcomip_st1),
    C(fucomi_st1), C(fucomip_st1), C(ftst_), C(fxam_), C(fcom_m32), C(fcomp_m32), C(fcom_m64), C(fcomp_m64),
    C(ficom_m16), C(ficomp_m16), C(ficom_m32), C(ficomp_m32),
};

static void x87(void)
{
    struct { const char *name; long double *a, *b; } vals[] = {
        {"gt", &three, &two}, {"lt", &one, &two}, {"eq", &two, &two}, {"un", &nanv, &two},
        {"e1", &two, NULL},     // st(1) empty: a stack fault
        {"e0", NULL, NULL},     // st(0) empty too
    };
    nanv = __builtin_nanl("");
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
        for (unsigned v = 0; v < 6; v++)
            for (int c1 = 0; c1 < 2; c1++) {
                setup(vals[v].a, vals[v].b, c1);
                uint16_t sw = cases[i].fn();
                printf("x87 %-12s %s c1=%d fsw=%04x\n", cases[i].name, vals[v].name, c1, sw);
            }
}

#define STACK_SIZE (512 * 1024)
static char stack_area[STACK_SIZE] __attribute__((aligned(4096)));

#ifdef __x86_64__
#define SP "%%rsp"
#define BP "%%rbp"
#define NEAR "retq"
#define FAR "lretq"
#define PUSHCS "mov %%cs, %%eax\n\tpushq %%rax\n\t"
#define CLOBBER "rax"
#else
#define SP "%%esp"
#define BP "%%ebp"
#define NEAR "retl"
#define FAR "lretl"
#define PUSHCS "mov %%cs, %%eax\n\tpushl %%eax\n\t"
#define CLOBBER "eax"
#endif

static uintptr_t in_sp, in_bp, out_sp, out_bp, keep_sp, keep_bp;

// BODY runs on the middle of stack_area; how far it moved the stack and frame pointers is out_sp - in_sp and so on.
#define RUN(body)                                                                                  \
    in_sp = (uintptr_t)stack_area + STACK_SIZE / 2;                                                \
    in_bp = in_sp + 256;                                                                           \
    __asm__ volatile("mov " SP ", %[ks]\n\tmov " BP ", %[kb]\n\t"                                  \
                     "mov %[is], " SP "\n\tmov %[ib], " BP "\n\t" body                             \
                     "mov " SP ", %[os]\n\tmov " BP ", %[ob]\n\t"                                  \
                     "mov %[ks], " SP "\n\tmov %[kb], " BP "\n\t"                                  \
                     : [os] "=m"(out_sp), [ob] "=m"(out_bp), [ks] "=m"(keep_sp), [kb] "=m"(keep_bp) \
                     : [is] "m"(in_sp), [ib] "m"(in_bp)                                            \
                     : CLOBBER, "cc", "memory")

#define NEARRET(n)                                                                                 \
    RUN("call 1f\n\tjmp 2f\n1:\t" NEAR " $" #n "\n2:\t");                                          \
    printf("ret   %6x sp%+ld\n", n, (long)(out_sp - in_sp));
#define FARRET(n)                                                                                  \
    RUN(PUSHCS "call 1f\n\tjmp 2f\n1:\t" FAR " $" #n "\n2:\t");                                    \
    printf("retf  %6x sp%+ld\n", n, (long)(out_sp - in_sp));
#define ENTER(n, level)                                                                            \
    RUN("enter $" #n ", $" #level "\n\t");                                                         \
    printf("enter %6x level %d sp%+ld bp%+ld\n", n, level, (long)(out_sp - in_sp), (long)(out_bp - in_bp));

static void counts(void)
{
    NEARRET(0) NEARRET(8) NEARRET(0x7ff8) NEARRET(0x8000) NEARRET(0xfff8)
    FARRET(0) FARRET(8) FARRET(0x7ff8) FARRET(0x8000) FARRET(0xfff8)
    ENTER(0, 0) ENTER(8, 0) ENTER(0x7ff8, 0) ENTER(0x8000, 0) ENTER(0xfff8, 0)
    ENTER(0x8000, 1) ENTER(0xfff8, 1) ENTER(0x8000, 2)
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("x86upfix start\n");
    x87();
    counts();
    printf("x86upfix end\n");
    return 0;
}
