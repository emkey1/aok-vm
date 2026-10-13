#!/bin/sh
# udhcpc's script for the VM image: address, default route and resolver from the lease, with busybox alone.
# (Alpine's own script wants iproute2 for the first step and leaves the interface down without it.)
case $1 in
bound|renew)
    ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}" up
    for r in $router; do route add default gw "$r" dev "$interface" 2>/dev/null; break; done
    : > /etc/resolv.conf
    for d in $dns; do echo "nameserver $d" >> /etc/resolv.conf; done ;;
esac
