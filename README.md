# BasisMultiWorld

[日本語](README.ja.md)

> **Status: snapshot (2026-10-28).** Built and tested against Basis `2f5b3e106`. This isn't
> maintained on a schedule, and Basis moves fast, so check upstream before relying on it. Issues
> and pull requests are welcome but may wait.

Run several [Basis](https://github.com/BasisVR/Basis) worlds on one small server, each under its
own name (`forest.worlds.example.com`), using DNS SRV records. Players type a name, never a port.

- **One file describes the worlds** (`worlds.conf`). `configure.sh` turns it into the Docker
  Compose file and each server's world config.
- **Basis isn't forked.** The server is built from a pinned commit of upstream `Basis Server/`.
- **DNS records are generated** for you to import.
- **Optional extras:** portals between worlds (a tested prop script), per-world admin dashboards,
  and web players (WebSocket behind a generated Caddy TLS front).

**Start here: [the tutorial](docs/tutorial.md).**

```sh
cp .env.example .env && chmod 600 .env     # fill it in
$EDITOR worlds.conf                        # one line per world; the first one is the hub, on 4296
./fetch-basis.sh && ./configure.sh && sudo docker compose up -d --build
./dns-records.sh <server-ipv4> > records.txt   # import into your DNS (DNS-only, no proxy)
```

Players need a Basis client built from `experimental-branch-major-changes` at `41789fb7d` or
later for SRV lookups. Older clients still connect, but always land in the hub.

## AI disclosure

This repository's scripts, configuration and documentation, including the Japanese translation,
were written with the help of an AI coding assistant. The maintainer directs, reviews and stands
behind every change. As in Basis's [AI.md](https://github.com/BasisVR/Basis/blob/developer/AI.md),
individual commits aren't tagged; this note is the disclosure. Corrections to the Japanese are welcome.

MIT licensed. See [LICENSE](LICENSE).
