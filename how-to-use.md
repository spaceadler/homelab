# How to Use This Repo

From a blank machine to your own photos, music and passwords on your phone.
The [README](README.md) is the reference for everything afterwards:
addresses, commands, the security model.

## Prelude: Philosophy & Evolution
Keep in mind that this setup is not necessarily the "best" way to build a homelab. It is simply the way that works best for me. This architecture originally started as a simple storage container for my documents for an entire year before evolving into a wider, more comprehensive ecosystem of containers, `dev` repositories, and staged workflows. Features like the `~/homelab/dev` structure and the tight integration with Gitea and Agentic AIs are relatively new additions, and so is `install.sh`, which turned this repository from a skeleton you fill in yourself into one you can clone and run. Because of this organic growth, the architecture remains highly malleable. Expect further updates, refinements, and expansions to this repository as the homelab continues to evolve!

## Prelude: Hardware & Performance
While the architecture documentation focuses on the Raspberry Pi 4B, this specific hardware setup is entirely optional. Any standard x86-64 workstation will work beautifully, especially considering how well the stack performs on an ARM-based Pi.

To give you an idea of the performance footprint on a Raspberry Pi 4B (8GB) running the full stack:
- **CPU Utilization**: Averages around 20% on idle, scaling up to ~60% during heavy `syncthing` file operations.
- **Memory**: Idles at roughly 6GB of RAM usage.
- **Swap**: Utilizes around 8GB of SSD-backed swap space to handle memory spikes gracefully.

Pick fewer apps and all three drop accordingly.

---

## 1. Prepare the machine

You need:

- **A machine:** a 64-bit Raspberry Pi OS, Debian or Ubuntu machine,
  ARM64 or x86-64.
- **A Tailscale account:** free at [tailscale.com](https://tailscale.com),
  with the Tailscale app on your phone and laptop.

**On a Raspberry Pi**, two things make it a reliable server:

1. **Boot from an SSD, not the SD card.** SD cards wear out under a
   server's constant writes. Update the bootloader and make USB the first
   boot device:
   ```bash
   sudo rpi-eeprom-update -a        # then reboot
   sudo rpi-eeprom-config --edit    # set BOOT_ORDER=0xf41 (USB first, SD as fallback)
   ```
   Then flash **Raspberry Pi OS Lite (64-bit)** straight onto the SSD with
   Raspberry Pi Imager. Set your user, Wi-Fi/SSH and hostname in its
   settings.
2. **Give it room to breathe.** With every app running, 8 GB of RAM is
   tight. Compressed RAM swap (zram) first, then a swap file on the SSD as
   overflow:
   ```bash
   sudo apt install zram-tools
   printf 'ALGO=zstd\nPERCENT=200\nPRIORITY=100\n' | sudo tee /etc/default/zramswap
   sudo systemctl restart zramswap
   sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile
   echo '/swapfile none swap sw,pri=50 0 0' | sudo tee -a /etc/fstab && sudo swapon -a
   ```
   If your OS already set up a swap file of its own, remove that one first
   so you don't end up with two.

## 2. Clone and run

Log in as your normal user, not root; the script uses `sudo` where it
needs to.

```bash
git clone https://github.com/spaceadler/homelab ~/homelab
cd ~/homelab
./install.sh
```

It works through these steps, printing what it's doing as it goes:

1. **Packages:** installs Docker (from Docker's own repository) and
   Tailscale.
2. **Tailscale:** prints a login link. Open it and add this machine to your
   tailnet.
3. **Firewall:** closes every network card to the LAN; only Tailscale gets
   in.
   > If you're connected over SSH from your home network, it asks first:
   > your current session stays open, but new SSH logins will only work
   > over Tailscale. Reconnect via the machine's Tailscale IP afterwards.
4. **Three questions:** your local domain (default `homelab.local`), your
   timezone, and where your files go (default `~/homelab/storage`; point
   it at a bigger disk if you have one).
5. **The app menu:** Nginx, Pi-hole and Vaultwarden are always included.
   Tick what you want with Space, then press Enter. The list, with what
   each app does, is in the [README](README.md#the-apps-and-their-addresses).
6. **Setup and start:** generates every password, writes the configs and
   starts the apps.

The first run downloads every image, so expect anything from five minutes
to an hour on a Pi, depending on what you picked and your connection.
Nomie builds from source and CryptPad downloads OnlyOffice on first start;
those two are the slowest.

It finishes with a table of every app's address, and three next steps.

## 3. Point your tailnet at Pi-hole

So that `gallery.homelab.local` means something to your phone:
[Tailscale admin console → DNS](https://login.tailscale.com/admin/dns):

- **Add nameserver → Custom:** this machine's Tailscale IP (the summary
  shows it).
- **Choose how much goes through Pi-hole:**
  - **Turn on "Restrict to domain"** and enter your domain
    (`homelab.local`). Only app names go to Pi-hole.
  - **Or leave it unrestricted and tick "Override DNS servers".** Every
    lookup on every device goes through Pi-hole, which gives you ad
    blocking everywhere.
- **For Vaultwarden, on the same page:** enable **MagicDNS** and **HTTPS
  Certificates**, then run `./install.sh` once more so it can set up
  `tailscale serve`.

Now open `http://home.homelab.local` from your phone (with Tailscale on):
that's Glance, with every app you installed and whether it's up.

## 4. Log in to everything

Most apps make the first account you create the admin, so create yours
before you invite anyone. The handful that work differently (Vaultwarden's
invite, BookStack's default login, qBittorrent's temporary password) are
listed under [First logins](README.md#first-logins). Every generated
password is in its app's `.env`:

```bash
grep -h PASSWORD ~/homelab/containers/*/*/.env
```

Then install the phone apps that go with your server:

- **Bitwarden:** server URL is your Vaultwarden address.
- **Immich:** `http://gallery.homelab.local`. Turn on background backup.
- **Music:** any Subsonic app (Symfonium, Substreamer, Feishin) with
  `http://music.homelab.local`.
- **Audiobookshelf:** its own app.
- **Calendar and contacts:** DAVx5 on Android, or iOS Settings → Calendar
  → Accounts, with `http://cal.homelab.local`.

## 5. Back it up

The Layer 1 backup copies every app's config and database into
`backup/containers/<date>/`. Run it from root's crontab at a quiet hour,
since the apps pause while it copies:

```bash
sudo crontab -e
# every night at 04:00
0 4 * * * /home/<you>/homelab/scripts/backup.sh >/dev/null 2>&1
```

Then get the files off the machine:

1. **Main computer:** make a `~/homelab` folder there, and share
   `storage/`, `backup/` and `mailbox/` into it with Syncthing (`dev/` too,
   if you want your repos as local files as well as in Git).
2. **Third device:** share just `mailbox/` (and `dev/`), so all three
   devices share one drop zone.
3. **Off-site:** upload from the main computer to an end-to-end encrypted
   cloud (Filen, or Backblaze B2 behind `rclone crypt` or `restic`).

That's 3-2-1 with no extra effort once it's set up. The why, and four
tips that make it robust (file versioning, connecting over Tailscale,
where secrets end up, pruning old backups), are in
[Backup & disaster recovery](README.md#backup--disaster-recovery).

## 6. Living with it

- **Add or remove apps:** run `./install.sh` again.
- **Update apps:** run `docker compose pull && docker compose up -d` in an
  app's folder; Cup shows which ones have updates.
- **Update this repo:** `git pull && ./install.sh`.
- **More:** every other command is in
  [Operating it](README.md#operating-it).

### Extending with custom scripts
`scripts/` holds the backup and certificate scripts. Put your own
automation next to them. If you need inspiration, check out the
[spaceadler/scripts](https://github.com/spaceadler/scripts) repository!

### The Gitea workflow & Agentic AIs
Once Gitea (`git.homelab.local`) is running, you can create your own private Git repositories. Clone them into `~/homelab/dev/` and sync that folder across your devices with Syncthing.

This workflow is especially powerful if you use Agentic AIs. You can store your agent dotfiles, rules, and customization settings here (for example, configuring your Antigravity agent!) and have them seamlessly persist and sync across your entire homelab ecosystem.

### Staging in the mailbox
The `mailbox/` folder is designed to act like a physical inbox on a desk. When you are in a hurry and have files or folders that you don't have time to properly sort yet, drop them into the mailbox. This prevents you from cluttering up your meticulously organized `storage` arrays with unsorted data. You can come back later, think it over, and move them to their permanent homes.

### Notes
`storage/Notes` is a plain folder of Markdown files. Globnotes
(`notes.homelab.local`) edits it in the browser, and because it's just
files, you can open the same folder as an **Obsidian** vault (synced with
Syncthing) or in any editor. Use whichever fits your second-brain
workflow; they don't get in each other's way.

---

*powered by logic, coffee, and many sleepless nights*
