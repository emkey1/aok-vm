# p.sh -- in the Tiger guest: tigersrc (pkgsrc for 10.4 PowerPC) from its bootstrap kit, the two lines its page
# asks for in the profile, and a first few packages. Only /usr/pkg is taken from the kit.
cd /tmp
curl -s -O http://10.0.2.2:8643/bootstrap-tiger.tar.gz
sudo tar -C / -xzpf bootstrap-tiger.tar.gz ./usr/pkg
P=https://ftp.NetBSD.org/pub/pkgsrc/misc/nia/tigersrc/packages/All/
grep -q usr/pkg $HOME/.bash_profile 2>/dev/null
if [ $? != 0 ]; then
    echo "export PATH=/usr/pkg/sbin:/usr/pkg/bin:\$PATH" >> $HOME/.bash_profile
    echo "export PKG_PATH=$P" >> $HOME/.bash_profile
fi
for p in curl wget openssh python310; do
    sudo env PATH=/usr/pkg/sbin:/usr/pkg/bin:$PATH PKG_PATH=$P pkg_add $p
    echo "PKG $p: $?"
done
rm -f /tmp/bootstrap-tiger.tar.gz
echo PKG-DONE
