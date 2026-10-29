#!/bin/sh
# Switches worlds to the bundle worlds.conf now names for them. For each world it checks that the new
# URL is live and that nobody is in the world (unless --force). Then it runs configure.sh, restarts
# each world and its dashboard, and waits until the world reports ready.
# Upload a new build under a NEW file name and put that name in worlds.conf first: the Basis client
# and CDNs cache by URL, so a file replaced at the same URL may never reach players who loaded it.
# Usage: sudo ./deploy-world.sh [--check] [--force] <slug>...
#   --check  report the current and new URL, whether the new one is live, and the players; change nothing
#   --force  restart even with players connected, or when world.xml already has the new URL
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
[ $# -gt 0 ] || { echo "usage: $0 [--check] [--force] <slug>..." >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run with sudo (it drives docker and reads world.xml)" >&2; exit 1; }
[ -f .env ] && [ -f worlds.conf ] || { echo ".env or worlds.conf missing" >&2; exit 1; }
cdn=$(sed -n 's/^CDN_BASE=//p' .env | tail -n 1 | tr -d "\"'\r")

# The URL worlds.conf gives a world, built the way configure.sh builds it.
wanted() { sed -e 's/#.*//' worlds.conf | tr -d '\r' | awk -v s="$1" -v cdn="$cdn" '$1 == s && NF >= 4 { print ($3 ~ /^https:\/\// ? $3 : cdn "/" $3); exit }'; }
# The URL the world loads now (it reads world.xml when it starts).
current() { sed -n 's|.*<CombinedURL>\(.*\)</CombinedURL>.*|\1|p' "worlds/$1/initialresources/world.xml" 2>/dev/null | sed 's/&amp;/\&/g'; }
health_port() { docker compose port "$1" 10666 2>/dev/null | sed 's/.*://'; }
visitors() { curl -fsS -m 5 "127.0.0.1:$(health_port "$1")/health" 2>/dev/null | sed -n 's/.*"visitors":\([0-9]*\).*/\1/p'; }

# configure.sh rewrites every world.xml. A world left out here whose bundle also changed would get
# the new world.xml without a restart, and a later run would skip it as already done.
for slug in $(sed -e 's/#.*//' worlds.conf | awk 'NF >= 4 { print $1 }'); do
  case " $* " in *" $slug "*) continue ;; esac
  [ -f "worlds/$slug/initialresources/world.xml" ] || continue
  if [ "$(wanted "$slug")" != "$(current "$slug")" ]; then
    echo "worlds.conf also changes the bundle of '$slug': deploy it in the same run, or undo that edit" >&2
    exit 1
  fi
done

fail=0
todo=""
for slug in "$@"; do
  new=$(wanted "$slug")
  [ -n "$new" ] || { echo "$slug: not in worlds.conf" >&2; exit 1; }
  [ -f "worlds/$slug/initialresources/world.xml" ] || { echo "$slug: a new world; run ./configure.sh && sudo docker compose up -d" >&2; exit 1; }
  cur=$(current "$slug")
  code=$(curl -s -o /dev/null -w '%{http_code}' -I -m 20 "$new" || true)
  players=$(visitors "$slug")
  echo "$slug: now $cur"
  echo "$slug: new $new (HTTP $code), players ${players:-unknown}"
  if [ "$code" != 200 ]; then echo "$slug: the new URL isn't live; upload it first" >&2; fail=1; continue; fi
  if [ "$cur" = "$new" ] && [ "$force" = no ]; then
    echo "$slug: world.xml already has that URL, skipped (if the world started before it was written, use --force)"
    continue
  fi
  if [ "${players:-0}" != 0 ] && [ "$force" = no ]; then
    echo "$slug: $players player(s) connected; ask them first, then rerun with --force" >&2; fail=1; continue
  fi
  todo="$todo $slug"
done
[ "$fail" = 0 ] || exit 1
[ -n "$todo" ] || { echo "nothing to deploy"; exit 0; }
[ "$check" = no ] || { echo "check only, nothing changed; would deploy:$todo"; exit 0; }

./configure.sh
for slug in $todo; do
  docker compose restart "$slug"
  # The dashboard shares the world's network namespace, which the restart replaced.
  if [ -n "$(docker compose --profile dashboard ps -q "$slug-dashboard" 2>/dev/null)" ]; then
    docker compose --profile dashboard restart "$slug-dashboard"
  fi
  i=0
  until curl -fsS -m 5 "127.0.0.1:$(health_port "$slug")/health" 2>/dev/null | grep -q '"ready":true'; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { echo "$slug: not ready after 120 s" >&2; exit 1; }
    sleep 2
  done
  echo "$slug: ready on $(current "$slug")"
done
