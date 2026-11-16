# Operating the homelab

← [README](../README.md)

## Directory structure

The repository *is* the homelab: clone it to `~/homelab` and everything
lives inside. Files marked **(generated)** are written by `install.sh` or by
the apps themselves, are specific to your machine, and are never committed;
`.gitignore` keeps them out.

```text
~/homelab/
├── install.sh              # set up, add apps, apply changes: run it anytime
├── homelab.env.example     # template for…
├── homelab.env             # (generated) domain, timezone, storage path, your app list
├── containers/
│   ├── catalog.tsv         # every app: genre, address, port, description
│   ├── core/               # nginx · pihole · vaultwarden · os (the home screen:
│   │                       #   (generated) all written by adlerOS's own installer,
│   │                       #   with adlerOS itself in core/os/adleros)
│   ├── system/             # glance · beszel · cup
│   ├── media/              # immich · stremio · navidrome · audiobookshelf
│   ├── knowledge/          # globnotes · memos · bookstack ·
│   │                       #   karakeep · kiwix · 4get
│   ├── productivity/       # vikunja · super-productivity · radicale ·
│   │                       #   paperless-ngx · cryptpad · nomie
│   ├── life/               # dawarich · trek · airtrail · yamtrack ·
│   │                       #   ghostfolio · maybe
│   ├── files/              # syncthing · filebrowser · gitea · qbittorrent
│   └── extras/             # (generated) apps you imported in the App Store
├── storage/                # your files, as plain folders (or STORAGE_DIR elsewhere)
│   ├── Documents/          #   Paperless-ngx archive
│   ├── Downloads/          #   qBittorrent
│   ├── Files/              #   general files
│   ├── Gallery/            #   Immich: originals, thumbnails, encoded video
│   ├── Inbox/              #   drop scans here; Paperless-ngx imports them
│   ├── Media/              #   Music, Audiobooks, Podcasts, Books, Kiwix, …
│   └── Notes/              #   Markdown notes: Globnotes, Obsidian, any editor
├── backup/containers/      # (generated) dated copies from scripts/backup.sh
├── dev/                    # your own git repositories (synced with Syncthing)
├── mailbox/                # inbox for files you haven't sorted yet
├── scripts/
│   ├── backup.sh           # Layer 1 backup (see below)
│   ├── renew-certs.sh      # only for HTTPS with your own domain
│   └── agent/
│       └── actions.json    # this homelab's actions for adlerOS's helper: apply
│                           #   settings, back up, update
└── docs/
    └── tls.md              # HTTPS: Vaultwarden by default, every app optionally
```

Your files stay plain files: no Docker volumes hide your photos or music.
If everything else breaks, plug the disk into any computer and copy
`storage/` off it.

## Operating it

Everyday commands, all run from `~/homelab`:

| To… | Run |
| --- | --- |
| Add or remove apps | the App Store's **Install** and **Delete**, or `./install.sh` and tick or untick in the menu |
| Apply a change to `homelab.env` (domain, timezone, storage path) | `./install.sh` |
| Update this repo | `git pull && ./install.sh` |
| See what's running | the App Store in adlerOS, Beszel, or `docker ps` |
| Start, stop, restart or delete an app | the App Store, or `docker compose` in its folder |
| Read an app's logs | `cd containers/<genre>/<app> && docker compose logs -f` |
| Restart an app | `cd containers/<genre>/<app> && docker compose restart` |
| Change one app's settings | edit its `.env`, then `docker compose up -d` in its folder |
| Stop an app | `cd containers/<genre>/<app> && docker compose down` (its data stays) |
| Update one app | `cd containers/<genre>/<app> && docker compose pull && docker compose up -d` |
| Update every running app | see below |
| Find a password | `grep -h PASSWORD containers/*/*/.env` |

To update every running app in one go:

```bash
for d in containers/*/*/; do
  (cd "$d" && [ -n "$(docker compose ps -q 2>/dev/null)" ] && docker compose pull -q && docker compose up -d)
done
docker image prune -f   # clear out the old image versions
```

Cup (`cup.homelab.local`) shows which apps have updates waiting, so you can
read the changelogs first.

**How `install.sh` behaves:**

- **It doesn't prompt** with `--apps "immich memos …"` or `--yes`.
  `--apps` sets the *whole* list, so name everything you want.
- **Secrets are made once and kept.** Re-running never changes a password.
  If a newer version of the repo adds a setting to an app's `.env.example`,
  it's appended to your `.env`.
- **It never stops or deletes anything.** Unticking an app removes its
  route and dashboard entry; `docker compose down` in its folder stops it.
- **`--no-host`** skips installing packages and the firewall, for a machine
  that's already set up. **`--no-start`** writes the config without
  starting anything.
- **`--no-adleros`** sets the homelab up without adlerOS (and without its
  helper): `ADLEROS=off` in `homelab.env`, which later runs keep. The bare
  domain then goes to Glance, if you have it. `ADLEROS=on` and
  `./install.sh` adds adlerOS back.
- **adlerOS comes from GitHub,** and from `ADLEROS_MIRRORS` (the Gitea it's
  pushed to, by default) when GitHub can't be reached; `ADLEROS_REPO` and
  `ADLEROS_REF` pick another copy or version.

### Settings and the helper

adlerOS's **Settings** has the homelab's own rows too:

- **Homelab:** domain and timezone. Changing them shows an **Apply** bar;
  applying writes `homelab.env` and re-runs `install.sh` for you, with its
  output shown live. Also shown: HTTPS, your Tailscale address and the
  storage folder.
- **System:** **Back up now** (runs `scripts/backup.sh`, and shows the last
  backup's date) and **Update homelab** (`git pull` + `install.sh`, which
  also updates adlerOS, then a restart of adlerOS so it runs the new
  version), next to adlerOS's own: admin mode, restart, shut down, and the
  **Terminal** (a shell in a window: off unless `ADLEROS_TERMINAL=on` in
  `homelab.env` and `./install.sh` re-run, and only there in admin mode).

**How the home screen changes things without being powerful.** adlerOS has
no Docker or root access. For anything beyond its own settings it writes a
request file into `containers/core/os/data/agent/queue/`, and that's all it
can do. adlerOS's installer sets up a small systemd service, the **helper**
(`homelab-agent.path` and `.service`), which starts when a request appears.
It runs adlerOS's `agent/agent.py` as your user, never as root, and does
only what's listed in two files: adlerOS's
`containers/core/os/adleros/agent/actions.json` (apps, restart, shut down)
and this homelab's `scripts/agent/actions.json` (apply settings, back up,
update).

- Each action has a fixed list of steps.
- Each parameter it accepts has a pattern the value must match. Anything
  else is refused.
- Commands run without a shell, so a value can't sneak in a second
  command.
- The root-only steps go through `sudo` to root-owned copies of fixed
  scripts: `/usr/local/libexec/homelab/backup` and
  `/usr/local/libexec/adleros/power`. The rule in `/etc/sudoers.d/homelab`
  allows exactly those three commands (backup, reboot, power off) and nothing
  else.

Even a compromised home screen could only ask for one of those actions.

- **What it's doing:** `journalctl -u homelab-agent`.
- **Not set up:** run `./install.sh` without `--no-host`. With `--no-host`,
  Settings can still change your name, wallpaper and password, but its
  buttons wait for a helper that isn't there.

**Adding a setting:** an action in `scripts/agent/actions.json` (if it needs
to change the machine) and a row in adlerOS's settings catalog; see adlerOS's
[customizing](https://github.com/spaceadler/adleros/blob/main/docs/customizing.md#settings-rows).

### The App Store

adlerOS's **App Store** works on this homelab's catalog. An app is *every*
compose file in its folder and in the folders right inside it, so an app made
of several containers (Immich, Maybe) or several compose files (Beszel and
its agent) starts and stops as one, each file from its own folder, exactly as
if you'd typed `docker compose` there. Here:

- **Install** (under **Not installed**: the catalog apps you haven't picked)
  adds the app to `APPS` in `homelab.env` and re-runs `install.sh`, which sets
  it up (passwords, nginx route, dashboard entry) and starts it, as if you'd
  ticked it in the menu.
- **Delete** stops and removes its containers, takes it out of `APPS`, and
  re-runs `install.sh`, so its address and dashboard entry go too. Its data
  and compose files stay, so **Install** brings it back exactly as it was.
  It needs admin mode; core apps (Pi-hole, Vaultwarden) can't be deleted, and
  stopping them needs admin mode too.
- **Start** runs the app's `pre-start.sh` first, like `install.sh` does (Kiwix
  waits for an archive, Vaultwarden for a MagicDNS name).
- adlerOS itself and nginx aren't on the list, since stopping either would
  take the App Store down with it.

**Importing apps you already run** (*Import apps…*) works as in
[adlerOS's guide](https://github.com/spaceadler/adleros/blob/main/docs/guide.md#importing-apps-adleros-didnt-find).
Imported apps are recorded in `containers/extras/<app>/app.json`, pointing at
your compose file; a known app (Jellyfin, say) goes in its collection, the
rest in **Extras**. Their data lives wherever their compose files keep it, so
`scripts/backup.sh` doesn't copy it.

---

*powered by logic, coffee, and many sleepless nights*
