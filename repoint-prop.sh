#!/bin/sh
# Points a world's saved props (portals, or anything an admin saved with "Save to server") at a new
# build of a prop bundle: every saved <CombinedURL> whose file is <old file> gets <new file>, in the
# same folder. Upload the new build under a new file name first.
# The saved files hold the bundle unlock password: nothing here prints them, and the originals are
# copied to worlds/<slug>/prop-backup-<time>/ (root only) first. The world is stopped for the edit
# and started again, with its dashboard.
# Usage: sudo ./repoint-prop.sh [--check] [--force] <slug> <old file> <new file>
#   e.g. sudo ./repoint-prop.sh forest PortalToHub.BEE PortalToHub-v2.BEE
#   --check  report which saved files use <old file>, the new URL's status and the players; change nothing
#   --force  go ahead with players connected
set -eu
cd "$(dirname "$0")"
check=no
force=no
while [ $# -gt 0 ]; do
  case $1 in
    --check) check=yes ;;
    --force) force=yes ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
[ $# -eq 3 ] || { echo "usage: $0 [--check] [--force] <slug> <old file> <new file>" >&2; exit 2; }
slug=$1
old=$2
new=$3
case "$old$new" in *[!A-Za-z0-9._-]*) echo "file names only, with letters, digits, '.', '_' and '-'" >&2; exit 1 ;; esac
[ "$(id -u)" = 0 ] || { echo "run with sudo (the saved props belong to root)" >&2; exit 1; }
dir=worlds/$slug/initialresources
[ -d "$dir" ] || { echo "no $dir" >&2; exit 1; }

oldre=$(printf '%s' "$old" | sed 's/\./\\./g')
pattern="<CombinedURL>[^<]*/$oldre</CombinedURL>"
files=$(grep -l -E "$pattern" "$dir"/saved-*.xml 2>/dev/null || true)
if [ -z "$files" ]; then
  echo "$slug: no saved prop uses $old. Saved props use:" >&2
  sed -n 's|.*<CombinedURL>.*/\([^/<]*\)</CombinedURL>.*|  \1|p' "$dir"/saved-*.xml 2>/dev/null | sort | uniq -c >&2
  exit 1
fi
# shellcheck disable=SC2086
oldurls=$(grep -h -o -E "$pattern" $files | sed -e 's|<CombinedURL>||' -e 's|</CombinedURL>||' | sort -u)
[ "$(echo "$oldurls" | wc -l)" = 1 ] || { echo "$slug: the saved props load $old from more than one folder; edit them by hand" >&2; exit 1; }
oldurl=$oldurls
newurl="${oldurl%/*}/$new"
code=$(curl -s -o /dev/null -w '%{http_code}' -I -m 20 "$newurl" || true)
port=$(docker compose port "$slug" 10666 2>/dev/null | sed 's/.*://')
players=$(curl -fsS -m 5 "127.0.0.1:$port/health" 2>/dev/null | sed -n 's/.*"visitors":\([0-9]*\).*/\1/p')
echo "$slug: $(echo "$files" | wc -l) saved prop file(s) use $oldurl"
echo "$slug: new $newurl (HTTP $code), players ${players:-unknown}"
[ "$old" != "$new" ] || { echo "$slug: already on $new"; exit 0; }
[ "$code" = 200 ] || { echo "$slug: the new URL isn't live; upload it first" >&2; exit 1; }
if [ "${players:-0}" != 0 ] && [ "$force" = no ]; then
  echo "$slug: $players player(s) connected; ask them first, then rerun with --force" >&2; exit 1
fi
[ "$check" = no ] || { echo "check only, nothing changed"; exit 0; }

backup=worlds/$slug/prop-backup-$(date +%Y%m%d-%H%M%S)
mkdir -m 700 "$backup"
# shellcheck disable=SC2086
cp -p $files "$backup/"
docker compose stop "$slug"
for f in $files; do
  sed -i -E "s#(<CombinedURL>[^<]*/)$oldre(</CombinedURL>)#\1$new\2#" "$f"
  if ! grep -q -F "<CombinedURL>$newurl</CombinedURL>" "$f"; then
    echo "$f: the edit didn't take; putting the originals back" >&2
    cp -p "$backup"/* "$dir/"
    docker compose start "$slug"
    exit 1
  fi
done
docker compose start "$slug"
if [ -n "$(docker compose --profile dashboard ps -q "$slug-dashboard" 2>/dev/null)" ]; then
  docker compose --profile dashboard restart "$slug-dashboard"
fi
i=0
until curl -fsS -m 5 "127.0.0.1:$port/health" 2>/dev/null | grep -q '"ready":true'; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { echo "$slug: not ready after 120 s" >&2; exit 1; }
  sleep 2
done
echo "$slug: ready; its saved props now load $newurl (originals in $backup)"
