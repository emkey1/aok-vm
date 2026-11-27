# A Mac OS 9 disk for testing (2026-11-27)

Not for distribution: Mac OS is Apple's. The user gave the sources, archive.org's item
`mac-os9`: `MacOS9.iso` (Mac OS 9.2.2's CD; sha256 1bedd15e...269b7) and `MacOS9.img`
(2 GB; sha256 afeba601...c2a1). Both are on MBP5 in `~/aok-vm-bench/macos9/{iso,img}`.

`MacOS9.img` looks blank from outside (its HFS wrapper holds five files and is named
"untitled") but is a Mac OS Extended disk with a fresh Mac OS 9.2.1 installed and never
started: Apple's drivers, System Folder, Applications (Mac OS 9), 1.2 GB free.

**The test disk** is a copy of it, `macos9/hd/os9-hd.img` on MBP5 (as qcow2 beside it, 612
MB; sha256 of the raw disk d2793830...), changed only from inside Mac OS and, for the
downloads, from macOS:

- started once, the Setup Assistant quit, the disk named Macintosh HD;
- updated to Mac OS 9.2.2 with the CD's updater (the user's yes to Apple's licence), with
  "Update Apple Hard Disk Drivers" unticked in its Options;
- a folder Freeware, the user's choice of 2026-11-27 (os9-dl.sh; the downloads are kept in
  `macos9/dl`, one directory a file): Classilla 9.3.3 and MacSSH PPC 2.1fc3 from their
  SourceForge projects, Marathon, Marathon 2 and Marathon Infinity from Bungie's trilogy
  release (files3.bungie.org/trilogy), BBEdit Lite 6.1.2, SoundApp 2.7.3 (PPC) and Gauge
  PRO 1.1 from Macintosh Garden. os9-put.sh copied the archives onto the volume from macOS
  (which reads and writes Mac OS Extended, wrapper and all) with StuffIt Expander's creator,
  and Mac OS's own StuffIt Expander 6.0 unpacked them: select them, Open. BBEdit Lite comes
  as a self-mounting image, whose volume was dragged onto the disk. The archives were then
  emptied from the Trash. Only Gauge PRO was started (it says PowerPC 7400, G4).

It starts to the Finder with no questions: on Homebrew's QEMU 11.1.2 and on our engine with
the devices the app gives a mac99 machine, and in the app on the A10X as the machine "Mac
OS 9" (mac99, VGA, USB 2.0, a sungem network card, the disk on IDE; the Finder two minutes
after the start). Kept beside it on MBP5: `os9-hd-921.img` (named, before the update) and
`os9-hd-922.img` (updated, before the freeware).

**A Power Mac wants its network card too.** The first machine on the A10X had none, and the
user found Network Browser locking Mac OS up: the pointer moves, nothing answers, the clock
stops. Homebrew's QEMU does the same with `-nic none`, and with `-nic user,model=sungem`
Network Browser lists its two items at once; so does the app's machine with a sungem card.
Mac OS's doing, not the engine's: give a Mac OS 9 machine a network card.

**Driving Mac OS from outside.** With UTM's NDRV loader and a virtio tablet the guest has a
pointer that takes positions, so QMP's `input-send-event` clicks exactly where it is told:
`qmp.py SOCKET click X Y`, `dclick`, `drag`, `key meta_l-q`, `keydown shift` ... `keyup shift`
(a shift-click adds one item to a selection), `type "Macintosh HD"`, `shot FILE.ppm`; SOCKET
may be HOST:PORT for a machine in the app started with `-qmp tcp:0.0.0.0:PORT,server=on,wait=off`
in its additional arguments (take it out again afterwards)
(screen positions in the screen's pixels, 640x480 there). `os9-inst-start.sh cd|hd` starts
the CD with the disk attached, `os9-hd-start.sh brew|new` the disk alone with the app's
devices, `look.sh NAME ACTIONS...` acts and leaves a picture. Menus stay open after a
click, so a menu item is two clicks: Special is at 245,10 and its Shut Down at 270,135.
The machine needs `usb=on` (../upstream-fixes/README.md, last section).
