# Adding an app

← [README](../README.md)

The contract every app folder follows.

## Inside an app folder

Every app follows the same shape. `containers/media/immich/`, for
example:

```text
immich/
├── docker-compose.yml   # the recipe: images, ports, mounts, settings
├── .env.example         # its settings, with placeholders where secrets go
├── nginx.conf.template  # its route: server_name gallery.* → ${TS_IP}:2283
├── .env                 # (generated) globals + this app's generated secrets, chmod 600
└── postgres/            # (generated) the app's own data
```

Some apps also have a `*.template` (a config file that needs your domain,
rendered to the same name without `.template`), or a hook that
`install.sh` runs at the right moment. `configure.sh` runs on every install
(e.g. Syncthing pre-seeds its GUI login), `pre-start.sh` can hold an app
back (Kiwix waits until you have a `.zim` file), and `post-start.sh` runs
once it's up (Vaultwarden sets up `tailscale serve`).

You can work in any app folder with plain Docker Compose: every `.env`
carries the global settings too, so `docker compose up -d` there just
works.

## Steps

1. **Add a row** to `containers/catalog.tsv`: genre, folder name,
   subdomain, port, icon, display name, one-line description.
2. **Create `containers/<genre>/<app>/` with:**
   - `docker-compose.yml`. Use `${PUID}`, `${PGID}`, `${TZ}`,
     `${DOMAIN}`, `${URL_SCHEME}`, `${STORAGE_DIR}`, `${HOMELAB_DIR}` and
     `${TS_IP}` from the globals. Write `${VAR:?run ./install.sh}` for
     anything required, so a missing value fails loudly instead of
     becoming empty. The rule for storage: anything you'd lose goes in a
     `./folder`, which backups copy and you can move to a new machine.
     Things the app rebuilds by itself (caches, Redis job queues, search
     indexes, downloaded models) go in Docker volumes, so they don't
     bloat the backups.
   - `.env.example`. Secrets are placeholders that `install.sh` fills in
     once: `__PASS__` (32 letters and digits), `__HEX32__`, `__HEX64__`,
     `__HEX128__`, and `__B64_32__`.
   - `nginx.conf.template`, a `server` block with `include
     snippets/listen.conf;`, `server_name <subdomain>.*;` and a `location /`
     that proxies to `${TS_IP}:<port>` (filled in with this machine's
     Tailscale IP) with `include snippets/proxy.conf;`. Copy any app's.
   - **Optionally**, `*.template` files and `configure.sh` /
     `pre-start.sh` / `post-start.sh` hooks. Hooks run from the app folder
     with its `.env` loaded, plus `$DOCKER`, `$HOMELAB_APPS`,
     `$HOMELAB_CATALOG`, `$HOMELAB_SITES` and a `set_env KEY VALUE`
     helper. `pre-start.sh` exiting with 10 means "don't start this yet".
3. **If the app ships extra static config,** whitelist it in
   `.gitignore`. Everything else in an app folder is ignored by design.
4. **Test it:** `./install.sh --apps "<everything you run> <app>"`.

---

*powered by logic, coffee, and many sleepless nights*
