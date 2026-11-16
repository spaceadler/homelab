# Security model

← [README](../README.md)

The goal: the homelab must not be reachable from the internet or from your
home network, only from devices on your tailnet.

- **The router forwards no ports.** Tailscale makes outbound connections
  and punches through NAT, so there's nothing to forward.
- **The firewall blocks the LAN.** `install.sh` sets up two things. First,
  ufw denies every incoming connection on the physical network cards
  (`eth0`, `wlan0`, …), which covers services running on the host.
  Second, ports published by Docker containers skip ufw's rules entirely
  (Docker routes them through its own forwarding chain), so it adds a rule
  to Docker's `DOCKER-USER` chain that drops new connections from those
  same cards. Together they mean: from the LAN, nothing answers; over
  `tailscale0`, everything does. Re-run `install.sh` after adding a
  network card.
- **Your tailnet is the key.** With Tailscale's default policy, every
  member of your tailnet can reach every port on this machine. If you
  invite friends or family, write an access policy in the
  [Tailscale admin console](https://login.tailscale.com/admin/acls) that
  grants each person only the apps they use. Also turn on device approval
  and Tailnet Lock, so a stolen login can't add a new device.
- **Secrets are unique to each install.** Every password and key is
  generated on your machine by `openssl`. They live in each app's `.env`
  (`chmod 600`) and are never committed. Where an upstream compose file
  ships a public default (Dawarich's `SECRET_KEY_BASE=CHANGE_ME`, Maybe's
  sample key), this repo makes the value required and generates it.
- **The home screen can't run anything.** Settings and the App Store only
  queue requests; the helper on the host runs nothing but the actions
  listed in `scripts/agent/actions.json`, as your user (see
  [Settings and the helper](operating.md#settings-and-the-helper)). The App Store's
  actions take one of your apps by name; import only takes compose files
  under your home folder, never one from the home screen's own data folder,
  where it could have written one. So the most a compromised home screen
  could do is stop or delete your apps (their data stays), install ones
  from the catalog, or start a compose file you already have. In the
  browser, restart, shut down, delete and stopping core apps also need
  admin mode, which takes your password to turn on.
- **Vaultwarden is HTTPS-only.** It's bound to `127.0.0.1`, reachable only
  through `tailscale serve` (or nginx in HTTPS mode), and sign-ups are off.
  It's the one app nginx reaches on loopback; the rest it reaches at the
  Tailscale IP, as you would.

Things to know, so nothing surprises you:

- **Some containers can control Docker.** Glance, Cup and the Beszel agent
  mount `/var/run/docker.sock` to show your containers. Docker's API has no
  read-only mode, so each of them could control Docker if it were
  compromised. Leave out an app you don't need.
- **Two apps see the whole homelab folder.** Syncthing and File Browser
  see all of `~/homelab`, including every `.env`. That's what lets you
  sync or browse anything, but it also means a Syncthing share of the
  repo's root sends your secrets to that device. Share subfolders (like
  `storage/`) instead, or add `**/.env` to `.stignore`.
- **`scripts/backup.sh` copies secrets too.** Its copies include every
  `.env`, so treat wherever the backups go as holding the keys to the lab.

---

*powered by logic, coffee, and many sleepless nights*
