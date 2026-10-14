---
name: AOK VM issue
about: Report an issue or crash in AOK VM
title: ''
labels: ''
assignees: ''

---

AOK VM is a fork of UTM, made by the iSH-AOK project. Please report its problems here, not to UTM's developers, who do not support it. Search first: comment on an existing issue rather than opening a new one.

**Describe the issue**
What happened, and what you expected instead.

**Configuration (required)**
* AOK VM version (What's New, or Settings):
* iPadOS / iOS version:
* Device model:
* The machine: one of AOK VM's (which one), or your own (its architecture and system)
* How did you install AOK VM? (TestFlight, ...)

**Crash log**
If the app crashed, attach its crash log: in the Settings app, `Privacy & Security -> Analytics & Improvements -> Analytics Data`, the latest entry for UTM SE (AOK VM's program file is still named that). Export the text and attach it here.

**Debug log**
For all issues, crashes included, a debug log helps: open the machine's settings, turn on `Debug Log` (the `QEMU` page), save, reproduce the issue, quit the machine, then `Export Log...` from its settings and attach it here.

**The machine**
(Optional) The machine's `config.plist`, inside its `.utm`. The whole `.utm` contains your data; if you share it, use a file service and link it here.
