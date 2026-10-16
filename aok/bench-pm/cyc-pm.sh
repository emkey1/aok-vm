#!/bin/bash
# cyc-pm.sh REPS [WORKLOADS] -- the race for the PowerPC Mac (mac99, ppc32) and the 68k Mac (q800) guests:
# UTM's QEMU 10.0.12 with TCTI (what AOK VM shipped for these machines through build 6) against this fork's
# tree with TCTI (src-aok, utm-gl), host CPU cycles per workload as cycwrap counts them. Both engines get UTM's
# firmware (src/pc-bios: OpenBIOS for the PowerPC Mac), as the app gives them. The guests are the kit's
# (~/aok-vm-bench/kit/ppc, kit/m68k: build-kit.sh in aok-vm's aok/bench-pm). GUESTS narrows the list.
W=$HOME/aok-vm-bench; reps=${1:-2}; list=${2:-coremark,nbody,xz,sha256,awk}
common="-display none -monitor none -serial stdio -no-reboot"
one() { # one GUEST ENGINE
  local g=$1 eng=$2 b q con
  case $eng in utm) b=$W/build-pm-utm ;; ours) b=$W/build-pm-aok ;; esac
  case $g in
    ppc)  q="$b/qemu-system-ppc-unsigned -M mac99,via=pmu -cpu g4 -m 1024 -L $W/src/pc-bios -kernel $W/kit/ppc/vmlinux -initrd $W/kit/ppc/initramfs.cpio"; con=ttyS0 ;;
    m68k) q="$b/qemu-system-m68k-unsigned -M q800 -m 256 -L $W/src/pc-bios -kernel $W/kit/m68k/vmlinux -initrd $W/kit/m68k/initramfs.cpio"; con=ttyS0 ;;
  esac
  env QEMU_AOK=0 "$W/cycwrap" -q "$g-$eng" $q $common -append "console=$con rdinit=/init quiet bench=$list" < /dev/null 2>&1 | grep -a "^WL "
}
for r in $(seq $reps); do
  for g in ${GUESTS:-ppc m68k}; do
    one $g utm
    one $g ours
  done
done
echo CYC-DONE
