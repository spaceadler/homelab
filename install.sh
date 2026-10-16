#!/usr/bin/env bash
# install.sh: turn a fresh Debian, Raspberry Pi OS (64-bit) or Ubuntu machine
# into this homelab, or apply changes to one that already is.
#
#   ./install.sh                         set up the host, pick apps, start them
#   ./install.sh --apps "immich memos"   no menu; core apps are always included
#   ./install.sh --no-host               skip packages, Tailscale and firewall
#   ./install.sh --no-start              write config only, start nothing
#   ./install.sh --yes                   take every default, never prompt
#
# Safe to re-run, and meant to be: after `git pull`, after editing
# homelab.env, or to add apps. Secrets are generated once and then kept.
# Nothing is ever stopped or deleted: an app you deselect keeps running until
# you `docker compose down` it yourself.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true # keep & literal in ${x/a/b}

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS="$HOMELAB_DIR/containers"
CATALOG="$CONTAINERS/catalog.tsv"
CONFIG="$HOMELAB_DIR/homelab.env"
SITES="$CONTAINERS/core/nginx/sites"
STORAGE_SUBDIRS=(Documents Downloads Files Gallery Inbox Notes
    Media/Audiobooks Media/Books Media/Kiwix Media/Music Media/Podcasts
    Media/Recordings Media/Screenshots)
# Copied into every app's .env, so `docker compose` works in any app folder.
GLOBAL_KEYS=(DOMAIN TZ PUID PGID HOMELAB_DIR STORAGE_DIR TS_IP VAULT_HOST URL_SCHEME)

DO_HOST=1 DO_START=1 ASSUME_YES=0 CLI_APPS="" HAVE_APPS_FLAG=0
DOCKER="docker" GROUP_ADDED=0
declare -A GENRE SUB PORT NAME ABOUT GLOBALS
ORDER=() SELECTED=() SKIPPED=() FAILED=()

# --------------------------------------------------------------------- output

if [ -t 1 ]; then
    B=$'\e[1m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'
else
    B="" Y="" R="" N=""
fi
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s    ! %s%s\n' "$Y" "$*" "$N" >&2; }
die() {
    printf '%s    ✗ %s%s\n' "$R" "$*" "$N" >&2
    exit 1
}

interactive() { [ "$ASSUME_YES" = 0 ] && [ -t 0 ] && [ -r /dev/tty ]; }

# ask VAR "question" default: read an answer into VAR, or take the default.
ask() {
    local ans=""
    if interactive; then read -r -p "    $2 [$3]: " ans </dev/tty || true; fi
    printf -v "$1" '%s' "${ans:-$3}"
}

# confirm "question": yes unless the user types n.
confirm() {
    interactive || return 0
    local ans=""
    read -r -p "    $1 [Y/n]: " ans </dev/tty || true
    [[ ! $ans =~ ^[Nn] ]]
}

# ------------------------------------------------------------- small helpers

# env_file_set FILE KEY VALUE: replace KEY's line, or append it. Values go
# through the environment, so awk never interprets backslashes in them.
env_file_set() {
    local file=$1 tmp
    tmp=$(mktemp)
    if grep -q "^$2=" "$file" 2>/dev/null; then
        K="$2" V="$3" awk -F= '$1 == ENVIRON["K"] { print ENVIRON["K"] "=" ENVIRON["V"]; next } { print }' \
            "$file" >"$tmp"
    else
        { cat "$file" 2>/dev/null || true; printf '%s=%s\n' "$2" "$3"; } >"$tmp"
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$file"
}
# For hooks: set_env KEY VALUE edits the app's own .env.
set_env() { env_file_set .env "$1" "$2"; }

conf_get() {
    [ -f "$CONFIG" ] || return 0
    sed -n "s/^$1=//p" "$CONFIG" | tail -n1 | sed -E 's/^"(.*)"$/\1/'
}

# load_env FILE: export its KEY=VALUE lines literally (no shell expansion, so
# a value can never run code). Surrounding quotes are stripped.
load_env() {
    local line k v
    while IFS= read -r line || [ -n "$line" ]; do
        [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        k=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
        if [[ $v =~ ^\"(.*)\"$ ]] || [[ $v =~ ^\'(.*)\'$ ]]; then v=${BASH_REMATCH[1]}; fi
        export "$k=$v"
    done <"$1"
}

# The ${KEY} list envsubst may replace: only keys defined in FILE, so nginx's
# $host or a shell's $1 inside a template are left alone.
env_vars() { grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$1" | sed 's/=$//; s/.*/${&}/' | tr '\n' ' '; }

gen_pass() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | cut -c1-32; }

# fill_secrets LINE: replace each placeholder with a fresh random value.
fill_secrets() {
    local l=$1
    while [[ $l == *__HEX32__* ]]; do l=${l/__HEX32__/$(openssl rand -hex 16)}; done
    while [[ $l == *__HEX64__* ]]; do l=${l/__HEX64__/$(openssl rand -hex 32)}; done
    while [[ $l == *__HEX128__* ]]; do l=${l/__HEX128__/$(openssl rand -hex 64)}; done
    while [[ $l == *__B64_32__* ]]; do l=${l/__B64_32__/$(openssl rand -base64 32)}; done
    while [[ $l == *__PASS__* ]]; do l=${l/__PASS__/$(gen_pass)}; done
    printf '%s\n' "$l"
}

load_catalog() {
    local g a s p _icon n ab
    while IFS=$'\t' read -r g a s p _icon n ab; do
        GENRE[$a]=$g SUB[$a]=$s PORT[$a]=$p NAME[$a]=$n ABOUT[$a]=$ab
        ORDER+=("$a")
    done < <(grep -vE '^[[:space:]]*(#|$)' "$CATALOG")
}
app_dir() { printf '%s/%s/%s' "$CONTAINERS" "${GENRE[$1]}" "$1"; }

# ----------------------------------------------------------------- host setup

host_packages() {
    step "Host: packages, Docker, Tailscale"
    [ -r /etc/os-release ] || die "can't identify this OS (no /etc/os-release)"
    # shellcheck source=/dev/null
    . /etc/os-release
    local repo codename arch
    if [ "${ID:-}" = raspbian ]; then
        die "32-bit Raspberry Pi OS isn't supported; flash the 64-bit image"
    elif [ "${ID:-}" = ubuntu ] || [[ " ${ID_LIKE:-} " == *" ubuntu "* ]]; then
        repo=ubuntu codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
    elif [ "${ID:-}" = debian ] || [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        repo=debian codename=$VERSION_CODENAME
    else
        die "unsupported OS '${ID:-?}': this installer targets Debian, Raspberry Pi OS and Ubuntu"
    fi
    arch=$(dpkg --print-architecture)
    case $arch in amd64 | arm64) ;; *) die "unsupported architecture '$arch': needs amd64 or arm64" ;; esac
    info "$PRETTY_NAME ($arch)"

    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        ca-certificates curl git gettext-base openssl openssh-client ufw whiptail >/dev/null

    if ! command -v docker >/dev/null; then
        info "installing Docker from download.docker.com"
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL "https://download.docker.com/linux/$repo/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$repo $codename stable" |
            sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli \
            containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    fi
    sudo docker compose version >/dev/null 2>&1 ||
        die "Docker is installed but Compose v2 isn't: sudo apt-get install docker-compose-plugin"
    if ! id -nG "$USER" | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        GROUP_ADDED=1
    fi

    if ! command -v tailscale >/dev/null; then
        info "installing Tailscale from pkgs.tailscale.com"
        curl -fsSL "https://pkgs.tailscale.com/stable/$repo/$codename.noarmor.gpg" |
            sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL "https://pkgs.tailscale.com/stable/$repo/$codename.tailscale-keyring.list" |
            sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale >/dev/null
    fi
    if ! tailscale status >/dev/null 2>&1; then
        info "log this machine into your tailnet (open the link it prints):"
        sudo tailscale up
    fi
    info "Tailscale IP: $(tailscale ip -4 | head -n1)"
}

# Physical network cards: the only interfaces that face the LAN. Docker
# bridges, tailscale0 and lo are virtual and have no backing device.
physical_nics() { for d in /sys/class/net/*; do [ -e "$d/device" ] && basename "$d"; done; }

# Rewrite our DOCKER-USER block in a ufw rules file, leaving the rest alone.
write_docker_user_block() {
    local file=$1 tmp nic
    shift
    tmp=$(mktemp)
    # shellcheck disable=SC2024 # sudo reads the root-owned file; the copy is ours
    sudo awk '/^# BEGIN homelab docker-lan/ { skip = 1 } !skip { print } /^# END homelab docker-lan/ { skip = 0 }' \
        "$file" >"$tmp"
    if grep -q '^:DOCKER-USER' "$tmp"; then
        warn "$file already declares DOCKER-USER outside install.sh's block; merge these rules by hand:"
        for nic in "$@"; do warn "  -A DOCKER-USER -i $nic -m conntrack --ctstate NEW -j DROP"; done
        rm -f "$tmp"
        return
    fi
    {
        echo
        echo "# BEGIN homelab docker-lan (written by install.sh; re-run it after adding a network card)"
        echo "# Docker publishes ports by DNAT + FORWARD, so ufw's INPUT rules never see that"
        echo "# traffic. DOCKER-USER is the chain Docker leaves for us: drop new connections"
        echo "# that arrive from a physical interface. Replies to connections the containers"
        echo "# opened themselves are ESTABLISHED and still pass; tailscale0 is untouched."
        echo "*filter"
        echo ":DOCKER-USER - [0:0]"
        for nic in "$@"; do echo "-A DOCKER-USER -i $nic -m conntrack --ctstate NEW -j DROP"; done
        echo "COMMIT"
        echo "# END homelab docker-lan"
    } >>"$tmp"
    sudo install -m 0640 -o root -g root "$tmp" "$file"
    rm -f "$tmp"
}

firewall_setup() {
    step "Firewall: Tailscale in, LAN out"
    local nics src nic
    mapfile -t nics < <(physical_nics)
    if [ ${#nics[@]} -eq 0 ]; then
        warn "no physical network interfaces found; skipping the firewall"
        return
    fi
    info "closing to the LAN: ${nics[*]}"

    if [ -n "${SSH_CONNECTION:-}" ]; then
        src=${SSH_CONNECTION%% *}
        if ! [[ $src =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
            warn "you're connected over SSH from $src, which isn't a Tailscale address."
            warn "This session stays up, but new SSH logins will then only work over Tailscale."
            confirm "Continue with the firewall?" || {
                warn "skipped the firewall: the LAN can still reach every app"
                return
            }
        fi
    fi

    # Incoming is allowed by default and denied per physical card, rather than
    # the reverse: containers reach host-network services (the Beszel agent,
    # Syncthing) over Docker's bridges, which come and go and can't be listed
    # here. Only the cards are untrusted.
    sudo ufw default allow incoming >/dev/null
    sudo ufw default allow outgoing >/dev/null
    # Tailscale's WireGuard port: lets devices connect directly, not via relays.
    sudo ufw allow 41641/udp comment 'tailscale: direct connections' >/dev/null
    for nic in "${nics[@]}"; do
        sudo ufw deny in on "$nic" comment 'homelab: LAN closed, use Tailscale' >/dev/null
    done
    write_docker_user_block /etc/ufw/after.rules "${nics[@]}"
    write_docker_user_block /etc/ufw/after6.rules "${nics[@]}"
    sudo ufw --force enable >/dev/null
    sudo ufw reload >/dev/null
    info "ufw active: host services and published container ports answer only on tailscale0"
}

# Ubuntu's systemd-resolved listens on port 53 itself, which Pi-hole needs.
free_dns_port() {
    if sudo ss -Hlnup 'sport = :53' 2>/dev/null | grep -q systemd-resolve; then
        info "moving systemd-resolved off port 53 for Pi-hole"
        sudo mkdir -p /etc/systemd/resolved.conf.d
        printf '[Resolve]\nDNSStubListener=no\n' |
            sudo tee /etc/systemd/resolved.conf.d/homelab-pihole.conf >/dev/null
        # The stub file points at 127.0.0.53, which is about to go away.
        if [ "$(readlink -f /etc/resolv.conf)" = /run/systemd/resolve/stub-resolv.conf ]; then
            sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        fi
        sudo systemctl restart systemd-resolved
    elif sudo ss -Hlnup 'sport = :53' 2>/dev/null | grep -vq docker-proxy; then
        warn "something else already listens on port 53; Pi-hole won't start until it's stopped:"
        sudo ss -Hlnup 'sport = :53' | sed 's/^/      /' >&2
    fi
}

# ------------------------------------------------------------------ settings

configure_globals() {
    step "Settings: homelab.env"
    local first=0 domain tz puid pgid storage ts_ip vault_host
    if [ ! -f "$CONFIG" ]; then
        cp "$HOMELAB_DIR/homelab.env.example" "$CONFIG"
        first=1
    fi
    chmod 600 "$CONFIG"

    domain=$(conf_get DOMAIN)
    tz=$(conf_get TZ)
    [ -n "$tz" ] || tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo Etc/UTC)
    puid=$(conf_get PUID)
    pgid=$(conf_get PGID)
    storage=$(conf_get STORAGE_DIR)
    if [ $first = 1 ]; then
        ask domain "Local domain for your apps" "${domain:-homelab.local}"
        ask tz "Timezone" "$tz"
        ask storage "Folder for photos, music and documents" "${storage:-$HOMELAB_DIR/storage}"
    fi
    domain=${domain:-homelab.local}
    [[ $domain =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] ||
        die "DOMAIN '$domain' isn't a valid domain name (e.g. homelab.local)"
    storage=${storage:-$HOMELAB_DIR/storage}
    storage=$(realpath -m "$storage")

    if command -v tailscale >/dev/null && tailscale ip -4 >/dev/null 2>&1; then
        ts_ip=$(tailscale ip -4 | head -n1)
        vault_host=$(tailscale status --json --peers=false 2>/dev/null |
            sed -n 's/^ *"DNSName": *"\([^"]*\)\.",*$/\1/p' | head -n1)
    else
        ts_ip=$(conf_get TS_IP)
        vault_host=$(conf_get VAULT_HOST)
    fi
    [ -n "$ts_ip" ] || die "no Tailscale IP: run 'sudo tailscale up' (or, with --no-host, set TS_IP in homelab.env)"

    # HTTPS mode switches on by itself once a certificate for the domain is in
    # place (docs/tls.md). certbot keeps live/ root-only, hence sudo -n.
    local cert="$CONTAINERS/core/nginx/letsencrypt/live/$domain/fullchain.pem" scheme=http
    if sudo -n test -f "$cert" 2>/dev/null || [ -f "$cert" ]; then
        scheme=https
        # Port 443 now belongs to nginx, and the certificate covers vault.<domain>.
        vault_host=vault.$domain
    fi

    GLOBALS=([DOMAIN]=$domain [TZ]=$tz [PUID]=${puid:-$(id -u)} [PGID]=${pgid:-$(id -g)}
        [HOMELAB_DIR]=$HOMELAB_DIR [STORAGE_DIR]=$storage [TS_IP]=$ts_ip [VAULT_HOST]=$vault_host
        [URL_SCHEME]=$scheme)
    local k
    for k in "${GLOBAL_KEYS[@]}"; do
        [ "$k" = HOMELAB_DIR ] && continue # always where this repo is
        env_file_set "$CONFIG" "$k" "${GLOBALS[$k]}"
        info "$(printf '%-12s %s' "$k" "${GLOBALS[$k]:-(none)}")"
    done
}

# Prints the chosen non-core apps, space-separated.
app_menu() {
    local current=" $1 " a g state rows height list args=()
    if command -v whiptail >/dev/null; then
        for a in "${ORDER[@]}"; do
            [ "${GENRE[$a]}" = core ] && continue
            state=OFF
            [[ $current == *" $a "* ]] && state=ON
            args+=("$a" "$(printf '%-13s %s' "${GENRE[$a]}" "${ABOUT[$a]}")" "$state")
        done
        rows=$(tput lines 2>/dev/null || echo 24)
        height=$((rows < 44 ? rows - 2 : 42))
        list=$((height - 9))
        whiptail --title "Homelab apps" --separate-output --checklist \
            "Nginx, Pi-hole and Vaultwarden are always installed. Space toggles, Enter confirms." \
            "$height" 110 "$list" "${args[@]}" 3>&1 1>&2 2>&3 </dev/tty | tr '\n' ' '
        return
    fi
    # No whiptail: ask per genre.
    local genres=() out="" ans def apps
    for a in "${ORDER[@]}"; do
        g=${GENRE[$a]}
        [ "$g" = core ] && continue
        [[ " ${genres[*]} " == *" $g "* ]] || genres+=("$g")
    done
    for g in "${genres[@]}"; do
        apps="" def=n
        for a in "${ORDER[@]}"; do
            [ "${GENRE[$a]}" = "$g" ] || continue
            apps+="$a "
            [[ $current == *" $a "* ]] && def=y
        done
        read -r -p "    $g (${apps% })? [$def]: " ans </dev/tty || true
        [[ ${ans:-$def} =~ ^[Yy] ]] && out+="$apps"
    done
    printf '%s' "$out"
}

select_apps() {
    step "Apps"
    local wanted a picked=""
    if [ $HAVE_APPS_FLAG = 1 ]; then
        wanted=$CLI_APPS
    else
        wanted=$(conf_get APPS)
        if interactive; then wanted=$(app_menu "$wanted") || die "cancelled"; fi
    fi
    for a in $wanted; do
        [ -n "${GENRE[$a]+x}" ] || die "unknown app '$a' (the list is containers/catalog.tsv)"
    done
    for a in "${ORDER[@]}"; do
        if [ "${GENRE[$a]}" = core ]; then
            SELECTED+=("$a")
        elif [[ " $wanted " == *" $a "* ]]; then
            SELECTED+=("$a")
            picked+="$a "
        fi
    done
    env_file_set "$CONFIG" APPS "\"${picked% }\""
    info "${SELECTED[*]}"
}

make_storage() {
    local s
    for s in "${STORAGE_SUBDIRS[@]}"; do
        mkdir -p "${GLOBALS[STORAGE_DIR]}/$s" || die "can't create ${GLOBALS[STORAGE_DIR]}/$s (permissions?)"
    done
}

# ---------------------------------------------------------------------- apps

globals_block() {
    local k
    echo "# >>> homelab globals: install.sh rewrites this block from homelab.env on every run"
    for k in "${GLOBAL_KEYS[@]}"; do printf '%s=%s\n' "$k" "${GLOBALS[$k]}"; done
    echo "# <<< homelab globals"
}

# An app's .env = the globals block + the app's own settings. The app part is
# made once from .env.example (with fresh secrets) and kept from then on; keys
# that later appear in .env.example are appended.
write_env() {
    local dir=$1 env=$1/.env ex=$1/.env.example tmp line key
    tmp=$(mktemp)
    globals_block >"$tmp"
    if [ -f "$env" ] && grep -q '^# <<< homelab globals' "$env"; then
        awk 'keep { print } /^# <<< homelab globals/ { keep = 1 }' "$env" >>"$tmp"
    elif [ -f "$env" ]; then
        # An .env from before install.sh managed it: keep all but the globals.
        while IFS= read -r line || [ -n "$line" ]; do
            [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] &&
                [[ " ${GLOBAL_KEYS[*]} " == *" ${BASH_REMATCH[1]} "* ]] && continue
            printf '%s\n' "$line"
        done <"$env" >>"$tmp"
    elif [ -f "$ex" ]; then
        echo >>"$tmp"
        while IFS= read -r line || [ -n "$line" ]; do fill_secrets "$line"; done <"$ex" >>"$tmp"
    fi
    if [ -f "$env" ] && [ -f "$ex" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
            key=${BASH_REMATCH[1]}
            grep -q "^$key=" "$tmp" && continue
            fill_secrets "$line" >>"$tmp"
            info "${dir#"$CONTAINERS"/}: added $key to .env"
        done <"$ex"
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$env"
}

# Bind-mount sources that don't exist yet: create them as you, before Docker
# does it as root and leaves the app unable to write there.
make_mount_dirs() {
    local dir=$1 p
    # `|| true`: an app with no ./ mounts is fine, not a failed pipeline.
    { grep -oE "^[[:space:]]*-[[:space:]]*[\"']?\./[^:\"' ]+" "$dir/docker-compose.yml" || true; } |
        sed -E "s/^[[:space:]]*-[[:space:]]*[\"']?//" |
        while IFS= read -r p; do [ -e "$dir/$p" ] || mkdir -p "$dir/$p"; done
}

# Render every *.template next to itself (nginx.conf.template goes straight
# into nginx's sites/), filling in ${KEY}s from the app's .env.
render_templates() {
    local dir=$1 app=$2 vars f out
    vars=$(env_vars "$dir/.env")
    while IFS= read -r -d '' f; do
        if [ "${f##*/}" = nginx.conf.template ]; then out=$SITES/$app.conf; else out=${f%.template}; fi
        (load_env "$dir/.env" && envsubst "$vars" <"$f" >"$out.tmp")
        # Rendered files that carry a password are for your eyes only. Not
        # every file: some are read by an unprivileged user in the container
        # (CryptPad's config.js has *public* admin keys, so no "KEY" here).
        if grep -qE '\$\{[A-Z_]*(PASS|SECRET|TOKEN)[A-Z_]*\}' "$f"; then chmod 600 "$out.tmp"; fi
        mv -f "$out.tmp" "$out"
    # Only the app folder itself: its data folders are the app's business.
    done < <(find "$dir" -maxdepth 1 -name '*.template' -print0)
}

# run_hook DIR NAME: run an app's hook script from its folder, with its .env
# loaded. Returns the hook's exit code (0 if it has none).
run_hook() {
    local dir=$1 hook=$2
    [ -f "$dir/$hook" ] || return 0
    (
        cd "$dir"
        load_env .env
        export DOCKER HOMELAB_APPS="${SELECTED[*]}" HOMELAB_CATALOG="$CATALOG" HOMELAB_SITES="$SITES"
        export -f env_file_set set_env
        bash "./$hook"
    )
}

configure_app() {
    local app=$1 dir
    dir=$(app_dir "$app")
    [ -f "$dir/docker-compose.yml" ] || die "$dir/docker-compose.yml is missing"
    write_env "$dir"
    # Render first: a mounted config file that doesn't exist yet would
    # otherwise be created as a directory.
    render_templates "$dir" "$app"
    make_mount_dirs "$dir"
    if [ -f "$dir/nginx.conf" ]; then cp "$dir/nginx.conf" "$SITES/$app.conf"; fi
    run_hook "$dir" configure.sh || die "$app: configure.sh failed"
}

start_app() {
    local app=$1 dir rc=0
    dir=$(app_dir "$app")
    run_hook "$dir" pre-start.sh || rc=$?
    if [ $rc = 10 ]; then
        SKIPPED+=("$app")
        return 0
    elif [ $rc != 0 ]; then
        warn "$app: pre-start.sh failed ($rc); not starting it"
        FAILED+=("$app")
        return 0
    fi
    info "${NAME[$app]}"
    if ! (cd "$dir" && $DOCKER compose up -d --remove-orphans --quiet-pull 2>&1 | sed 's/^/      /'); then
        warn "$app didn't start; see: cd ${dir#"$HOMELAB_DIR"/} && docker compose logs"
        FAILED+=("$app")
        return 0
    fi
    run_hook "$dir" post-start.sh || warn "$app: post-start.sh failed"
}

reload_nginx() {
    $DOCKER ps --format '{{.Names}}' | grep -qx nginx || return 0
    if $DOCKER exec nginx nginx -t >/dev/null 2>&1; then
        $DOCKER exec nginx nginx -s reload >/dev/null
    else
        warn "nginx rejected the new config; it keeps serving the old one:"
        $DOCKER exec nginx nginx -t 2>&1 | sed 's/^/      /' >&2
    fi
}

summary() {
    step "Done"
    local a url direct d="${GLOBALS[DOMAIN]}" ip="${GLOBALS[TS_IP]}"
    printf '    %-20s %-38s %s\n' "App" "Address" "Direct"
    for a in "${SELECTED[@]}"; do
        [ "$a" = nginx ] && continue
        if [ "$a" = vaultwarden ]; then
            url="https://${GLOBALS[VAULT_HOST]:-<no MagicDNS name>}" direct="(HTTPS only)"
        elif [ "${SUB[$a]}" = "-" ]; then
            url="-" direct="$ip:${PORT[$a]}"
        else
            url="${GLOBALS[URL_SCHEME]}://${SUB[$a]}.$d" direct="http://$ip:${PORT[$a]}"
        fi
        printf '    %-20s %-38s %s\n' "${NAME[$a]}" "$url" "$direct"
    done
    [ ${#SKIPPED[@]} -eq 0 ] || warn "not started (see messages above): ${SKIPPED[*]}"
    [ ${#FAILED[@]} -eq 0 ] || warn "failed: ${FAILED[*]}"
    cat <<EOF

    Next steps
    1. Names: Tailscale admin console → DNS (https://login.tailscale.com/admin/dns)
       → Add nameserver → Custom: $ip, "Restrict to domain": $d.
       Leave it unrestricted (+ "Override DNS servers") for ad blocking everywhere.
    2. Vaultwarden: https://${GLOBALS[VAULT_HOST]:-<machine>.<tailnet>.ts.net}/admin, with the token in
       containers/core/vaultwarden/.env; invite your email, then register with it.
EOF
    if [ "${GLOBALS[URL_SCHEME]}" = http ]; then
        echo "       (Needs MagicDNS and HTTPS Certificates enabled on that same DNS page.)"
    fi
    cat <<EOF
    3. Logins: every generated password is in its app's .env, e.g.
       grep -h PASSWORD containers/*/*/.env
EOF
    if [ $GROUP_ADDED = 1 ]; then
        echo "    4. Log out and back in to use 'docker' without sudo."
    fi
}

# ---------------------------------------------------------------------- main

main() {
    while [ $# -gt 0 ]; do
        case $1 in
        --apps) CLI_APPS=${2?--apps needs a list} HAVE_APPS_FLAG=1 && shift 2 ;;
        --apps=*) CLI_APPS=${1#*=} HAVE_APPS_FLAG=1 && shift ;;
        --no-host) DO_HOST=0 && shift ;;
        --no-start) DO_START=0 && shift ;;
        -y | --yes) ASSUME_YES=1 && shift ;;
        -h | --help) sed -n '2,14p' "$0" | sed -E 's/^# ?//' && exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
        esac
    done
    [ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root; it uses sudo where it needs to"

    load_catalog
    if [ $DO_HOST = 1 ]; then
        sudo -v || die "needs sudo"
        host_packages
        firewall_setup
        free_dns_port
    fi
    for c in openssl envsubst docker; do
        command -v $c >/dev/null || die "'$c' is missing (run without --no-host to install it)"
    done
    docker info >/dev/null 2>&1 || DOCKER="sudo docker"

    configure_globals
    select_apps
    make_storage

    step "Configuring ${#SELECTED[@]} apps"
    mkdir -p "$SITES"
    find "$SITES" -maxdepth 1 -name '*.conf' -delete # regenerated just below
    for a in "${SELECTED[@]}"; do configure_app "$a"; done
    info "done: .env, rendered configs and nginx sites written"

    if [ $DO_START = 1 ]; then
        step "Starting"
        for a in "${SELECTED[@]}"; do start_app "$a"; done
        reload_nginx
    fi
    summary
}

main "$@"
