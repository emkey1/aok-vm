# A Mac OS 9 disk for testing (2026-11-27)

Not for distribution: Mac OS is Apple's. The user gave the sources, archive.org's item
`mac-os9`: `MacOS9.iso` (Mac OS 9.2.2's CD; sha256 1bedd15e...269b7) and `MacOS9.img`
(2 GB; sha256 afeba601...c2a1). Both are on MBP5 in `~/aok-vm-bench/macos9/{iso,img}`.

`MacOS9.img` looks blank from outside (its HFS wrapper holds five files and is named
"untitled") but is a Mac OS Extended disk with a fresh Mac OS 9.2.1 installed and never
started: Apple's drivers, System Folder, Applications (Mac OS 9), 1.2 GB free.

**The test disk** is a copy of it, `macos9/hd/os9-hd.img` on MBP5 (as qcow2 beside it, 306
MB), changed only inside Mac OS: started once, the Setup Assistant quit, the disk named
Macintosh HD, shut down from the Special menu. It starts to the Finder with no questions:
on Homebrew's QEMU 11.1.2 and on our engine with the devices the app gives a mac99
machine, and in the app on the A10X as the machine "Mac OS 9" (mac99, VGA, USB 2.0, the
disk on IDE; the Finder about two minutes after the start).

Not done: the update to 9.2.2 from the CD, which stops at Apple's licence agreement (the
user's to accept), and added software (downloads, the user's to approve).

**Driving Mac OS from outside.** With UTM's NDRV loader and a virtio tablet the guest has a
pointer that takes positions, so QMP's `input-send-event` clicks exactly where it is told:
`qmp.py SOCKET click X Y`, `dclick`, `key meta_l-q`, `type "Macintosh HD"`, `shot FILE.ppm`
(screen positions in the screen's pixels, 640x480 there). `os9-inst-start.sh cd|hd` starts
the CD with the disk attached, `os9-hd-start.sh brew|new` the disk alone with the app's
devices, `look.sh NAME ACTIONS...` acts and leaves a picture. Menus stay open after a
click, so a menu item is two clicks: Special is at 245,10 and its Shut Down at 270,135.
The machine needs `usb=on` (../upstream-fixes/README.md, last section).
