# More software in the ReactOS machine

What it would take to give ReactOS.utm more programs than ReactOS ships with,
using only software whose licence allows it. Explored on 2026-10-28.

**Decided (the user, 2026-10-28): on demand.** Users install programs with
the Applications Manager; no "ReactOS Plus" image. The machine's notes and
its line in the list say so (make-vm.py, ../images/index.py: in the next
images). Left: RAPPS tried on the AOK engine on an iPad (the Mac's AOK build
has no user-mode network), and the sources below.

## What is there to choose from

ReactOS's own Applications Manager (RAPPS, already on the machine's desktop)
reads a catalogue, [reactos/rapps-db](https://github.com/reactos/rapps-db):
402 programs, each with its download URL, SHA-1, size and licence, chosen
because they run on ReactOS (that is, on Windows XP/2003-era APIs). By their
`License` field, 217 are open source (GPL, LGPL, MIT, BSD, MPL, Apache, public
domain and the like). The rest are freeware, shareware, EULAs or trials: their
licences mostly forbid passing them on, so they are out.

The open-source ones by category: games 53, development 35, internet 34,
tools 26, audio 14, office 10, other 10, graphics 9, video 8, libraries 8,
edutainment 5, science 3, finance 1, engineering 1.

## Two ways to get them into the machine

**1. Installed when the user wants them (works today).** In the VM, RAPPS
fetches the catalogue and the installers over HTTPS from their own sites. On
MBP5 (`rapps-probe.sh`: the finished disk, Homebrew's QEMU with the network,
`rapps /INSTALL /S 7zip putty sumatrapdf` typed in the Run box), 7-Zip and
PuTTY were downloaded and installed with no questions in under a minute.
RAPPS 0.4.16 recognises NSIS, Inno Setup and MSI installers and supplies their
silent switches itself. SumatraPDF has an installer of its own, which RAPPS
cannot guess, so it waited for a click. Nothing is passed on by us, so there
is nothing to comply with: the user gets each program from its maker. The
cost is a network connection and the wait. Not yet tried on the iPad.

**2. Installed in the image ("ReactOS Plus").** A script after build.sh boots
the finished disk with the installers on a CD and runs them silently, with
the switches each one needs written down in a manifest of our own (URL and
SHA-1 taken from the RAPPS entry, so the download is checked). The machine
starts with the programs in place, offline. But then **we** are passing them
on, and each licence asks something of that:

- **GPL and LGPL** (most of the list): the matching source, published beside
  the image (the same release on GitHub is "the same place", which both GPLv2
  and GPLv3 accept), and each licence's text in the image.
- **MPL 2.0** (Firefox 52 ESR, Mypal, Thunderbird): the licence text and
  where its source is. Firefox's and Thunderbird's names and logos are
  Mozilla's trademarks; passing on the unmodified official build has to be
  checked against Mozilla's trademark policy first. Mypal and K-Meleon avoid
  the question.
- **MIT, BSD, Apache**: the licence and copyright notices in the image.

The image also grows: the starter set below is about 160 MB of installers.

**This applies to ReactOS itself already.** ReactOS is GPLv2, and the
existing ReactOS.utm passes it on. Its source (ReactOS-0.4.16's source
archive) should be published with the image whichever way this goes.

## With no network: a CD

For a machine that has no network (an iPad away from Wi-Fi; asked for on
2026-10-29), `software-cd/make-cd.sh OUT.iso` makes a CD of the starter set
below on a Mac: the installers from `software-cd/manifest.txt` (RAPPS's URLs
and SHA-1s, except OpenTTD's zip build with OpenGFX, its base graphics, in
`baseset`: the installer in RAPPS downloads OpenGFX even when silent and stops
on "Downloading of OpenGFX failed" with no network), and `INSTALL.CMD`, which
runs each with its silent switch (NSIS `/S`, Inno Setup `/VERYSILENT ...`, MSI
`msiexec /qn`, SumatraPDF `-s`, Mypal `-ms`), copies the four that come as zips, makes their Start menu
entries (`SHORTCUTS.VBS`) and logs to `C:\AOK-install.log`. The user's own
copy, made on their Mac: nothing is passed on by us.

WinSCP's installer installs, then never exits on ReactOS 0.4.16 (it runs
WinSCP.exe twice at the end; both setup processes were still running at
shutdown), so `INSTALL.CMD` starts it last and does not wait for it.

`software-cd/test-cd.sh ISO` tries it on MBP5: the finished disk, no network,
the CD on `ide.1`, `INSTALL.CMD` typed in the Run box, then the log, Program
Files and the Start menu read off the disk.

**Putting the CD in the machine.** The machines in the list have one IDE disk
and no CD drive. The app gives a second IDE drive `ide.1`, where `build.sh`'s
install CD was, so ReactOS already knows the drive and asks nothing. With the
machine shut down: its settings, Drives, a new CD/DVD drive on IDE with the
ISO imported. Or from a Mac with the app closed: the ISO copied into the
bundle's `Data/` and a drive added to its `config.plist`
(`{"ImageName": "aok-programs.iso", "ImageType": "CD", "Interface": "IDE",
"InterfaceVersion": 1, "ReadOnly": true, "Identifier": ...}`) with devicectl.
The CD is D:; double-click `INSTALL.CMD` on it.

## A starter set

Small, open source, XP-era builds that are in the RAPPS catalogue (package
name, licence, installer size):

| | Programs |
|---|---|
| Internet | Mypal 29.3 (`mypal`, MPL, 34 MB) or K-Meleon 75.1 (`kmeleon`, GPL, 27 MB); PuTTY (`putty`, MIT, 3.5 MB); WinSCP 5.7.7 (`winscp`, GPLv3, 5.9 MB) |
| Tools | 7-Zip (`7zip`, LGPL, 1.4 MB); Notepad++ 6.9 (`npp`, GPL, 4.2 MB); Explorer++ (`explorerpp`, GPLv3, 0.6 MB) |
| Documents | SumatraPDF 3.1.2 (`sumatrapdf`, GPLv3, 4.9 MB); AbiWord 2.9.4 (`abiword`, GPL, 9.9 MB) |
| Media | Media Player Classic HC (`mpc`, GPL, 13 MB) |
| Fun | TuxPaint (`tuxpaint`, GPL, 14 MB); LZDoom with Freedoom (`lzdoom`, GPL/BSD, 39 MB); OpenTTD 1.10 (`openttd`, GPLv2, 5.2 MB); The Powder Toy (`thepowdertoy`, GPL, 1.8 MB); DOSBox (`dosbox`, GPL, 1.5 MB) |
| Programming | Python 3.4.4 (`python`, the PSF licence, 25 MB); Tiny C Compiler (`tcc`, LGPL, 0.5 MB) |

Larger ones the catalogue has, if size does not matter: LibreOffice 5.4
(225 MB), GIMP 2.8 (90 MB), VLC 3.0 (45 MB), Inkscape 0.48 (35 MB), Firefox 52
ESR (45 MB), SuperTux (90 MB), ScummVM (125 MB).

Every one has to be tried on the AOK engine, on the Mac and then on an iPad,
before it goes in: open it, use it, picture. On the iPad's speed (ReactOS's
desktop in 13 s) the big office and graphics suites will be slow.

## Recommendation

Both, in this order:

1. Keep ReactOS.utm small and make on-demand install the way to get more:
   check RAPPS on the iPad, and put a short note on the desktop. No licence
   work beyond ReactOS's own source.
2. Then, if wanted, a second catalogue machine, "ReactOS Plus", built by a
   script from the manifest above, with `C:\Licenses` (each licence and
   where its source is) and the sources published with the image.

Separately, publish ReactOS's own source with the existing image.
