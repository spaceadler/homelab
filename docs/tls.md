# HTTPS

Out of the box, every app is plain HTTP on `http://<app>.homelab.local`, and
that's fine here. Traffic between your devices and this machine already
travels inside Tailscale's WireGuard tunnel, encrypted end to end, so nobody
on the path can read or change it. HTTPS adds the padlock, not secrecy.

A few apps need the padlock anyway, because browsers only allow some features
on HTTPS pages:

| App | What breaks without HTTPS |
| --- | --- |
| Vaultwarden | The web vault, which needs the browser's crypto API (HTTPS-only); the Bitwarden apps expect HTTPS too. |
| CryptPad | CryptPad's own docs require HTTPS for anything beyond local testing. |
| Nomie, Super Productivity | Installing as an app on your phone, and working offline. |

There are two ways to get HTTPS, and this repo supports both:

1. **Tailscale's certificate: automatic, for Vaultwarden only.** This is the
   default, and needs one switch in the Tailscale admin console.
2. **Your own domain: every app on HTTPS.** About 15 minutes of setup.
   `install.sh` notices the certificate and switches everything over.

---

## 1. The default: `tailscale serve` for Vaultwarden

Tailscale can issue a real, publicly trusted Let's Encrypt certificate for
your machine's tailnet name, e.g. `homelab.tail1234.ts.net`. `install.sh`
uses that for Vaultwarden, through `tailscale serve`. Tailscale terminates
HTTPS on that name and forwards to Vaultwarden on `127.0.0.1:4345`.

**Turn it on (once per tailnet):**
[Tailscale admin console → DNS](https://login.tailscale.com/admin/dns) →
enable **MagicDNS**, then under **HTTPS Certificates** click **Enable HTTPS**.
Re-run `./install.sh`. Vaultwarden is then at
`https://<machine>.<tailnet>.ts.net`, and `http://vault.homelab.local`
redirects there.

**What to know:**

- **Only your tailnet can reach it.** `tailscale serve` is tailnet-only
  (`tailscale funnel` would be the public-internet version, which this repo
  never uses).
- **Renewal is automatic.** Tailscale renews the certificate itself.
- **The name becomes public.** Every Let's Encrypt certificate is published
  in the public Certificate Transparency logs, so your machine and tailnet
  name become public. That name gives nobody access, but it is visible.
- **Checking or undoing it:** `sudo tailscale serve status` shows what's
  served; `sudo tailscale serve reset` undoes it.

Why not a certificate for the Tailscale IP itself? No public authority
issues certificates for private IPs. You'd have to create your own
certificate authority and install it on every phone and computer, and the
Bitwarden apps still often reject it.

---

## 2. Your own domain: HTTPS for every app

You need a domain whose DNS is hosted on Cloudflare. The free plan is fine,
and other DNS providers work too (see the end). Nothing becomes public:

- **No DNS records are published.** You won't create a single record for
  your apps. Inside your tailnet, Pi-hole answers `*.yourdomain` with the
  Pi's Tailscale IP, exactly as it does for `homelab.local` now.
- **No ports are opened.** Let's Encrypt checks that you own the domain
  through a temporary DNS TXT record (the DNS-01 challenge), never by
  connecting to your machine.
- **Only the wildcard is published.** The certificate is for
  `*.yourdomain`, so the public certificate logs show the wildcard, never
  `gallery.` or `vault.`.

> **Already have a website on your domain** (say, through a Cloudflare
> Tunnel)? Use a subdomain such as `lab.example.com` as the homelab domain.
> Otherwise devices on your tailnet would resolve the bare domain to the Pi
> instead of your website. Everything below works the same: the certificate
> covers `lab.example.com` and `*.lab.example.com`.

The examples use `lab.example.com`; substitute your own.

### Step 1: a Cloudflare API token that can only edit this domain's DNS

Cloudflare dashboard → **My Profile → API Tokens → Create Token** → template
**Edit zone DNS**.

- **Permissions:** Zone → DNS → Edit.
- **Zone Resources:** Include → Specific zone → *your domain*. Don't pick
  "All zones".

Create it and copy the token. Treat it like a password: it can change your
domain's DNS.

### Step 2: give the token to certbot

```bash
cd ~/homelab/containers/core/nginx
mkdir -p certbot letsencrypt
printf 'dns_cloudflare_api_token = %s\n' 'PASTE-TOKEN-HERE' > certbot/cloudflare.ini
chmod 600 certbot/cloudflare.ini
```

Git never sees `certbot/` or `letsencrypt/`; `.gitignore` covers them.

### Step 3: get the certificate

```bash
docker run --rm \
  -v "$PWD/letsencrypt:/etc/letsencrypt" \
  -v "$PWD/certbot:/certbot:ro" \
  certbot/dns-cloudflare certonly \
  --dns-cloudflare --dns-cloudflare-credentials /certbot/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  -d lab.example.com -d '*.lab.example.com' \
  --agree-tos -m you@example.com --non-interactive
```

certbot creates a TXT record, Let's Encrypt checks it, certbot removes it.
The certificate lands in `letsencrypt/live/lab.example.com/`.

### Step 4: switch the homelab over

```bash
cd ~/homelab
sed -i 's/^DOMAIN=.*/DOMAIN=lab.example.com/' homelab.env
./install.sh
```

`install.sh` finds `letsencrypt/live/lab.example.com/fullchain.pem` and turns
on HTTPS mode:

- **nginx:** every site listens on 443 with your certificate. Plain HTTP
  redirects to HTTPS, and a name that isn't one of your apps is refused
  during the handshake.
- **Apps:** each app's own idea of its address (BookStack's `APP_URL`,
  Paperless's `PAPERLESS_URL`, CryptPad's origins, the CORS settings, the
  Glance dashboard) switches to `https://`.
- **Vaultwarden** moves to `https://vault.lab.example.com`, served by nginx.
  `tailscale serve` is switched off, because nginx needs port 443.
- **Pi-hole** now answers `*.lab.example.com` instead of `*.homelab.local`.

### Step 5: point your tailnet at the new name

[Tailscale admin console → DNS](https://login.tailscale.com/admin/dns) →
edit the Pi-hole nameserver you added during setup → **Restrict to domain**:
`lab.example.com` (in place of `homelab.local`).

Then update anything that remembers the old address:

- **Phone apps:** the Bitwarden, Immich and DAVx5 apps, plus Subsonic
  clients for Navidrome.
- **Settings stored inside an app:** e.g. Immich → Administration →
  Settings → Server → External domain.

### Step 6: renewal

Certificates last 90 days. `scripts/renew-certs.sh` renews when one is due
and reloads nginx. Run it daily from cron (`crontab -e`):

```cron
0 3 * * * /home/<you>/homelab/scripts/renew-certs.sh >/dev/null
```

### Going back

Move `containers/core/nginx/letsencrypt/live/<domain>` out of the way (or
set `DOMAIN` back to `homelab.local`) and run `./install.sh`. Every setting
returns to plain HTTP, and Vaultwarden goes back to `tailscale serve`.

### Not on Cloudflare?

certbot has DNS plugins for most providers, published as images named
`certbot/dns-<provider>`: route53, digitalocean, google, linode, ovh,
gandi, and others. Use that image and its credentials flags in step 3, and
change the image name in `scripts/renew-certs.sh`. Anything else works too
(acme.sh, a certificate from another authority) as long as the files end up
at `letsencrypt/live/<DOMAIN>/fullchain.pem` and `privkey.pem`.
