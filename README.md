# CouchDB on Railway

A three-node [Apache CouchDB](https://couchdb.apache.org/) 3.5 cluster behind a Caddy
load balancer, built for Railway.

Upstream strongly recommends a minimum of three nodes, and CouchDB's own deployment
guide puts a load balancer in front of them. This repo backs both roles:

| Path | Service | Notes |
|---|---|---|
| `Dockerfile` | `couchdb-node1` / `couchdb-node2` / `couchdb-node3` | `FROM couchdb:3.5` plus a boot-time wrapper |
| `proxy/Dockerfile` | `couchdb` | `FROM caddy:2-alpine`, round-robins the three nodes |

Both services select their Dockerfile with `RAILWAY_DOCKERFILE_PATH`, which Railway
templates carry (`dockerfilePath` is dropped).

## What the wrapper does

`entrypoint.sh` runs as root before the official image's entrypoint and re-enters it on
its final `exec`, so the vendor's chown, `[admins]` block and `setpriv` drop all still run.

- **Teaches Erlang distribution to speak IPv6.** Railway's private network routes IPv6
  between services, so a stock node never connects to a peer. The node gets
  `-proto_dist inet6_tcp` and an `inetrc` holding `{inet6,true}.`, passed through
  `ERL_INETRC` — the `-kernel inetrc "<path>"` form loses its quotes to the args_file
  parser and kills the VM at boot. `ERL_EPMD_ADDRESS` is deliberately left unset: epmd
  already listens on the IPv6 wildcard, and setting it to `::` collides with the `::1`
  epmd always adds for itself.
- **Caps the Erlang VM to the container's CPU quota.** The BEAM never reads cgroups and
  otherwise sizes its scheduler pool from the host's 48 cores against an 8-CPU quota.
- **Bootstraps the cluster** from the coordinator, in the background behind the `exec`
  so the health check is not held up: it waits for each peer's `/_up`, `PUT`s it into
  `_node/_local/_nodes`, and creates `_users`, `_replicator` and `_global_changes` only
  once every node is registered — created earlier they land with `n=1` and stay that way.
- **Derives the admin password hash deterministically.** CouchDB hashes a plaintext
  `[admins]` password with a random salt per node, and an `AuthSession` cookie is an
  HMAC over that salt — so behind a load balancer a cookie minted by one node is
  rejected by the next and `/_session` logins fail intermittently. The salt is derived
  from `COUCHDB_SECRET`, making the stored hash byte-identical everywhere; the plaintext
  never stays in the container's environment. A pre-hashed `COUCHDB_PASSWORD` is passed
  through untouched.
- **Renders the Railway configuration** into `default.d/20-railway.ini`, leaving
  `local.d/docker.ini` (where CouchDB writes runtime changes) outranking it.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `COUCHDB_USER` | — | required; cluster admin |
| `COUCHDB_PASSWORD` | — | required |
| `COUCHDB_SECRET` | — | `[chttpd_auth] secret`; must be identical on every node and stable, or sessions are invalidated |
| `COUCHDB_ERLANG_COOKIE` | — | identical on every node; the cluster's shared authentication token |
| `COUCHDB_UUID` | unset | 32 hex characters, **identical on every node** — replication checkpoint ids derive from it, so a per-node uuid resets every client's checkpoint whenever the balancer picks another node |
| `COUCHDB_CLUSTER_ROLE` | `single` | `coordinator`, `member` or `single` |
| `COUCHDB_CLUSTER_PEERS` | empty | coordinator only; space-separated peer hostnames |
| `COUCHDB_NODE_HOST` | `$RAILWAY_PRIVATE_DOMAIN` | this node's own private hostname |
| `COUCHDB_CLUSTER_N` | `3` | replicas per shard (forced to 1 when role is `single`) |
| `COUCHDB_CLUSTER_Q` | `2` | shards per database |
| `COUCHDB_LOG_LEVEL` | `warning` | |
| `COUCHDB_MAX_DOCUMENT_SIZE` | `8000000` | |
| `COUCHDB_PASSWORD_ITERATIONS` | `600000` | PBKDF2 iterations for the derived admin hash |
| `COUCHDB_CORS_ORIGINS` | unset | setting it enables CORS with credentials |
| `PORT` | `5984` | CouchDB's clustered port |

`require_valid_user` is on from the first boot, so there is no anonymous surface at all
except `/_up` (`require_valid_user_except_for_up`), which is what the Railway health
check and the load balancer's active probe use.

Setting `COUCHDB_CLUSTER_ROLE=single` on one node gives a working standalone CouchDB
from the same image, with the system databases created by CouchDB itself at `n=1`.

## Licence

The wrapper is Apache-2.0, matching Apache CouchDB.
