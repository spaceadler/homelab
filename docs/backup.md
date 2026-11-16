# Backup & disaster recovery

← [README](../README.md)

A 3-2-1 strategy: three copies of everything, on two different machines,
one of them off-site. It's built from Syncthing and one encrypted cloud, so
no provider ever holds a readable copy of your files.

The idea is that every device gets the same `~/homelab` folder, holding
only the subfolders it needs. Syncthing keeps those subfolders identical
across devices, so your devices together *are* the cloud:

| Folder | Server | Main computer | Third device |
| --- | --- | --- | --- |
| `storage/` | ✔ the live files | ✔ synced | |
| `backup/` | ✔ written by `backup.sh` | ✔ synced | |
| `mailbox/` | ✔ | ✔ | ✔ |
| `dev/` | ✔ | optional | optional |
| `containers/` | ✔ live, **never synced** | | |

1. **Layer 1: application backup, on the server.** `sudo
   ./scripts/backup.sh` stops every running stack, copies `containers/`
   (configs, `.env` secrets and app databases) to
   `backup/containers/<date>/` with exact permissions, and starts them
   again. Run it often, nightly from root's crontab
   ([how](../how-to-use.md#5-back-it-up)). The copy is what makes apps safe to
   sync: a running database's files change mid-copy and arrive corrupt,
   while the backup is a stopped, consistent snapshot. That's why
   `containers/` itself is never shared.
2. **Layer 2: the main computer (hot copy).** On your desktop, make a
   `~/homelab` folder and share `storage/`, `backup/` and `mailbox/` into
   it with Syncthing. Add `dev/` too if you want your repositories as local
   files as well as in Git. That machine now holds every file plus the
   latest app backups, which is everything needed to rebuild the server
   (see below).
3. **The third device (laptop, work machine): a shared space.** Connect it
   to the tailnet and share just `mailbox/` (and `dev/` if you like).
   `mailbox/` becomes a drop zone shared by all three devices: put a file
   in on one and it's on the others moments later, reachable from anywhere,
   with no cloud storage involved.
4. **Layer 3: off-site, end-to-end encrypted (cold copy).** From the main
   computer, upload `storage/` and `backup/` to a cloud that only ever sees
   encrypted data:
   - **Filen** is end-to-end encrypted by design.
   - **Backblaze B2** is cheap storage but not encrypted on its own, so put
     a client that encrypts before uploading in front of it, such as
     `rclone` with a `crypt` remote, or `restic`.

   That makes three copies (server, main computer, cloud) on two machines,
   with one off-site: 3-2-1, with nothing to remember once it's set up.

**Make it robust:**

- **Turn on file versioning.** Syncthing mirrors, and a mirror isn't a
  backup on its own: a file deleted or overwritten on one device goes away
  everywhere. On the main computer, set `storage/` and `backup/` to
  **Staggered File Versioning** (Edit folder → File Versioning), so
  replaced and deleted files are kept for a while.
- **Connect over Tailscale.** The server's firewall closes the LAN, so
  Syncthing can't reach it there. On the other devices, set the server's
  address to `tcp://<server-tailscale-ip>:22000` (Edit device → Advanced →
  Addresses) for a direct connection instead of Syncthing's relays.
- **Mind where the secrets go.** `backup/` holds every app's `.env`. Keep it
  on machines you'd trust with your passwords, which is why it isn't on the
  third device.
- **Prune old backups.** Every run adds a dated copy of `containers/`.
  Keep the latest 14, for example:
  `ls -1d ~/homelab/backup/containers/*/ | head -n -14 | xargs -r sudo rm -rf`

**Recovering on a new machine** (about an hour, most of it copying):

```bash
# 1. Fresh 64-bit Raspberry Pi OS / Debian / Ubuntu, then:
git clone https://github.com/spaceadler/homelab ~/homelab
# 2. Put your files back from the main computer (or the cloud): storage/ as
#    it is, and the latest container backup over containers/:
rsync -a main-computer:homelab/storage/ ~/homelab/storage/
sudo rsync -a main-computer:homelab/backup/containers/<date>/ ~/homelab/containers/
# 3. Run the installer. It keeps the restored .env files (your passwords)
#    and picks up the new machine's Tailscale IP.
cd ~/homelab && ./install.sh
```

---

*powered by logic, coffee, and many sleepless nights*
