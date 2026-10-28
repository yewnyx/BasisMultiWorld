#!/bin/sh
# Prints the DNS records for worlds.conf as a BIND file, ready to import into your DNS provider.
# The first world is the hub and also answers on the bare DNS_ZONE name.
#   Usage: ./dns-records.sh <server-ipv4> > records.txt
set -eu
cd "$(dirname "$0")"
ip=${1:?usage: $0 <server-ipv4>}
printf '%s' "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || { echo "not an IPv4 address: $ip" >&2; exit 64; }
zone=$(sed -n 's/^DNS_ZONE=//p' .env 2>/dev/null | tail -n 1)
host=$(sed -n 's/^DNS_HOST=//p' .env 2>/dev/null | tail -n 1)
[ -n "$zone" ] || { echo "set DNS_ZONE in .env (for example worlds.example.com)" >&2; exit 1; }
sed -e 's/#.*//' worlds.conf | awk -v ip="$ip" -v zone="${zone%.}" -v host="${host:-vm1}" '
  NF >= 4 { n++; slug[n] = $1; port[n] = $2 }
  END {
    if (n == 0) { print "worlds.conf lists no worlds" > "/dev/stderr"; exit 1 }
    target = host "." zone "."
    printf "%s 300 IN A %s\n", target, ip
    printf "%s. 300 IN A %s\n", zone, ip
    printf "*.%s. 300 IN A %s\n", zone, ip
    for (i = 1; i <= n; i++) printf "%s.%s. 300 IN A %s\n", slug[i], zone, ip
    printf "_basis._udp.%s. 300 IN SRV 0 0 %s %s\n", zone, port[1], target
    for (i = 1; i <= n; i++) printf "_basis._udp.%s.%s. 300 IN SRV 0 0 %s %s\n", slug[i], zone, port[i], target
  }'
