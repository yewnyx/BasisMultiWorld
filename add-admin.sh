#!/bin/sh
# Adds player DIDs to the "admin" group in every world's config/permissions.xml.
# Stop the servers first so they don't overwrite the file on exit:
#   sudo docker compose stop && sudo ./add-admin.sh did:key:z6Mk... && sudo docker compose start
# BasisFirstAdmin only seeds admins on a server's very first boot; this is for afterwards.
set -eu
cd "$(dirname "$0")"
[ $# -gt 0 ] || { echo "usage: $0 did:key:z... [did:key:z...]" >&2; exit 64; }
for did in "$@"; do
  printf '%s' "$did" | grep -Eq '^did:key:z[1-9A-HJ-NP-Za-km-z]+$' || { echo "not a did:key: $did" >&2; exit 65; }
done
for file in worlds/*/config/permissions.xml; do
  [ -f "$file" ] || continue
  for did in "$@"; do
    if grep -q "<User uuid=\"$did\">" "$file"; then
      echo "$file: $did already listed (check its groups by hand if it isn't admin)"
      continue
    fi
    grep -q '</Users>' "$file" || { echo "$file: no <Users> block; start that server once first" >&2; exit 1; }
    tmp=$(mktemp)
    awk -v did="$did" '
      /<\/Users>/ && !done { print "    <User uuid=\"" did "\">"; print "      <Group name=\"default\" />"; print "      <Group name=\"admin\" />"; print "    </User>"; done = 1 }
      { print }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"   # keeps the file's owner and mode
    rm -f "$tmp"
    echo "$file: added $did to admin"
  done
done
