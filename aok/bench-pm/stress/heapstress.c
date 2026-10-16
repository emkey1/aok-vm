/*
 * heapstress: what busybox sort does with the heap, checked as it goes. Words
 * of random letters, each in its own malloc'd block, their pointers in a
 * vector grown 64 at a time by realloc (past the mmap threshold that is an
 * mremap each time), sorted by qsort and strcmp, then freed; and between
 * them the string functions against plain loops. Every result is checked,
 * so that a wrong one is reported where it happens, with its values, and
 * not as malloc's abort some time later.
 *
 * Prints HEAPSTRESS FAIL lines, at most 20, and then HEAPSTRESS ok or bad.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t rng = 0x2545f491;
static int fails;

static uint32_t rnd(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

#define FAIL(...) do {                                                      \
        printf("HEAPSTRESS FAIL " __VA_ARGS__);                             \
        fflush(stdout);                                                     \
        if (++fails >= 20) {                                                \
            puts("HEAPSTRESS bad");                                         \
            exit(1);                                                        \
        }                                                                   \
    } while (0)

static uint32_t hash(const char *s)
{
    uint32_t h = 2166136261u;

    while (*s) {
        h = (h ^ (unsigned char)*s++) * 16777619u;
    }
    return h;
}

static int plain_strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++, b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

static int sign(int x)
{
    return (x > 0) - (x < 0);
}

static int cmp(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

/* One sort: n words, as sort reads them. */
static void sort_round(int round)
{
    int n = 20000 + rnd() % 60000;
    char **v = NULL;
    uint32_t sum = 0, sum2 = 0;
    char buf[32];

    for (int i = 0; i < n; i++) {
        int len = 1 + rnd() % 14;

        for (int j = 0; j < len; j++) {
            buf[j] = 'a' + rnd() % 26;
        }
        buf[len] = 0;
        if ((i & 63) == 0) {
            char **w = realloc(v, (i + 64) * sizeof(*v));

            if (!w) {
                FAIL("round %d: realloc to %d failed\n", round, i + 64);
                return;
            }
            /* What was there must still be there. */
            for (int k = i >= 64 ? i - 64 : 0; k < i; k++) {
                if (w[k] == NULL || strlen(w[k]) > 14) {
                    FAIL("round %d: after realloc to %d, entry %d is %p\n",
                         round, i + 64, k, (void *)w[k]);
                }
            }
            v = w;
        }
        v[i] = malloc(len + 1);
        memcpy(v[i], buf, len + 1);
        if ((int)strlen(v[i]) != len || plain_strcmp(v[i], buf) != 0) {
            FAIL("round %d: word %d: copied \"%s\" (%zu) from \"%s\" (%d)\n",
                 round, i, v[i], strlen(v[i]), buf, len);
        }
        sum += hash(v[i]);
    }

    qsort(v, n, sizeof(*v), cmp);

    for (int i = 0; i < n; i++) {
        sum2 += hash(v[i]);
        if (i && plain_strcmp(v[i - 1], v[i]) > 0) {
            FAIL("round %d: out of order at %d: \"%s\" > \"%s\" (strcmp %d)\n",
                 round, i, v[i - 1], v[i], strcmp(v[i - 1], v[i]));
        }
    }
    if (sum != sum2) {
        FAIL("round %d: the words changed in the sort: %08x %08x\n",
             round, sum, sum2);
    }
    for (int i = 0; i < n; i++) {
        free(v[i]);
    }
    free(v);
}

/* The string functions, at every alignment and many lengths. */
static void string_round(int round)
{
    static unsigned char a[4096 + 64], b[4096 + 64], c[4096 + 64];

    for (int t = 0; t < 2000; t++) {
        int len = rnd() % (t & 1 ? 4096 : 80);
        int sa = rnd() % 32, sb = rnd() % 32;

        for (int i = 0; i < len + 64; i++) {
            a[i] = rnd();
            b[i] = c[i] = rnd();
        }
        memcpy(b + sb, a + sa, len);
        for (int i = 0; i < len + 64; i++) {
            unsigned char want = (i >= sb && i < sb + len) ? a[sa + i - sb] : c[i];

            if (b[i] != want) {
                FAIL("round %d: memcpy(+%d, +%d, %d): byte %d is %02x, not %02x\n",
                     round, sb, sa, len, i, b[i], want);
                break;
            }
        }

        int fill = rnd() & 0xff;

        memcpy(c, b, len + 64);
        memset(b + sb, fill, len);
        for (int i = 0; i < len + 64; i++) {
            unsigned char want = (i >= sb && i < sb + len) ? fill : c[i];

            if (b[i] != want) {
                FAIL("round %d: memset(+%d, %02x, %d): byte %d is %02x\n",
                     round, sb, fill, len, i, b[i]);
                break;
            }
        }

        /* An overlapping move, either way. */
        int d = (int)(rnd() % 64) - 32;
        int src = 32, dst = 32 + d;

        memcpy(c, a, len + 64);
        memmove(a + dst, a + src, len);
        for (int i = 0; i < len; i++) {
            if (a[dst + i] != c[src + i]) {
                FAIL("round %d: memmove(+%d, +%d, %d): byte %d is %02x, not %02x\n",
                     round, dst, src, len, i, a[dst + i], c[src + i]);
                break;
            }
        }

        /* Strings: no zero bytes but the end, then strlen, strcmp, strcpy. */
        for (int i = 0; i < len + 64; i++) {
            a[i] = 1 + rnd() % 255;
        }
        a[sa + len] = 0;
        memcpy(b, a, len + 64);
        if (len && rnd() & 1) {
            b[sa + rnd() % len] ^= 1 + rnd() % 254;
        }
        if (strlen((char *)a + sa) != (size_t)len) {
            FAIL("round %d: strlen(+%d) of %d is %zu\n",
                 round, sa, len, strlen((char *)a + sa));
        }
        int r1 = sign(strcmp((char *)a + sa, (char *)b + sa));
        int r2 = sign(plain_strcmp((char *)a + sa, (char *)b + sa));

        if (r1 != r2) {
            FAIL("round %d: strcmp(+%d) of %d is %d, not %d\n",
                 round, sa, len, r1, r2);
        }
        strcpy((char *)c + sb, (char *)a + sa);
        if (plain_strcmp((char *)c + sb, (char *)a + sa) != 0) {
            FAIL("round %d: strcpy(+%d, +%d) of %d differs\n", round, sb, sa, len);
        }
    }
}

int main(int argc, char **argv)
{
    int rounds = argc > 1 ? atoi(argv[1]) : 40;

    for (int r = 0; r < rounds; r++) {
        sort_round(r);
        string_round(r);
    }
    printf("HEAPSTRESS %s %d rounds\n", fails ? "bad" : "ok", rounds);
    return fails != 0;
}
