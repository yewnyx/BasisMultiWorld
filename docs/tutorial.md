# Tutorial: several Basis worlds on one server

[日本語](tutorial.ja.md)

By the end you'll have several Basis worlds running on one small Linux server. Each has its own
name, and players join by typing just that name:

```
worlds.example.com          →  hub     (UDP 4296)
forest.worlds.example.com   →  Forest  (UDP 4297)
city.worlds.example.com     →  City    (UDP 4298)
```

This works through DNS SRV records ([RFC 2782](https://www.rfc-editor.org/rfc/rfc2782)). When a
player enters a name without a port, the Basis client looks up `_basis._udp.<name>` and connects
to the host and port the record names. Every world shares one IP address and listens on its own
port.

## What you need

- **A Linux server** with Docker and the compose plugin, and a public IPv4 address.
  - The servers are light: an idle world uses about 85 MB of RAM. The smallest VPS from most
    providers is plenty.
  - Building the image once takes about 1.5 GB of RAM and 2 GB of disk. On a 2 GB machine, add swap.
- **A domain** whose DNS you control. Your DNS provider must support SRV records.
- **Your worlds as `.BEE` bundles** on an HTTPS host or CDN, plus the password they were built with.
- **A Basis client new enough for SRV lookups and "Save to server":** built from upstream
  `experimental-branch-major-changes` at commit `41789fb7d` (2026-10-27) or later.
  - Older clients still connect, but to `<name>:4296`, which is always the hub.
  - Web builds can't make DNS queries at all.
- **Your player DID** (`did:key:z6Mk...`) so you can be admin.

## 1. Prepare the server

Open the UDP port of every world in the firewall: 4296 for the first world, then one more per world.
Open nothing else to the public; reach SSH through a VPN (such as Tailscale) if you can. Install Docker
Engine with the compose plugin.

## 2. Get this repository and describe your worlds

```sh
git clone https://github.com/<you>/BasisMultiWorld.git basis-worlds
cd basis-worlds
cp .env.example .env && chmod 600 .env
```

Edit `worlds.conf`. Use one line per world: slug, UDP port, bundle, display name. **The first line
is the hub. Keep it on 4296.**

```
hub      4296   Hub.BEE       My Hub
forest   4297   Forest.BEE    Forest Walk
city     4298   City.BEE      City at Night
```

Edit `.env` and fill in at least these four:

| Setting | What it is |
| --- | --- |
| `CDN_BASE` | the URL your bundles are under, no trailing slash (`https://cdn.example.com/basis`) |
| `UNLOCK_PASSWORD` | the password your bundles were built with |
| `BASIS_FIRST_ADMIN` | your DID; comma-separate several |
| `DNS_ZONE` | the name of the hub (`worlds.example.com`); every other world is `<slug>.` in front of it |

`BASIS_REF` pins the upstream Basis commit that the server is built from. The repository doesn't
contain Basis itself: `fetch-basis.sh` downloads only the `Basis Server/` folder of
[BasisVR/Basis](https://github.com/BasisVR/Basis) at that commit, which is about 11 MB.

## 3. Build and start

```sh
./fetch-basis.sh          # upstream server source → ./basis
./configure.sh            # worlds.conf + .env → docker-compose.yml + worlds/<slug>/…/world.xml
sudo docker compose up -d --build
sudo docker compose ps    # every world should become "healthy"
curl -fsS localhost:10666/health   # first world; the next ones are 10667, 10668, …
```

`configure.sh` checks `worlds.conf` first: duplicate slugs or ports, bad port numbers, a missing
password. If anything is wrong, it changes nothing. Re-run it whenever you edit `worlds.conf` or
`.env`, then run `sudo docker compose up -d`.

## 4. DNS

```sh
./dns-records.sh 203.0.113.10 > records.txt   # your server's IPv4
```

This prints the full record set in BIND format: an A record for every name, a wildcard, and one
SRV record per world. Import the file, or type the records in by hand.

- **Cloudflare:** go to DNS → Records → Import and Export → Import. Leave "Proxy imported DNS
  records" **off**. The proxy can't carry the game's UDP traffic, and every record must be "DNS only".
- **Why each world also has its own A record:** the SRV record under a name keeps the wildcard from
  covering that name. Without its own A record, a client whose SRV lookup fails would get no address
  at all, instead of landing in the hub.

Check the records:

```sh
dig +short SRV _basis._udp.forest.worlds.example.com   # → 0 0 4297 vm1.worlds.example.com.
dig +short A forest.worlds.example.com                 # → your IPv4
```

## 5. Join

In the client, connect to `worlds.example.com` with no port. You should land in the hub, as admin.
Then try `forest.worlds.example.com`.

## 6. Portals between worlds

A portal is a small prop with a door that sends the player to another world.
[`examples/ServerPortal.cs`](../examples/ServerPortal.cs) is a version tested inside props. The
creator guide's `ServerPortal` example fails in a prop. Set the door's `host` to the world's name
and leave `port` at **4296**, so the client does the SRV lookup and DNS decides where the door
leads.

Building the prop:

1. **On the prop's root object:** `BasisProp`, a **`CilboxPropBasis` (on the root itself)** and
   `ServerPortal`.
2. **The door:** a child with a collider on the `Interactable` layer and a `BasisInteractableButton`.
   Set `InteractRange` to about 3; the default 1 m is short on desktop. Assign the door and the two
   TextMeshPro labels in the inspector.
3. **The build:** build from a **saved** scene. Include all the platforms the SDK offers, so every
   player can see the door. In the Unity log, each platform should say "Cilbox scripts to do: 1"; a
   0 there means a dead door.
4. **Publish:** upload the `.BEE` next to your worlds.

Placing it on a server:

1. **Spawn the prop as Networked**, as admin, from the Library.
2. **Move it where you want it.**
3. **In the Instantiated tab, click "Save to server".** The server writes the prop into that world's
   `initialresources/` and loads it again on every restart.

Don't use "Load on Boot": it only loads the item in your own client.

Players press the door, see the destination address and confirm. The prompt always shows
`<name>:4296` even when SRV sends them to another port; that's expected. Basis's built-in "rift"
portals also work, but they disappear when the server restarts.

## 7. Optional: admin dashboard

Each world can get a [MarusansiBasisDashboard](https://github.com/nodokaha/MarusansiBasisDashboard),
which shows players and lets you load worlds and send announcements. Turning it on:

1. **Give each world an API key** in `.env` (`HUB_API_KEY=` and so on). Generate each with
   `openssl rand -hex 32`.
2. **Recreate the servers with the API on:** `./configure.sh && sudo docker compose up -d`. This
   restarts the worlds.
3. **Start the dashboards:** `sudo docker compose --profile dashboard up -d --build`.

The dashboards listen on the server's own `127.0.0.1:4000` and up, one per world. **Their admin
pages have no login and accept requests from any website. Never publish those ports.** Reach them
through an SSH tunnel, or over Tailscale with `tailscale serve --bg --http=4000 http://127.0.0.1:4000`
and an access rule limited to your own devices.

## 8. Running it

- **Admins:** `BASIS_FIRST_ADMIN` only applies on a world's first boot. To add an admin later:
  ```sh
  sudo docker compose stop && sudo ./add-admin.sh did:key:z6Mk... && sudo docker compose up -d
  ```
- **Backups:** everything worth keeping is `.env` plus `worlds/*/config` (admins, permissions),
  `worlds/*/storage` (player saves) and `worlds/*/initialresources` (props saved to the server).
  It's only kilobytes. Back it up daily (restic works well), and keep it on a disk that survives
  rebuilding the server.
- **Updating Basis:** change `BASIS_REF` in `.env`, then run
  `./fetch-basis.sh && sudo docker compose up -d --build`.
- **Replacing a world bundle:** both your CDN and the Basis client cache by URL. The client never
  checks for a newer file under the same name. Either upload under a new file name and update
  `worlds.conf`, or purge your CDN and accept that players who already loaded the world may keep the
  old copy.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Every world name and every portal lands in the hub | The client is older than 2026-10-27 and does no SRV lookup, or the SRV records are missing. Check with `dig`. |
| A world never becomes healthy | `sudo docker compose logs --tail=50 <slug>`. |
| `curl localhost:1066x/health` returns 404 or no answer | Run `configure.sh` again: the generated file sets `HealthCheckHost: "*"`. The default `localhost` doesn't work in containers. |
| "Save to server" fails | `initialresources` must be writable. The stock upstream compose file mounts it read-only. |
| Players can't connect at all | The UDP port isn't open in the firewall, or Cloudflare's proxy is on for the record. |

## How the SRV lookup behaves

- **When it happens:** with no port, or with the default 4296, the client looks up
  `_basis._udp.<name>` and connects to the record's target and port. Any other port connects
  directly, with no lookup.
- **Several records:** lower priority wins, and records with equal priority share players by weight.
  The client tries up to three targets.
- **No record:** the client connects to `<name>:4296`. With the wildcard A record, an unknown or
  failed name ends up in the hub.
- **Caching:** answers are cached for the record's TTL, at most 5 minutes.

## Credits

- [Basis](https://github.com/BasisVR/Basis) by BasisVR (MIT). This repository only builds its server.
- [MarusansiBasisDashboard](https://github.com/nodokaha/MarusansiBasisDashboard) by nodokaha.
- [basispm-build-awesome](https://github.com/nodokaha/basispm-build-awesome) by nodokaha, for the
  "build the server straight from upstream" idea.
- The prop-safe portal script was tested by the Splat project's Basis tooling.
