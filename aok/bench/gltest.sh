#!/bin/sh
# gltest.sh [FRAMES] -- is the display accelerated? Installs Mesa (the guest has none: about 250 MB into RAM,
# so give the VM 2 GB) and runs kmscube on the console's display. It then says which GL renderer the guest
# was given -- "virgl (...)" when the host's GPU renders, "llvmpipe" when the guest's CPU does -- and how
# fast the cube went, with what the kernel's driver and Mesa's loader said on the way. Needs the network.
apk add --no-cache mesa-dri-gallium mesa-gbm mesa-egl mesa-gles kmscube > /tmp/gltest-apk.log 2>&1 ||
    { echo "GLTEST apk failed:"; tail -3 /tmp/gltest-apk.log; exit 1; }
dmesg | grep -iE "virtio_gpu|virtio-gpu|\[drm\]" | grep -iE "features|cap sets|error|fail" | sed 's/^\[[^]]*\] */GLTEST kernel: /'
echo "GLTEST drivers: $(ls /usr/lib/dri /usr/lib/xorg/modules/dri 2>/dev/null | grep -iE 'virtio|virgl|swrast|libgallium' | tr '\n' ' ')"
EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose MESA_DEBUG=1 kmscube -c "${1:-600}" > /tmp/gltest.log 2>&1
grep -iE "virgl|virtio|fail|fallback|cannot|unable|not supported" /tmp/gltest.log | head -8 | cut -c1-110 | sed 's/^ */GLTEST mesa: /'
grep -iE "renderer|vendor|version" /tmp/gltest.log | grep -viE "extensions|shading" | sed 's/^ */GLTEST /'
grep "Rendered" /tmp/gltest.log | tail -1 | sed 's/^/GLTEST /'
