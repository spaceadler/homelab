# Apps, addresses and first logins

← [README](../README.md)

## The apps and their addresses

Core apps are always installed; everything else you pick in
`install.sh`'s menu, by genre. Addresses below use the default domain,
`homelab.local`. **Port** is the direct `http://<tailscale-ip>:<port>`
address. This list is generated from
[`containers/catalog.tsv`](../containers/catalog.tsv), which is also what the
installer reads.

### Core (always installed)

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Nginx | Reverse proxy: turns `<app>.<domain>` into the right port | - | 80 |
| Pi-hole | DNS for `<app>.<domain>`, plus ad blocking | `http://dns.homelab.local` | 8081 |
| Vaultwarden | Password manager | `https://<machine>.<tailnet>.ts.net` (`vault.homelab.local` redirects) | 4345 (this machine only) |
| adlerOS | Home screen with every app you installed, behind a password | `http://os.homelab.local` (and `http://homelab.local`) | 8686 |

### System

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Glance | Dashboard of widgets: feeds, calendar, containers | `http://home.homelab.local` | 8080 |
| Beszel | CPU, RAM, disk and container monitoring | `http://stats.homelab.local` | 8042 |
| Cup | Shows which container images have updates | `http://cup.homelab.local` | 9898 |

### Media

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Immich | Photos and videos, with phone backup | `http://gallery.homelab.local` | 2283 |
| Stremio | Streaming server for the Stremio apps | `http://watch.homelab.local` | 5543 |
| Navidrome | Music streaming (Subsonic apps work too) | `http://music.homelab.local` | 4533 |
| Audiobookshelf | Audiobooks, podcasts and e-books | `http://audiobook.homelab.local` | 13378 |

### Knowledge

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Globnotes | Markdown notes in storage/Notes (Obsidian-compatible) | `http://notes.homelab.local` | 8487 |
| Memos | Quick thoughts, Twitter-style | `http://memos.homelab.local` | 5230 |
| BookStack | Wiki: shelves, books, chapters, pages | `http://books.homelab.local` | 6875 |
| Karakeep | Bookmarks that archive the page itself | `http://bookmarks.homelab.local` | 3786 |
| Kiwix | Offline Wikipedia and other .zim archives | `http://wiki.homelab.local` | 8092 |
| 4get | Private metasearch engine | `http://search.homelab.local` | 9364 |

### Productivity

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Vikunja | Tasks, Kanban, Gantt | `http://todo.homelab.local` | 3456 |
| Super Productivity | Time blocking and planning, synced over WebDAV | `http://schedule.homelab.local` | 5432 |
| Radicale | Calendar and contacts (CalDAV/CardDAV) | `http://cal.homelab.local` | 5222 |
| Paperless-ngx | Scanned documents with OCR and search | `http://docs.homelab.local` | 8302 |
| CryptPad | End-to-end encrypted office suite (needs [HTTPS](tls.md)) | `http://workspace.homelab.local` | 7000 |
| Nomie | Life and mood tracking | `http://track.homelab.local` | 5005 |

### Life

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Dawarich | Location history (Google Timeline replacement) | `http://timeline.homelab.local` | 3001 |
| TREK | Trip planner | `http://trips.homelab.local` | 3210 |
| AirTrail | Flight log | `http://fly.homelab.local` | 9478 |
| Yamtrack | Movies, shows, anime, books and games you've watched/read/played | `http://catalogue.homelab.local` | 2143 |
| Ghostfolio | Investment portfolio and net worth | `http://assets.homelab.local` | 3333 |
| Maybe | Budgeting and expenses | `http://budget.homelab.local` | 13400 |

### Files

| App | What it's for | Address | Port |
| --- | --- | --- | --- |
| Syncthing | Keeps folders in sync across your devices | `http://sync.homelab.local` | 8384 |
| File Browser | Web file manager for the whole homelab folder | `http://storage.homelab.local` | 8090 |
| Gitea | Git server (SSH on port 222) | `http://git.homelab.local` | 3000 |
| qBittorrent | Torrent client, downloads to storage/Downloads | `http://qb.homelab.local` | 6420 |

A few apps answer on a second name or port as well: CryptPad's sandbox at
`workspacesb.`, Nomie's database at `trackdb.` (CouchDB, port 5984),
Stremio's streaming server on port 11470, and Gitea's SSH on port 222.

## First logins

Every app has its own accounts, on top of Tailscale. Most work the same way:
on your first visit, you create the first account and it becomes the admin.
Do that before you share your tailnet with anyone. The exceptions:

| App | First login |
| --- | --- |
| Vaultwarden | Sign-ups are off. Open `/admin` with `VAULTWARDEN_ADMIN_TOKEN` from its `.env`, invite your email, then register with it. Afterwards, empty the token in `.env` and `docker compose up -d` to close `/admin`. |
| Home screen | `OS_PASSWORD`, in `containers/core/os/.env` (the first run's summary shows it). Change it in Settings → Password; from then on, the changed one counts. |
| Immich, Navidrome | The first account is the admin. `install.sh` offers to make it for you (in a terminal), and with it the login or key adlerOS's Gallery and Music use. |
| Pi-hole | `PIHOLE_PASSWORD` |
| Paperless-ngx | `PAPERLESS_ADMIN_USER` / `PAPERLESS_ADMIN_PASSWORD` |
| File Browser | `admin` / `FILEBROWSER_ADMIN_PASSWORD` (reset to this on every start, so change it in `.env`) |
| Syncthing | `SYNCTHING_GUI_USER` / `SYNCTHING_GUI_PASSWORD` |
| Radicale | `RADICALE_USER` / `RADICALE_PASSWORD` |
| Super Productivity sync | `WEBDAV_USERNAME` / `WEBDAV_PASSWORD`, under Settings → Sync → WebDAV |
| Nomie's database | `admin` / `NOMIE_COUCHDB_PASSWORD`, under Settings → Storage → CouchDB |
| Dawarich | Creates an admin `demo@dawarich.app` on first start; its post-start hook replaces the public default password with `DAWARICH_ADMIN_PASSWORD`. Change the email once you're in. |
| BookStack | **Its built-in default: `admin@admin.com` / `password`. Change both right away.** |
| qBittorrent | User `admin` with a temporary password, which `install.sh` prints after the first start. |
| Gitea | Shows an installer on first visit; the defaults are fine. |
| Globnotes | No login by default, because being on your tailnet is the login. Set `GLOBNOTES_AUTH_TYPE=password` in its `.env` to add one. |

Each value lives in that app's `.env`, e.g.
`containers/productivity/paperless-ngx/.env`.

---

*powered by logic, coffee, and many sleepless nights*
