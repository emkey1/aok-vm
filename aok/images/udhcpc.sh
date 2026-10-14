#!/bin/busybox sh
# udhcpc's script in a base machine's initramfs: the address, the route and the name servers, the last
# into the root (mounted at /newroot), whose /etc/resolv.conf they become.
case $1 in
bound|renew)
    ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}" up
    for r in $router; do route add default gw "$r" dev "$interface" 2> /dev/null; break; done
    : > /newroot/etc/resolv.conf
    [ -n "$domain" ] && echo "search $domain" >> /newroot/etc/resolv.conf
    for d in $dns; do echo "nameserver $d" >> /newroot/etc/resolv.conf; done
    ;;
esac
exit 0
