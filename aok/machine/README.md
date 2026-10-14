# What an AOK VM machine carries

`tools/` is the machine's `/AOK/tools` and `aok-update` its
`/usr/local/bin/aok-update`: the base machines get both (`aok/images`), and
`aok-update`, run in a machine, fetches them again from this directory of the
repository on GitHub, so a fix reaches machines already made.

They were iSH-AOK's (`opt/AOK/tools` and `tests/bench-utm/utm/vm-update.sh`,
its commit d127efaa8), copied here on 2026-10-14. They are this repository's own
since: edit them here. The scripts still know how to run inside iSH-AOK as
well as on a machine of its own (they look for `/proc/ish`), which nothing
here needs; that can go when they are next worked on.
