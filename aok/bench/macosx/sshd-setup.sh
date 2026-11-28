# s.sh [KEYFILE] -- in the Tiger guest, with tigersrc installed: its OpenSSH as the ssh server, started at boot
# by launchd on port 22, with host keys made here, and the public key in KEYFILE allowed for this user.
sudo /usr/pkg/bin/ssh-keygen -A
cat > /tmp/org.pkgsrc.sshd.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>org.pkgsrc.sshd</string>
    <key>ProgramArguments</key>
    <array><string>/usr/pkg/sbin/sshd</string><string>-D</string></array>
    <key>RunAtLoad</key><true/>
    <key>OnDemand</key><false/>
</dict>
</plist>
PL
sudo cp /tmp/org.pkgsrc.sshd.plist /Library/LaunchDaemons/org.pkgsrc.sshd.plist
sudo chown root:wheel /Library/LaunchDaemons/org.pkgsrc.sshd.plist
sudo launchctl load -w /Library/LaunchDaemons/org.pkgsrc.sshd.plist
if [ -n "$1" ]; then
    mkdir -p $HOME/.ssh; chmod 700 $HOME/.ssh
    cat "$1" >> $HOME/.ssh/authorized_keys; chmod 600 $HOME/.ssh/authorized_keys
fi
sleep 3
ps ax -o pid,command | grep "[s]shd"
echo SSH-DONE
