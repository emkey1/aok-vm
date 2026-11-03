# Sources of AOK VM's machines

The machines AOK VM offers are other people's free software, each under its own
licences. These assets hold the source of what is in them, at the versions they
hold. They were collected from the package databases of the machines' root
archives and disks by `aok/images/sources/collect.py` in
https://github.com/emkey1/aok-vm.

| Machines | What they hold | Asset |
|---|---|---|
| All Alpine and Devuan machines | Linux 6.18.55: Alpine's `linux-virt`, and `linux-lts` on riscv64 | `sources-linux-6.18.55-r0-alpine.tar` |
| Alpine 3.24.2, each architecture | 14 source packages, among them BusyBox, apk-tools, musl and OpenRC | `sources-alpine-3.24.2.tar` |
| Devuan 6, each architecture | 66 source packages, among them glibc, GCC's libraries, coreutils and bash | `sources-devuan-6.tar` |
| ReactOS | ReactOS 0.4.16, tag `0.4.16-release` (822e8647792a) | `sources-reactos-0.4.16.tar` |
| KolibriOS, KolibriOS with Extras | KolibriOS 0.7.7.0+8930, commit d50642ce1f | `sources-kolibrios-0.7.7.0-8930.tar` |
| FreeDOS 1.4 | The official LiveCD it is installed from | `sources-freedos-1.4.tar` |
| All | The scripts that make the machines, and AOK VM's changes to ReactOS | `sources-aok-vm-machine-scripts.tar` |

## In each asset

- **Linux:** kernel.org's `linux-6.18.tar.xz` and `patch-6.18.55.xz`, and Alpine's
  `main/linux-lts` (its build recipe and configurations) at the commit the packages
  name. `INDEX.json` says which.
- **Alpine:** for each source package, its `aports` directory at the commit the
  package names, with the upstream files that recipe fetches, checked against its
  SHA-512 sums. `INDEX.json` lists them, with their licences.
- **Devuan:** each source package as Debian and Devuan publish it: its `.dsc` and the
  files it names, checked against the `.dsc`. `INDEX.json` lists them, with the
  architectures whose roots have them.
- **ReactOS:** the tag's source as GitHub serves it. It is the commit the machine's
  desktop reports. The machine's disk also has a small change to `usbhub.sys`, whose
  source and patch are `aok/reactos/usbhub-wait` in the scripts asset, offered to
  ReactOS as reactos/reactos#9751.
- **KolibriOS:** the commit's source, from https://git.kolibrios.org/KolibriOS/kolibrios.
  "KolibriOS with Extras" adds the `kolibrios` folder of the CD of that revision. Its
  programs are each under their own licences; see the `README` on that CD.
- **FreeDOS:** `FD14-LiveCD.zip` as FreeDOS publishes it. Each of its 191 packages
  has a `SOURCE` folder.

## Not here

- AOK VM's own code: https://github.com/emkey1/aok-vm.
- The engine, and the firmware QEMU builds and carries:
  https://github.com/emkey1/qemu, at the commit `aok/ENGINE` names for a release of
  the app.
- `/AOK/tools` and `aok-update` in the Alpine and Devuan machines: iSH-AOK's, and
  `aok/machine` in the scripts asset.

Problems: https://github.com/emkey1/aok-vm/issues
