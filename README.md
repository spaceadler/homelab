# A Sovereign Homelab

> One script and ~30 apps that turn a Raspberry Pi (or any 64-bit Debian/Ubuntu box) into your own cloud: reachable from your devices anywhere, by nobody else.

![Containerization](https://img.shields.io/badge/Containerization-Docker-blue)
![Network](https://img.shields.io/badge/Network-Tailscale-black)
![Architecture](https://img.shields.io/badge/Architecture-ARM64%20%7C%20x86--64-orange)

New to self-hosting? Read the **[TL;DR](abstract.md)**. Installing for the first time? Follow the **[How-to-Use Guide](how-to-use.md)**.

## Quick Start

```bash
git clone https://github.com/spaceadler/homelab ~/homelab
cd ~/homelab && ./install.sh
```

```mermaid
flowchart LR
    run(["./install.sh"]) --> host["host: Docker, Tailscale,<br/>ufw + DOCKER-USER lockout"]
    host --> pick["pick apps<br/>(catalog.tsv)"]
    pick --> secrets["generate every secret<br/>(once, kept forever)"]
    secrets --> routes["render .env, nginx routes,<br/>Pi-hole wildcard"]
    routes --> up["start the apps"]
    up --> os["adlerOS home screen<br/>http://homelab.local"]
```

Run it again anytime: it's how you add apps, apply settings and update. It never stops or deletes anything.

## How It Works

```mermaid
graph LR
    classDef client fill:#4A90E2,stroke:#2E5C8A,stroke-width:2px,color:#fff;
    classDef vpn fill:#00004B,stroke:#00004B,stroke-width:2px,color:#fff;
    classDef dns fill:#2C3E50,stroke:#34495E,stroke-width:2px,color:#fff;
    classDef proxy fill:#9B59B6,stroke:#6C3483,stroke-width:2px,color:#fff;
    classDef service fill:#2C3E50,stroke:#7F8C8D,stroke-width:2px,color:#fff;
    classDef blocked fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,color:#fff;

    User["📱 Your devices<br/>(phone, laptop)"]:::client
    VPN["🔒 Tailscale<br/>(WireGuard)"]:::vpn
    LAN["🏠 Home Wi-Fi / LAN"]:::blocked

    subgraph Host [" ⚡ Homelab host (100.x.y.z) "]
        PiHole["Pi-hole :53<br/>*.homelab.local → 100.x.y.z"]:::dns
        Nginx["Nginx :80<br/>gallery.* → :2283<br/>music.* → :4533 …"]:::proxy
        Serve["tailscale serve :443"]:::proxy
        Apps["Apps<br/>(one Docker stack each)"]:::service
        Vault["Vaultwarden<br/>127.0.0.1:4345"]:::service
    end

    User ==> VPN
    VPN -.->|"1. DNS"| PiHole
    VPN ==>|"2. http://gallery.homelab.local"| Nginx
    Nginx -->|"3. 100.x.y.z:port"| Apps
    VPN ==>|"https://machine.tailnet.ts.net"| Serve --> Vault
    LAN -.->|"✗ dropped by the firewall"| Host
```

1. **Name → machine:** Pi-hole's one wildcard record sends every `*.homelab.local` to this machine's Tailscale IP.
2. **Machine → nginx:** port 80, inside the WireGuard tunnel.
3. **nginx → app:** matched by name, forwarded to the app's port. `http://<tailscale-ip>:<port>` works too.

**Vaultwarden** is the exception: it gets real HTTPS through `tailscale serve`. **The router forwards no ports**, and the home LAN is firewalled out.

## The Apps

```mermaid
flowchart TB
    core["Core: Nginx · Pi-hole · Vaultwarden · adlerOS"]
    core --- sys["System<br/>Glance · Beszel · Cup"]
    core --- media["Media<br/>Immich · Stremio · Navidrome · Audiobookshelf"]
    core --- know["Knowledge<br/>Globnotes · Memos · BookStack · Karakeep · Kiwix · 4get"]
    core --- prod["Productivity<br/>Vikunja · Super Productivity · Radicale · Paperless-ngx · CryptPad · Nomie"]
    core --- life["Life<br/>Dawarich · TREK · AirTrail · Yamtrack · Ghostfolio · Maybe"]
    core --- files["Files<br/>Syncthing · File Browser · Gitea · qBittorrent"]
```

Core is always installed; the rest you pick by genre. Every address, port and first login: **[docs/apps.md](docs/apps.md)**. The source of truth is [`containers/catalog.tsv`](containers/catalog.tsv).

## The Home Screen

`http://homelab.local` opens **[adlerOS](https://github.com/spaceadler/adleros)**, styled after umbrelOS: app pages per collection, widgets, a dock, search, Files, Live Usage, Settings and an App Store, all keyboard-drivable. It's **its own repo**: `install.sh` only fetches it into `containers/core/os/adleros/` and runs its installer. Skip it with `--no-adleros`.

```mermaid
flowchart LR
    os["adlerOS<br/>(no Docker, no root)"] -->|"writes a request"| q[("queue/")]
    q --> helper["helper (systemd)<br/>runs as you"]
    helper -->|"only actions in<br/>actions.json"| machine["apps · backup · update"]
```

A compromised home screen can only *ask* for one of those listed actions.

## Layout

```text
~/homelab/
├── install.sh          # set up, add apps, apply changes: run it anytime
├── homelab.env         # (generated) domain, timezone, storage path, app list
├── containers/         # catalog.tsv + one folder per app, by genre
├── storage/            # your files as plain folders: no hidden volumes
├── backup/             # (generated) dated copies from scripts/backup.sh
├── dev/ · mailbox/     # your repos · your unsorted-files inbox
├── scripts/            # backup.sh, renew-certs.sh, agent/actions.json
└── docs/
```

## Documentation

| Doc | What's in it |
|---|---|
| [docs/apps.md](docs/apps.md) | Every app's address and port, and how to log in the first time |
| [docs/operating.md](docs/operating.md) | Full directory tree, everyday commands, `install.sh` flags, Settings, the helper, the App Store |
| [docs/security.md](docs/security.md) | The security model and what to watch out for |
| [docs/tls.md](docs/tls.md) | HTTPS: Vaultwarden by default, every app with your own domain |
| [docs/backup.md](docs/backup.md) | 3-2-1 backup with Syncthing and an encrypted cloud; recovering on a new machine |
| [docs/adding-an-app.md](docs/adding-an-app.md) | The app-folder contract |
| [docs/hardware.md](docs/hardware.md) | The reference Raspberry Pi 4 build |
| [CODEMAP.md](CODEMAP.md) | Files, hub functions and the call graph, generated from the code |

<details>
  <summary>Screenshots</summary>

### Tailscale
![Tailscale](screenshots/Tailscale.png)

### Pi-hole
![Pi-hole](screenshots/Pi-hole.png)

### Glance
![Glance](screenshots/Glance.png)

### Beszel
![Beszel](screenshots/Beszel.png)

### Cup
![Cup](screenshots/Cup.png)

### Immich
![Immich](screenshots/Immich.png)

### Navidrome
![Navidrome](screenshots/Navidrome.png)

### Stremio
![Stremio](screenshots/Stremio.png)

### Memos
![Memos](screenshots/Memos.png)

### Vikunja
![Vikunja](screenshots/Vikunja.png)

### Ghostfolio
![Ghostfolio](screenshots/Ghostfolio.png)

### Maybe
![Maybe](screenshots/Maybe.png)

### File Browser
![File_Browser](screenshots/File_Browser.png)

### Syncthing
![syncthing](screenshots/syncthing.png)

### qBittorrent
![qB](screenshots/qB.png)

</details>

## Credits

- **Home screen:** [adlerOS](https://github.com/spaceadler/adleros), which credits its design (after umbrelOS, reimplemented, no umbrelOS code or artwork), its font (Inter, SIL OFL) and its wallpapers (NASA, public domain).
- **App icons:** fetched at runtime from [dashboard-icons](https://github.com/homarr-labs/dashboard-icons). Each icon belongs to its app's project.

---
*powered by logic, coffee, and many sleepless nights*
