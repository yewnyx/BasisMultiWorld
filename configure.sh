#!/bin/sh
# Generates docker-compose.yml and every worlds/<slug>/initialresources/world.xml from worlds.conf
# and .env. Re-run it after editing either file, then `sudo docker compose up -d`.
set -eu
cd "$(dirname "$0")"
[ -f .env ] || { echo ".env missing: cp .env.example .env, then fill it in" >&2; exit 1; }
[ -f worlds.conf ] || { echo "worlds.conf missing" >&2; exit 1; }
# Folders first: awk can write files but not create directories.
for slug in $(sed -e 's/#.*//' worlds.conf | awk 'NF >= 4 && $1 ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ { print $1 }'); do
  mkdir -p "worlds/$slug/initialresources" "worlds/$slug/config" "worlds/$slug/storage"
done
umask 077   # world.xml holds the bundle unlock password
awk -f lib/configure.awk .env worlds.conf
