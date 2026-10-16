/* mixer: unmute and set every OSS mixer channel the device has to full volume, so that the "sound"
 * workload's data reaches QEMU's audiodev instead of a muted codec. */
#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <linux/soundcard.h>
int main(void)
{
    int fd = open("/dev/mixer", O_RDWR), devmask = 0, vol = 100 | (100 << 8);
    if (fd < 0) { perror("mixer"); return 1; }
    ioctl(fd, SOUND_MIXER_READ_DEVMASK, &devmask);
    for (int i = 0; i < SOUND_MIXER_NRDEVICES; i++)
        if (devmask & (1 << i)) {
            int v = vol;
            if (ioctl(fd, MIXER_WRITE(i), &v) == 0) printf("MIXER %d -> %d\n", i, v & 0xff);
        }
    return 0;
}
