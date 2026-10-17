#!/bin/sh
# devuan-ultimate-job.sh -- run inside the Devuan machine by rc.local's aokjob= hook, as root, once it has
# booted (build-devuan-disk.sh ultimate): iSH-AOK's own provisioning and Wayland scripts, from /AOK/tools,
# answering their questions through the environment. What it leaves:
#   - the "ultimate terminal" tool set and services of provision-ultimate-devuan.sh
#   - a login, aok, with no password and sudo without one; it is logged in on the display's console, root
#     still on the serial one (a local test machine: give both passwords before putting it on a network)
#   - labwc, foot, waybar and the rest of setup-wayland.sh, and seatd; `desktop` starts the desktop
set -x
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
# The clock: a machine started with no network time yet can be far enough off for apt to refuse the
# archive's signatures.
date
export TZ_NAME=UTC TARGET_USER=aok NEW_HOSTNAME=devuan SUDO_NOPASSWD=1
sh /AOK/tools/provision-ultimate-devuan.sh || exit 1
sh /AOK/tools/setup-wayland.sh || exit 2
# X11 programs on the desktop, and a browser and file manager for its menu: best-effort.
sh /AOK/tools/setup-wayland-extras.sh x11 tools || echo "wayland extras: not all installed"
id aok
# Vulkan in the guest: Mesa's virtio driver (venus) is the guest's half of what the engine's virtio-gpu
# offers when the front end's "Vulkan Driver" is not Disabled. vkcube and vulkaninfo to see it with.
apt-get install -y --no-install-recommends mesa-vulkan-drivers vulkan-tools || echo "vulkan: not installed"
# The power key. A key of the host's keyboard can arrive as one: an iPad keyboard's did, through UTM, and
# elogind shut the machine down under its user twice in twenty minutes ("Power key pressed short.
# Powering off..." in auth.log). The machine is stopped from its front end, or by its owner's poweroff.
mkdir -p /etc/elogind/logind.conf.d
cat > /etc/elogind/logind.conf.d/50-aok-vm-keys.conf <<'L'
# (devuan-ultimate-job.sh) A host keyboard's lock or power key must not take the machine down.
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
L
# aok on the display's console; root stays on the serial port.
sed -i 's|^1:2345:respawn:.*|1:2345:respawn:/sbin/agetty --autologin aok --noclear tty1 linux|' /etc/inittab
cat > /etc/motd <<'M'

   Devuan GNU/Linux 6 (excalibur), riscv64, for the AOK QEMU engine
   ------------------------------------------------------------
   desktop  :  desktop                  (Wayland: labwc, foot, waybar)
               desktop soft             (the same, drawn without the GPU)
   display  :  gltest                   which GL renderer programs get
               vulkaninfo --summary     the Vulkan device (venus), vkcube
   games    :  sudo sh /AOK/tools/setup-games.sh   (Doom, ScummVM, Warzone 2100, ...)
   re-setup :  sudo sh /AOK/tools/provision-ultimate-devuan.sh
               (timezone, login, hostname: it asks)
   services :  service <name> {start|stop|status}
   ------------------------------------------------------------

M
sed -i "s/riscv64/$(dpkg --print-architecture)/" /etc/motd
apt-get clean
rm -rf /var/lib/apt/lists/*
df -h / | tail -1
dpkg-query -W -f '${Package} ${Version}\n' labwc foot waybar seatd neovim gcc mesa-vulkan-drivers vulkan-tools 2>&1
