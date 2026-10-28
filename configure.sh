#!/bin/sh
# Generates docker-compose.yml and every worlds/<slug>/initialresources/world.xml from worlds.conf
# and .env. With WEB_PLAYERS=yes it also writes caddy/Caddyfile and each world's
# config/transports/websocket.xml. Re-run it after editing either file, then `sudo docker compose up -d`.
set -eu
cd "$(dirname "$0")"
[ -f .env ] || { echo ".env missing: cp .env.example .env, then fill it in" >&2; exit 1; }
[ -f worlds.conf ] || { echo "worlds.conf missing" >&2; exit 1; }
web=$(sed -n 's/^WEB_PLAYERS=//p' .env | tail -n 1 | tr -d "\"'\r")
# Folders first: awk can write files but not create directories.
mkdir -p caddy
for slug in $(sed -e 's/#.*//' worlds.conf | awk 'NF >= 4 && $1 ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ { print $1 }'); do
  mkdir -p "worlds/$slug/initialresources" "worlds/$slug/config/transports" "worlds/$slug/storage" "worlds/$slug/defaultlibrary"
  if [ "$web" = yes ] && [ ! -w "worlds/$slug/config/transports" ]; then
    echo "worlds/$slug/config/transports isn't writable (the server created it as root): run sudo ./configure.sh" >&2
    exit 1
  fi
done
umask 077   # world.xml holds the bundle unlock password
awk -f lib/configure.awk .env worlds.conf
