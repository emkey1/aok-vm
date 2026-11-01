// usbcsw.c -- does a USB stick answer a status request queued while the data transfer is still going? Windows queues
// them that way; Linux's own driver does not, so this does it through usbfs: a SCSI READ(10) of 1 MB, with the bulk IN
// transfers for its data and for its status (CSW) submitted together. QEMU's usb-storage parked such a status request
// and never answered it (UTM's ae92cdc41f). "serial" sends them one at a time, as the control: that always worked.
// Prints one line per mode; "HANG" is a status that did not come within 5 s. Build: gcc -O1 -static usbcsw.c
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define XFER (1024 * 1024)
#define BLOCK 512

struct cbw { uint32_t sig, tag, len; uint8_t flags, lun, cblen, cb[16]; } __attribute__((packed));
struct csw { uint32_t sig, tag, residue; uint8_t status; } __attribute__((packed));

static int fd, ep_in, ep_out, iface;
static unsigned char *buf;

static int find_device(void)
{
    char path[600], sub[280];
    DIR *bus = opendir("/dev/bus/usb");
    struct dirent *b, *d;
    if (!bus) return perror("/dev/bus/usb"), -1;
    while ((b = readdir(bus))) {
        if (b->d_name[0] == '.') continue;
        snprintf(sub, sizeof sub, "/dev/bus/usb/%s", b->d_name);
        DIR *dev = opendir(sub);
        if (!dev) continue;
        while ((d = readdir(dev))) {
            unsigned char desc[1024];
            if (d->d_name[0] == '.') continue;
            snprintf(path, sizeof path, "%s/%s", sub, d->d_name);
            int f = open(path, O_RDWR);
            if (f < 0) continue;
            int n = read(f, desc, sizeof desc), in = 0, out = 0, msc = 0, ifn = 0;
            for (int i = 18; i + 2 <= n && desc[i]; i += desc[i]) {
                if (desc[i + 1] == 4) {
                    msc = desc[i + 5] == 8 && desc[i + 6] == 6 && desc[i + 7] == 0x50;
                    if (msc) ifn = desc[i + 2];
                } else if (desc[i + 1] == 5 && msc && (desc[i + 3] & 3) == 2) {
                    if (desc[i + 2] & 0x80) in = desc[i + 2]; else out = desc[i + 2];
                }
            }
            if (in && out) {
                fd = f; ep_in = in; ep_out = out; iface = ifn;
                printf("usbcsw: %s interface %d in %02x out %02x\n", path, ifn, in, out);
                return 0;
            }
            close(f);
        }
        closedir(dev);
    }
    fprintf(stderr, "usbcsw: no mass storage device\n");
    return -1;
}

static void submit(struct usbdevfs_urb *u, int ep, void *data, int len)
{
    memset(u, 0, sizeof *u);
    u->type = USBDEVFS_URB_TYPE_BULK;
    u->endpoint = ep;
    u->buffer = data;
    u->buffer_length = len;
    if (ioctl(fd, USBDEVFS_SUBMITURB, u) < 0) { perror("SUBMITURB"); exit(2); }
}

// Reap until the URB comes back, or 5 s pass: 0 or -1.
static int reap(struct usbdevfs_urb *want)
{
    struct timespec t0, t;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        struct usbdevfs_urb *got = NULL;
        struct pollfd p = {fd, POLLOUT, 0};
        if (ioctl(fd, USBDEVFS_REAPURBNDELAY, &got) == 0) {
            got->usercontext = (void *)1;
            if (want->usercontext) return 0;
            continue;
        }
        if (errno != EAGAIN) { perror("REAPURB"); exit(2); }
        if (want->usercontext) return 0;
        clock_gettime(CLOCK_MONOTONIC, &t);
        if (t.tv_sec - t0.tv_sec >= 5) return -1;
        poll(&p, 1, 100);
    }
}

static int one_read(int tag, uint32_t lba, int queued)
{
    struct cbw c = {0x43425355, (uint32_t)tag, XFER, 0x80, 0, 10, {0}};
    struct csw s;
    struct usbdevfs_urb uc, ud, us;
    uint32_t blocks = XFER / BLOCK;
    c.cb[0] = 0x28;
    c.cb[2] = lba >> 24; c.cb[3] = lba >> 16; c.cb[4] = lba >> 8; c.cb[5] = lba;
    c.cb[7] = blocks >> 8; c.cb[8] = blocks;
    memset(buf, 0, XFER);
    memset(&s, 0, sizeof s);
    submit(&uc, ep_out, &c, sizeof c);
    if (reap(&uc) < 0) { printf("  CBW HANG\n"); return -1; }
    submit(&ud, ep_in, buf, XFER);
    if (queued) {
        submit(&us, ep_in, &s, sizeof s);
    } else {
        if (reap(&ud) < 0) { printf("  data HANG\n"); return -1; }
        submit(&us, ep_in, &s, sizeof s);
    }
    if (reap(&ud) < 0) { printf("  data HANG\n"); return -1; }
    if (reap(&us) < 0) {
        printf("  status HANG (read %d: data %d bytes back, status never)\n", tag, ud.actual_length);
        return -1;
    }
    if (ud.actual_length != XFER || s.sig != 0x53425355 || s.tag != (uint32_t)tag || s.status) {
        printf("  read %d: data %d bytes, csw sig %08x tag %u status %d\n", tag, ud.actual_length, s.sig, s.tag, s.status);
        return -1;
    }
    for (int i = 0; i < XFER / BLOCK; i++) {
        uint32_t want = lba + i, got;
        memcpy(&got, buf + i * BLOCK, 4);
        if (got != want) { printf("  read %d: block %u holds %u\n", tag, want, got); return -1; }
    }
    return 0;
}

int main(int argc, char **argv)
{
    int n = argc > 1 ? atoi(argv[1]) : 30;
    setvbuf(stdout, NULL, _IOLBF, 0);
    buf = malloc(XFER);
    if (find_device() < 0) return 1;
    struct usbdevfs_ioctl disc = {iface, USBDEVFS_DISCONNECT, NULL};
    ioctl(fd, USBDEVFS_IOCTL, &disc);       // from the kernel's driver, if it took the device
    if (ioctl(fd, USBDEVFS_CLAIMINTERFACE, &iface) < 0) { perror("CLAIM"); return 1; }
    for (int queued = 0; queued < 2; queued++) {
        int ok = 0;
        for (int i = 0; i < n; i++) {
            if (one_read(i + 1, i * (XFER / BLOCK), queued) < 0) break;
            ok++;
        }
        printf("usbcsw: %s %d/%d reads\n", queued ? "queued" : "serial", ok, n);
        if (ok != n) { printf("usbcsw: FAIL\n"); return 1; }
    }
    printf("usbcsw: PASS\n");
    return 0;
}
