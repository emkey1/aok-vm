#!/bin/sh
# rename-user.sh OLD NEW -- run as root in Mac OS X 10.4: the account OLD becomes NEW (same uid, gid and
# generated uid, so its files and its password stay its own), its own group and home folder too, its place in
# every group that lists it, and auto-login. A link OLD -> NEW is left in /Users for paths stored in full.
# Then the machine restarts.
set -e
O=$1; N=$2
[ -n "$O" ] && [ -n "$N" ] && [ "$(id -u)" = 0 ] || { echo "usage: sudo sh rename-user.sh OLD NEW"; exit 1; }
niutil -read . /users/$O > /dev/null
niutil -read . /users/$N > /dev/null 2>&1 && { echo "$N exists already"; exit 1; }
[ -e /Users/$N ] && { echo "/Users/$N exists already"; exit 1; }
niutil -createprop . /users/$O home /Users/$N
niutil -createprop . /users/$O realname $N
niutil -createprop . /users/$O name $N
if niutil -read . /groups/$O > /dev/null 2>&1; then niutil -createprop . /groups/$O name $N; fi
for g in $(niutil -list . /groups | awk '{print $2}'); do
    if niutil -readprop . /groups/$g users 2>/dev/null | tr ' ' '\n' | grep -qx "$O"; then
        niutil -destroyval . /groups/$g users $O
        niutil -appendprop . /groups/$g users $N
        echo "group $g: $O -> $N"
    fi
done
mv /Users/$O /Users/$N
ln -s $N /Users/$O
L=/Library/Preferences/com.apple.loginwindow
if [ "$(defaults read $L autoLoginUser 2>/dev/null)" = "$O" ]; then defaults write $L autoLoginUser $N; fi
if [ "$(defaults read $L lastUserName 2>/dev/null)" = "$O" ]; then defaults write $L lastUserName $N; fi
lookupd -flushcache
id $N
echo "RENAMED $O -> $N; restarting"
sleep 2
shutdown -r now
