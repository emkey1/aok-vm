#!/bin/bash
# on MBP5: ssh-check.sh PORT -- what a user of the Tiger guest's ssh gets: a login by password, and by key a login
# shell with tigersrc's tools on the path and pkg_add working through sudo (a dry run).
cd ~/aok-vm-bench/macosx; P=${1:-2222}
O=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o LogLevel=ERROR -p $P)
printf '#!/bin/sh\ncat %s\n' "$PWD/.pw" > sshtest/ap.sh; chmod 700 sshtest/ap.sh
echo "password login: $(SSH_ASKPASS=$PWD/sshtest/ap.sh SSH_ASKPASS_REQUIRE=force ssh -n "${O[@]}" -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no timcook@127.0.0.1 echo ok 2>&1 | tail -1)"
echo "key, interactive-style login shell:"
ssh -n "${O[@]}" -i sshtest/k timcook@127.0.0.1 'bash -lc "which pkg_add pkg_info curl python3.10; echo PKG_PATH=\$PKG_PATH; echo password | sudo -S -p \"\" pkg_add -n zip > /tmp/n.out 2>&1; echo pkg_add-dry-run-exit \$?; tail -2 /tmp/n.out"'
echo "key, plain command (no profile): $(ssh -n "${O[@]}" -i sshtest/k timcook@127.0.0.1 'which pkg_info || echo not-on-path' 2>&1 | tail -1)"
