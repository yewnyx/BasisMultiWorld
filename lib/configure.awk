# Reads .env (first file) and worlds.conf (second file). If every line is valid, writes
# docker-compose.yml and worlds/<slug>/initialresources/world.xml, plus caddy/Caddyfile and each
# world's config/transports/websocket.xml when WEB_PLAYERS=yes; otherwise writes nothing.
# Called by configure.sh, which creates the folders first.

# Literal (non-regex) replace, so passwords and names never need escaping rules of their own.
function put(s, key, value,    out, i) {
    out = ""
    while ((i = index(s, key)) > 0) { out = out substr(s, 1, i - 1) value; s = substr(s, i + length(key)) }
    return out s
}
function xml(s) { return put(put(put(put(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;") }
# Single-quoted YAML; "$" is doubled so docker compose doesn't treat it as a variable.
function yaml(s) { return "'" put(put(s, "'", "''"), "$", "$$") "'" }
function fail(msg) { errors = errors "worlds.conf:" FNR ": " msg "\n" }
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
# Every name that reaches world i by name: the hub (first world) also answers on the zone itself
# and on the SRV target host.
function names(i, port,    p, s) {
    p = port == "" ? "" : ":" port
    s = slugs[i] "." zone p
    if (i == 1) s = zone p ", " s ", " host "." zone p
    return s
}
# Sets TrustedProxies in an existing websocket.xml (the server adds every other setting) or writes
# a minimal one. Written through a temp file: the server may own the old file.
function trusted(path,    content, line, have, tmp) {
    content = ""; have = 0
    while ((getline line < path) > 0) { content = content line "\n"; have = 1 }
    close(path)
    if (!have) content = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<BasisWebSocketTransportConfig>\n</BasisWebSocketTransportConfig>\n"
    if (content ~ /<TrustedProxies>[^<]*<\/TrustedProxies>/) sub(/<TrustedProxies>[^<]*<\/TrustedProxies>/, "<TrustedProxies>" proxyNet "</TrustedProxies>", content)
    else if (content ~ /<TrustedProxies[ \t]*\/>/) sub(/<TrustedProxies[ \t]*\/>/, "<TrustedProxies>" proxyNet "</TrustedProxies>", content)
    else sub(/<\/BasisWebSocketTransportConfig>/, "  <TrustedProxies>" proxyNet "</TrustedProxies>\n</BasisWebSocketTransportConfig>", content)
    tmp = path ".tmp"
    printf "%s", content > tmp
    close(tmp)
    if (system("mv -f '" tmp "' '" path "'") != 0) errors = errors path ": couldn't write\n"
}

FNR == NR {
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*(#|$)/) next
    eq = index(line, "=")
    if (eq < 2) next
    value = substr(line, eq + 1)
    # Same quoting as docker compose's .env: a value wrapped in matching quotes loses them. Single
    # quotes are how a password containing "$" stays literal for compose too.
    if (length(value) >= 2 && (value ~ /^'.*'$/ || value ~ /^".*"$/)) value = substr(value, 2, length(value) - 2)
    env[trim(substr(line, 1, eq - 1))] = value
    next
}

{
    line = $0
    sub(/\r$/, "", line)
    sub(/[ \t]*#.*$/, "", line)
    line = trim(line)
    if (line == "") next
    if (split(line, f, /[ \t]+/) < 4) { fail("expected: <slug> <port> <bundle> <display name>"); next }
    slug = f[1]; port = f[2]; bundle = f[3]
    name = line
    for (k = 1; k <= 3; k++) sub(/^[^ \t]+[ \t]+/, "", name)
    if (slug !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ || length(slug) > 40) { fail("slug '" slug "' must be lowercase letters, digits and dashes"); next }
    if (slug in seen) { fail("slug '" slug "' is listed twice"); next }
    if (port !~ /^[0-9]+$/ || port + 0 < 1024 || port + 0 > 65535) { fail("port '" port "' must be a number from 1024 to 65535"); next }
    if (port in ports) { fail("port " port " is already used by '" ports[port] "'"); next }
    if (bundle !~ /^https:\/\// && env["CDN_BASE"] == "") { fail("bundle '" bundle "' is relative, so CDN_BASE must be set in .env"); next }
    seen[slug] = 1; ports[port] = slug
    count++
    slugs[count] = slug; portOf[count] = port; nameOf[count] = name
    urlOf[count] = bundle ~ /^https:\/\// ? bundle : env["CDN_BASE"] "/" bundle
    var = toupper(slug); gsub(/-/, "_", var); varOf[count] = var
}

END {
    if (count == 0 && errors == "") errors = "worlds.conf: no worlds listed\n"
    if (env["UNLOCK_PASSWORD"] == "") {
        for (i = 1; i <= count; i++) if (env["UNLOCK_PASSWORD_" varOf[i]] == "") { errors = errors ".env: UNLOCK_PASSWORD (or UNLOCK_PASSWORD_" varOf[i] ") is empty\n"; break }
    }
    web = env["WEB_PLAYERS"] == "yes"
    if (env["WEB_PLAYERS"] != "" && env["WEB_PLAYERS"] != "yes" && env["WEB_PLAYERS"] != "no") errors = errors ".env: WEB_PLAYERS must be yes or no\n"
    zone = tolower(env["DNS_ZONE"]); sub(/\.$/, "", zone)
    host = env["DNS_HOST"] == "" ? "vm1" : tolower(env["DNS_HOST"])
    proxyNet = env["PROXY_NET"] == "" ? "172.30.42.0/24" : env["PROXY_NET"]
    webClient = env["WEB_CLIENT_URL"]
    if (web) {
        if (zone !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/) errors = errors ".env: WEB_PLAYERS=yes needs DNS_ZONE set to a domain name (certificates are issued for it)\n"
        if (host !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) errors = errors ".env: DNS_HOST must be a single DNS label\n"
        if (proxyNet !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) errors = errors ".env: PROXY_NET must be an IPv4 subnet like 172.30.42.0/24\n"
        if (webClient != "" && (webClient !~ /^https:\/\/[^ \t?#{}]+$/)) errors = errors ".env: WEB_CLIENT_URL must be an https:// URL without a query\n"
        for (i = 1; i <= count; i++) if (portOf[i] == 80 || portOf[i] == 443) errors = errors "worlds.conf: port " portOf[i] " is needed by Caddy\n"
    }
    if (errors != "") { printf "%s", errors > "/dev/stderr"; exit 1 }
    if (portOf[1] != 4296) printf "note: the first world (%s) is the hub but isn't on port 4296; clients that miss the SRV record connect to <name>:4296.\n", slugs[1] > "/dev/stderr"

    out = "docker-compose.yml"
    print "# Generated by configure.sh from worlds.conf and .env. Edit those and re-run ./configure.sh;" > out
    print "# changes made here are overwritten." > out
    print "" > out
    print "x-basis-server: &basis-server" > out
    print "  # Every world builds the same image; the build cache makes the rest instant." > out
    print "  build:" > out
    print "    context: \"./basis/Basis Server\"" > out
    print "    dockerfile: Docker/Dockerfile" > out
    print "  image: basis-server:local" > out
    print "  restart: unless-stopped" > out
    print "  healthcheck:" > out
    print "    test: [\"CMD\", \"curl\", \"-fsS\", \"http://127.0.0.1:10666/health\"]" > out
    print "    interval: 30s" > out
    print "    timeout: 5s" > out
    print "    retries: 3" > out
    print "    start_period: 30s" > out
    print "  logging: &logging" > out
    print "    driver: json-file" > out
    print "    options:" > out
    print "      max-size: \"20m\"" > out
    print "      max-file: \"5\"" > out
    print "" > out
    print "x-basis-env: &basis-env" > out
    print "  HealthCheckPort: 10666" > out
    print "  # The default \"localhost\" answers 404 to 127.0.0.1 inside a container and can't be reached" > out
    print "  # through a published port. The ports below still publish it on the host's loopback only." > out
    print "  HealthCheckHost: \"*\"" > out
    print "  EnableStatistics: true" > out
    print "  EnableConsole: false" > out
    print "  # Seeded as admins on each world's first boot only; see add-admin.sh for later." > out
    print "  BasisFirstAdmin: ${BASIS_FIRST_ADMIN:-}" > out
    print "  # The REST API is used only by the optional dashboards; an empty ApiKey keeps it off." > out
    print "  ApiEnabled: true" > out
    if (web) {
        print "  # UDP for native clients, plus WebSocket on the same port number over TCP. That TCP port isn't" > out
        print "  # published: web players reach it through the caddy service." > out
        print "  NetworkStackId: litenetlib,websocket" > out
    }
    print "" > out
    print "# Optional dashboard per world (docker compose --profile dashboard up -d). Its admin pages have" > out
    print "# no login and accept any origin: keep the ports on loopback, never publish them." > out
    print "x-dashboard: &dashboard" > out
    print "  build:" > out
    print "    context: https://github.com/nodokaha/MarusansiBasisDashboard.git#${DASHBOARD_REF:-cb23088b1f38d0c9ff6223d2ec9760652a5eed94}" > out
    print "  image: basis-dashboard:local" > out
    print "  restart: unless-stopped" > out
    print "  profiles: [dashboard]" > out
    print "  logging: *logging" > out
    print "" > out
    print "services:" > out
    for (i = 1; i <= count; i++) {
        s = slugs[i]; v = varOf[i]
        print "  " s ":" > out
        print "    <<: *basis-server" > out
        print "    container_name: basis-" s > out
        print "    environment:" > out
        print "      <<: *basis-env" > out
        print "      SetPort: " portOf[i] > out
        print "      ServerName: " yaml(nameOf[i]) > out
        print "      ServerMotd: ${" v "_MOTD:-}" > out
        print "      Password: ${" v "_PASSWORD:-}" > out
        print "      PeerLimit: ${" v "_PEER_LIMIT:-64}" > out
        print "      ApiKey: ${" v "_API_KEY:-}" > out
        print "    ports:" > out
        print "      - \"" portOf[i] ":" portOf[i] "/udp\"" > out
        print "      - \"127.0.0.1:" (10665 + i) ":10666/tcp\"    # health" > out
        print "      - \"127.0.0.1:" (3999 + i) ":4000/tcp\"     # dashboard (profile \"dashboard\")" > out
        print "    volumes:" > out
        print "      - ./worlds/" s "/initialresources:/app/initialresources" > out
        print "      - ./worlds/" s "/config:/app/config" > out
        print "      - ./worlds/" s "/storage:/app/storage" > out
        print "      # What admins add under Admin > Default library; unmounted, it's lost when the container is recreated." > out
        print "      - ./worlds/" s "/defaultlibrary:/app/defaultlibrary" > out
        print "" > out
    }
    if (web) {
        print "  # TLS front for web players: routes each world name to its world's WebSocket listener, the way" > out
        print "  # the SRV records do for UDP. Certificates are kept in caddy/data. See caddy/Caddyfile." > out
        print "  caddy:" > out
        print "    image: caddy:2.11.7-alpine" > out
        print "    container_name: basis-caddy" > out
        print "    restart: unless-stopped" > out
        print "    ports:" > out
        print "      - \"80:80/tcp\"" > out
        print "      - \"443:443/tcp\"" > out
        print "      - \"4296:4296/tcp\"" > out
        for (i = 1; i <= count; i++) if (portOf[i] != 4296) print "      - \"" portOf[i] ":" portOf[i] "/tcp\"" > out
        print "    volumes:" > out
        print "      - ./caddy:/etc/caddy:ro" > out
        print "      - ./caddy/data:/data" > out
        print "      - ./caddy/config:/config" > out
        print "    logging: *logging" > out
        print "" > out
    }
    for (i = 1; i <= count; i++) {
        s = slugs[i]; v = varOf[i]
        print "  " s "-dashboard:" > out
        print "    <<: *dashboard" > out
        print "    container_name: basis-" s "-dashboard" > out
        print "    network_mode: \"service:" s "\"" > out
        print "    depends_on:" > out
        print "      " s ":" > out
        print "        condition: service_healthy" > out
        print "    environment:" > out
        print "      PORT: 4000" > out
        print "      HEALTH_PORT: 10666" > out
        print "      API_URL_BASE: http://localhost:10667" > out
        print "      API_BEARER_TOKEN: ${" v "_API_KEY:-}" > out
        if (i < count) print "" > out
    }
    if (web) {
        print "" > out
        print "networks:" > out
        print "  default:" > out
        print "    ipam:" > out
        print "      config:" > out
        print "        # Pinned: every world trusts X-Forwarded-For only from this network (PROXY_NET in .env)." > out
        print "        - subnet: " proxyNet > out
    }
    close(out)

    for (i = 1; i <= count; i++) {
        pw = env["UNLOCK_PASSWORD_" varOf[i]]
        if (pw == "") pw = env["UNLOCK_PASSWORD"]
        x = "worlds/" slugs[i] "/initialresources/world.xml"
        print "<?xml version=\"1.0\" encoding=\"utf-8\"?>" > x
        print "<BasisLoadableConfiguration>" > x
        print "  <Mode>1</Mode>" > x
        print "  <LoadedNetID>" xml(slugs[i]) "</LoadedNetID>" > x
        print "  <UnlockPassword>" xml(pw) "</UnlockPassword>" > x
        print "  <CombinedURL>" xml(urlOf[i]) "</CombinedURL>" > x
        print "  <QuaternionW>1</QuaternionW>" > x
        print "  <ScaleX>1</ScaleX>" > x
        print "  <ScaleY>1</ScaleY>" > x
        print "  <ScaleZ>1</ScaleZ>" > x
        print "  <Persist>true</Persist>" > x
        print "</BasisLoadableConfiguration>" > x
        close(x)
        printf "world %-12s UDP %s  %s\n", slugs[i], portOf[i], urlOf[i]
    }

    if (web) {
        c = "caddy/Caddyfile"
        print "# Generated by configure.sh from worlds.conf and .env; changes made here are overwritten." > c
        print "#" > c
        print "# TLS front for web players. A browser can only open wss:// from an https:// page and can't look" > c
        print "# up SRV records, so a web client turns a plain world name into wss://<name>:4296/. On 443 and" > c
        print "# 4296 each name goes to its own world, the way the SRV records do for UDP; on the other world" > c
        print "# ports the port decides, as for UDP. Certificates come from Let's Encrypt for exactly these" > c
        print "# names, so TCP 80 and 443 must be open." > c
        print "{" > c
        print "\tservers {" > c
        print "\t\t# No HTTP/3: UDP 443 isn't open." > c
        print "\t\tprotocols h1 h2" > c
        print "\t}" > c
        print "}" > c
        print "" > c
        print "# Arguments: the world's listener, and the address the web client should join." > c
        print "(world) {" > c
        if (webClient != "") {
            print "\t# A browser opening the address lands in the web client, set to join this world." > c
            print "\t@page header Accept *text/html*" > c
            print "\tredir @page " webClient "?connection={args[1]} 302" > c
        }
        print "\treverse_proxy {args[0]}" > c
        print "}" > c
        for (i = 1; i <= count; i++) {
            print "" > c
            print names(i, "") ", " names(i, "4296") " {" > c
            print "\timport world " slugs[i] ":" portOf[i] " {host}" > c
            print "}" > c
        }
        for (i = 1; i <= count; i++) {
            if (portOf[i] == 4296) continue
            all = ""
            for (j = 1; j <= count; j++) all = all (all == "" ? "" : ", ") names(j, portOf[i])
            print "" > c
            print all " {" > c
            print "\timport world " slugs[i] ":" portOf[i] " {host}:" portOf[i] > c
            print "}" > c
        }
        close(c)
        for (i = 1; i <= count; i++) trusted("worlds/" slugs[i] "/config/transports/websocket.xml")
        if (errors != "") { printf "%s", errors > "/dev/stderr"; exit 1 }
        print "wrote caddy/Caddyfile (web players on: open TCP 80, 443, 4296 and the world ports)"
    }
    print "wrote docker-compose.yml"
}
