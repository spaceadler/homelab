#!/usr/bin/env python3
"""apps.py: install, start, stop, restart or delete an app, or report on them.

The homelab helper runs it for the App Store (see actions.json), as your user:

    apps.py status                       every app's containers, as JSON
    apps.py usage                        each app's CPU and memory now, as JSON
    apps.py logs APP                     an app's recent logs, as JSON
    apps.py start|stop|restart|update|delete|install APP
    apps.py scan PATH                    compose files at PATH, as JSON
    apps.py import NAME FILE SERVICES URL ICON PORT
    apps.py forget APP                   un-import (containers untouched)

An installed app is one on the home screen: a catalog app in APPS (core apps
always), in containers/<collection>/<app>, or one you imported, described by
containers/extras/<app>/app.json. A catalog app's compose files are every
compose file in its folder and in the folders right inside it (Beszel keeps
its agent in ./agent), so an app made of several containers, or several
compose files, starts and stops as one. Each file runs as `docker compose`
from its own folder, exactly as if you ran it there yourself.

    start    runs the app's pre-start.sh first, if it has one (exit 10 means
             "not yet": Kiwix with no archives, say), then `up -d`
    stop     `stop`: the containers stay, ready to start again
    restart  `restart`, or a start if it has no containers
    update   `pull`, then `up -d`: new images, and the containers recreated
             on them; data stays
    delete   `down`, and the app leaves the home screen: a catalog app is
             taken out of APPS and install.sh re-run (so its address and
             dashboard entry go too); an imported one is marked not
             installed. Its data and compose files stay, so install brings
             it back as it was. Core apps can't be deleted.
    install  the reverse: a catalog app goes into APPS and install.sh sets it
             up and starts it; an imported one is started again

The home screen itself (os) and nginx aren't on the list: stopping either
would take the App Store down with it.

Import makes a compose file you already have into apps here: scan lists the
compose files in a folder (and two levels below it) with their services;
import records one app from one of them in containers/extras/<app>/app.json:
its name and address, and which of the file's services are its own (SERVICES
is a comma list, the app's own service first). One file can hold several apps
(Immich and Navidrome, say): each gets its services, and start, stop and
delete touch only those. Nothing is copied or moved. Only compose files under
your home folder, and never one the home screen could have written.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOMELAB = Path(__file__).resolve().parents[2]
CONTAINERS = HOMELAB / "containers"
CATALOG = CONTAINERS / "catalog.tsv"
CONFIG = HOMELAB / "homelab.env"
EXTRAS = CONTAINERS / "extras"
COMPOSE_NAMES = ("compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml")
APP_ID = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")
SERVICE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
NOT_MANAGED = {"os", "nginx"}
SKIP = 10  # a pre-start.sh exit code: not ready to start, not an error
HOME = Path.home().resolve()
OS_DATA = CONTAINERS / "core" / "os" / "data"  # the home screen can write here
SCAN_DEPTH = 2
SCAN_MAX_FILES = 100
SHOW_BYTES = 32 * 1024  # compose text shown per file
SHOW_TOTAL = 700 * 1024
SKIP_DIRS = {"node_modules", ".git", "__pycache__", "venv", ".venv"}
LOG_LINES = 300  # per compose file
LOG_BYTES = 400 * 1024


def say(message):
    print(message, flush=True)


def read_env(path):
    values = {}
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return values
    for line in lines:
        key, sep, value = line.partition("=")
        key = key.strip()
        if not sep or not key or key.startswith("#"):
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key] = value
    return values


def rewrite(path, text):
    """Rewrite a file in place, keeping it the same file: the home screen
    sees homelab.env through a bind mount of that one file, which would go
    on showing the old copy of a file that was replaced instead."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
        f.truncate()


def write_private(path, text):
    """Replace a file atomically, never following a link planted there."""
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


# ------------------------------------------------------------------ apps

def compose_file(folder):
    """The compose file `docker compose` would pick in this folder, if any."""
    for name in COMPOSE_NAMES:
        f = folder / name
        try:
            if f.is_file():
                return f
        except OSError:
            continue
    return None


def folder_compose_files(folder):
    """The folder's compose file, then those of the folders right inside it."""
    files = []
    own = compose_file(folder)
    if own:
        files.append(own)
    try:
        subfolders = sorted(p for p in folder.iterdir() if p.is_dir() and not p.is_symlink())
    except OSError:
        subfolders = []
    for sub in subfolders:
        f = compose_file(sub)
        if f:
            files.append(f)
    return files


def catalog():
    """[(collection, id, subdomain, name)] in catalog order."""
    rows = []
    try:
        lines = CATALOG.read_text().splitlines()
    except OSError:
        return rows
    for line in lines:
        fields = line.split("\t")
        if not line.startswith("#") and len(fields) == 7:
            rows.append((fields[0], fields[1], fields[2], fields[5]))
    return rows


def imported_app(app_id):
    """An imported app's description, or None. Only the helper writes these."""
    try:
        info = json.loads((EXTRAS / app_id / "app.json").read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(info, dict) or not isinstance(info.get("files"), list):
        return None
    files = [Path(f) for f in info["files"] if isinstance(f, str) and f.startswith("/")]
    services = info.get("services")
    if not (isinstance(services, list) and services and all(isinstance(s, str) and SERVICE.fullmatch(s) for s in services)):
        services = None  # the whole file
    return {"id": app_id, "name": info.get("name", app_id), "kind": "imported", "folder": None,
            "files": [f for f in files if f.is_file()], "services": services,
            "installed": info.get("installed", True) is not False, "info": info}


def imported_apps():
    apps = {}
    if EXTRAS.is_dir():
        for entry in sorted(EXTRAS.iterdir()):
            if APP_ID.fullmatch(entry.name):
                app = imported_app(entry.name)
                if app:
                    apps[entry.name] = app
    return apps


def catalog_app(collection, app_id, name, installed):
    folder = CONTAINERS / collection / app_id
    return {"id": app_id, "name": name, "kind": "catalog", "core": collection == "core", "folder": folder,
            "files": folder_compose_files(folder), "services": None, "installed": installed}


def every_app():
    """{id: app} for every app the App Store knows, installed or not."""
    chosen = set(read_env(CONFIG).get("APPS", "").split())
    apps = {}
    for collection, app_id, sub, name in catalog():
        if app_id in NOT_MANAGED or sub == "-":
            continue
        apps[app_id] = catalog_app(collection, app_id, name, collection == "core" or app_id in chosen)
    for app_id, app in imported_apps().items():
        apps.setdefault(app_id, app)
    return apps


def all_apps():
    """{id: app} for every installed app: what the home screen shows."""
    return {k: v for k, v in every_app().items() if v["installed"]}


# ---------------------------------------------------------------- docker

def docker_env():
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL")}
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    return env


def compose(file, *args):
    """`docker compose <args>` for one file, from its folder; output goes to the job."""
    say(f"$ docker compose {' '.join(args)}    ({file.parent})")
    return subprocess.run(["docker", "compose", "-f", str(file), *args], cwd=file.parent, env=docker_env(),
                          stdin=subprocess.DEVNULL, check=False).returncode


def run_installer():
    """Re-run install.sh as the helper always does: no host setup, no prompts."""
    say("$ ./install.sh --no-host --yes")
    return subprocess.run([str(HOMELAB / "install.sh"), "--no-host", "--yes"], cwd=HOMELAB, env=docker_env(),
                          stdin=subprocess.DEVNULL, check=False).returncode


def containers():
    """Every container on the machine: (name, state, status, compose folder, service)."""
    fmt = "\t".join(["{{.Names}}", "{{.State}}", "{{.Status}}",
                     '{{.Label "com.docker.compose.project.working_dir"}}',
                     '{{.Label "com.docker.compose.service"}}', "{{.Image}}"])
    result = subprocess.run(["docker", "ps", "-a", "--no-trunc", "--format", fmt], env=docker_env(),
                            stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "docker ps failed")
    rows = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 6:
            rows.append(dict(zip(("name", "state", "status", "folder", "service", "image"), parts)))
    return rows


def summarize(found, files):
    if not files:
        return "no-compose"
    if not found:
        return "removed"
    states = [c["state"] for c in found]
    if any(s == "restarting" for s in states):
        return "restarting"
    running = sum(s == "running" for s in states)
    if running == len(states):
        return "unhealthy" if any("(unhealthy)" in c["status"] for c in found) else "running"
    return "partial" if running else "stopped"


def app_status(apps):
    rows = containers()
    by_folder = {}
    for row in rows:
        if row["folder"]:
            by_folder.setdefault(os.path.realpath(row["folder"]), []).append(row)
    report = {}
    for app_id, app in apps.items():
        found = []
        for f in app["files"]:
            found += [c for c in by_folder.get(os.path.realpath(f.parent), [])
                      if app["services"] is None or c["service"] in app["services"]]
        report[app_id] = {"state": summarize(found, app["files"]), "files": len(app["files"]),
                          "containers": [{k: c[k] for k in ("name", "service", "state", "status", "image")} for c in found]}
    return report


def parse_bytes(text):
    """'123.4MiB' -> bytes (docker stats' units)."""
    m = re.fullmatch(r"([\d.]+)\s*([KMGT]?i?B)", text.strip())
    if not m:
        return 0
    scale = {"B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
             "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4}
    return int(float(m.group(1)) * scale.get(m.group(2), 1))


def usage(apps):
    """Each app's share of the CPU (0-100, of the whole machine) and memory
    (bytes) right now, from one `docker stats` sample; containers that aren't
    part of an app add up under "other"."""
    result = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"],
                            env=docker_env(), stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=60, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "docker stats failed")
    owner = {}
    status = app_status(apps)
    for app_id, report in status.items():
        for c in report["containers"]:
            owner[c["name"]] = app_id
    cpus = os.cpu_count() or 1
    out = {app_id: {"cpu": 0.0, "memory": 0, "containers": 0} for app_id in apps}
    other = {"cpu": 0.0, "memory": 0, "containers": 0}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        name, cpu, mem = parts
        try:
            share = float(cpu.rstrip("%")) / cpus
        except ValueError:
            share = 0.0
        entry = out.get(owner.get(name), other)
        entry["cpu"] += share
        entry["memory"] += parse_bytes(mem.split("/")[0])
        entry["containers"] += 1
    for entry in [*out.values(), other]:
        entry["cpu"] = round(entry["cpu"], 2)
    return {"apps": out, "other": other}


# --------------------------------------------------------------- actions

def scoped(app, *args):
    """compose args for this app: its own services, when it shares its file."""
    return [*args, *(app["services"] or [])]


def pre_start(app):
    """Run the app's pre-start.sh like install.sh does; its exit code."""
    hook = app["folder"] / "pre-start.sh" if app["folder"] else None
    if not hook or not hook.is_file():
        return 0
    env = {**docker_env(), **read_env(app["folder"] / ".env"), "DOCKER": "docker"}
    say("$ ./pre-start.sh")
    return subprocess.run(["bash", "./pre-start.sh"], cwd=app["folder"], env=env,
                          stdin=subprocess.DEVNULL, check=False).returncode


def start(app):
    code = pre_start(app)
    if code == SKIP:
        say(f"{app['name']} isn't ready to start yet; the message above says why.")
        return SKIP
    if code:
        say(f"pre-start.sh failed ({code}), so {app['name']} wasn't started.")
        return code
    return first_failure(compose(f, *scoped(app, "up", "-d")) for f in app["files"])


def stop(app):
    return first_failure(compose(f, *scoped(app, "stop")) for f in reversed(app["files"]))


def restart(app):
    if not app_status({app["id"]: app})[app["id"]]["containers"]:
        say("No containers yet, so starting it instead.")
        return start(app)
    return first_failure(compose(f, *scoped(app, "restart")) for f in app["files"])


def update(app):
    """New images, then the containers recreated on them (only those that changed)."""
    code = first_failure(compose(f, *scoped(app, "pull")) for f in app["files"])
    if code:
        say(f"Pulling didn't finish ({code}); {app['name']} keeps running as it was.")
        return code
    return start(app)


def logs(app):
    """The last LOG_LINES lines of each compose file's containers, oldest first."""
    lines = []
    for f in app["files"]:
        result = subprocess.run(["docker", "compose", "-f", str(f), *scoped(app, "logs", "--no-color", "--timestamps",
                                                                            "--tail", str(LOG_LINES))],
                                cwd=f.parent, env=docker_env(), stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, errors="replace", timeout=60, check=False)
        lines += (result.stdout + result.stderr).splitlines()
    # Compose interleaves containers; sort by the timestamp after the "name | ".
    stamp = re.compile(r"^\S+\s+\|\s+(\S+)")
    lines.sort(key=lambda l: (m.group(1) if (m := stamp.match(l)) else ""))
    text = "\n".join(lines)
    if len(text) > LOG_BYTES:
        text = text[-LOG_BYTES:].split("\n", 1)[-1]
    return {"app": app["id"], "lines": text.splitlines()}


def remove_containers(app):
    if app["services"] is None:
        return first_failure(compose(f, "down") for f in reversed(app["files"]))
    # Only this app's services: the rest of its file belongs to other apps.
    return first_failure(compose(f, *scoped(app, "rm", "--stop", "--force")) for f in reversed(app["files"]))


def set_chosen(app_id, chosen):
    """Add an app to APPS in homelab.env, or take it out; catalog order."""
    current = set(read_env(CONFIG).get("APPS", "").split())
    current = current | {app_id} if chosen else current - {app_id}
    ordered = [a for _, a, _, _ in catalog() if a in current]
    line = f'APPS="{" ".join(ordered)}"'
    lines = CONFIG.read_text().splitlines() if CONFIG.exists() else []
    for i, existing in enumerate(lines):
        if existing.startswith("APPS="):
            lines[i] = line
            break
    else:
        lines.append(line)
    rewrite(CONFIG, "\n".join(lines) + "\n")


def set_imported_installed(app, installed):
    info = {**app["info"], "installed": installed}
    write_private(EXTRAS / app["id"] / "app.json", json.dumps(info, indent=2) + "\n")
    os.chmod(EXTRAS / app["id"] / "app.json", 0o644)


def delete(app):
    if app.get("core"):
        sys.exit(f"{app['name']} is a core app and always installed; stop it instead.")
    code = remove_containers(app)
    if code:
        say(f"Its containers didn't all come down ({code}), so {app['name']} stays installed.")
        return code
    if app["kind"] == "imported":
        set_imported_installed(app, False)
        say(f"{app['name']} is off your home screen. Install brings it back.")
        return 0
    set_chosen(app["id"], False)
    say(f"{app['name']} is out of APPS. Re-running install.sh to drop its address and dashboard entry:")
    return run_installer()


def install(app):
    if app["installed"]:
        sys.exit(f"{app['name']} is already installed.")
    if app["kind"] == "imported":
        set_imported_installed(app, True)
        return start({**app, "installed": True})
    set_chosen(app["id"], True)
    say(f"Added {app['name']} to APPS. install.sh sets it up and starts it:")
    return run_installer()


def first_failure(codes):
    """Run every step (a failed one doesn't stop the rest); the first error."""
    failed = 0
    for code in list(codes):
        failed = failed or code
    return failed


COMMANDS = {"start": start, "stop": stop, "restart": restart, "update": update, "delete": delete, "install": install}


# ---------------------------------------------------------------- import

def importable(path):
    """The real path of a compose file we may import, or an error."""
    real = Path(os.path.realpath(path))
    if not real.is_relative_to(HOME):
        return None, "only compose files under your home folder"
    if real.is_relative_to(OS_DATA.resolve()):
        return None, "not from the home screen's own data"
    if real.name not in COMPOSE_NAMES and not re.fullmatch(r"(docker-)?compose[\w.-]*\.ya?ml", real.name):
        return None, "not a compose file name"
    if not real.is_file():
        return None, "no such file"
    return real, None


def services(file):
    """[{name, image, ports, container, needs}] from `docker compose config`,
    which reads the file (and its .env) without starting anything."""
    result = subprocess.run(["docker", "compose", "-f", str(file), "config", "--format", "json"], cwd=file.parent,
                            env=docker_env(), stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=30, check=False)
    if result.returncode != 0:
        raise ValueError((result.stderr.strip().splitlines() or ["docker compose config failed"])[-1])
    config = json.loads(result.stdout)
    found = []
    for name, svc in (config.get("services") or {}).items():
        ports = sorted({int(p["published"]) for p in svc.get("ports") or []
                        if str(p.get("published", "")).isdigit()})
        needs = svc.get("depends_on") or {}
        found.append({"name": name, "image": svc.get("image") or "(built here)", "ports": ports,
                      "container": svc.get("container_name") or "", "needs": sorted(needs)})
    return found


def taken_services(real, apps):
    """{service: app name} already in adlerOS for this file; '*' for all of it."""
    taken = {}
    for app in apps.values():
        if any(os.path.realpath(f) == str(real) for f in app["files"]):
            for s in app["services"] or ["*"]:
                taken[s] = app["name"]
    return taken


def find_compose_files(start):
    if start.is_file():
        return [start]
    files, todo = [], [(start, 0)]
    while todo and len(files) < SCAN_MAX_FILES:
        folder, depth = todo.pop(0)
        try:
            entries = sorted(folder.iterdir())
        except OSError:
            continue
        own = compose_file(folder)
        if own:
            files.append(own)
        if depth < SCAN_DEPTH:
            todo += [(e, depth + 1) for e in entries
                     if e.is_dir() and not e.is_symlink() and not e.name.startswith(".") and e.name not in SKIP_DIRS]
    return files


def scan(path):
    start = Path(os.path.realpath(path))
    if not start.is_relative_to(HOME):
        return {"error": f"Pick a folder inside your home folder ({HOME})."}
    if not start.exists():
        return {"error": f"{path} doesn't exist."}
    apps = every_app()
    report, shown = [], 0
    for f in find_compose_files(start):
        real, error = importable(f)
        entry = {"path": str(f), "folder": f.parent.name, "taken": {}, "already": None}
        if error:
            entry["error"] = error
            report.append(entry)
            continue
        taken = taken_services(real, apps)
        try:
            text = real.read_text(errors="replace")
            if shown + len(text) <= SHOW_TOTAL and len(text) <= SHOW_BYTES:
                entry["text"] = text
                shown += len(text)
            entry["services"] = services(real)
        except (OSError, ValueError, subprocess.TimeoutExpired) as e:
            entry["error"] = f"can't read it: {e}"
        names = {s["name"] for s in entry.get("services", [])}
        if "*" in taken:
            taken = {s: taken["*"] for s in names}
        entry["taken"] = taken
        if names and names <= set(taken):
            entry["already"] = ", ".join(sorted(set(taken.values())))
        report.append(entry)
    return {"files": report, "home": str(HOME)}


def slug(name):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", name.lower())).strip("-")[:40] or "app"


def import_app(name, file, service_list, url, icon, port):
    real, error = importable(file)
    if error:
        sys.exit(f"{file}: {error}")
    if not re.fullmatch(r"[^\x00-\x1f]{1,40}", name):
        sys.exit("name: 1 to 40 characters")
    if not re.fullmatch(r"https?://[^\s\"'<>\\]{1,300}", url):
        sys.exit("address: an http:// or https:// address")
    if icon and not re.fullmatch(r"di:[a-z0-9-]{1,64}", icon):
        sys.exit("icon: di:<name> from dashboard-icons, or nothing")
    if port and not (port.isdigit() and 0 < int(port) < 65536):
        sys.exit("port: a number from 1 to 65535, or nothing")
    wanted = service_list.split(",")
    if not all(SERVICE.fullmatch(s) for s in wanted) or len(set(wanted)) != len(wanted):
        sys.exit("services: the app's service first, then the ones it needs, separated by commas")
    try:
        found = {s["name"] for s in services(real)}
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        sys.exit(f"can't read {file}: {e}")
    missing = [s for s in wanted if s not in found]
    if missing:
        sys.exit(f"{file} has no service called {', '.join(missing)}")
    apps = every_app()
    taken = taken_services(real, apps)
    clash = sorted(s for s in wanted if s in taken or "*" in taken)
    if clash:
        owner = taken.get(clash[0]) or taken.get("*")
        sys.exit(f"{', '.join(clash)} in {file} already belong to {owner} in adlerOS")
    catalog_ids = {app_id for _, app_id, _, _ in catalog()}
    base = app_id = slug(name)
    n = 2
    while app_id in apps or app_id in catalog_ids or (EXTRAS / app_id).exists():
        app_id = f"{base}-{n}"
        n += 1
    folder = EXTRAS / app_id
    folder.mkdir(parents=True, mode=0o755)
    info = {"name": name, "files": [str(real)],
            # All of the file: none listed, so it runs as a whole (down, not rm).
            "services": None if set(wanted) == found else wanted,
            "url": url, "icon": icon, "port": int(port) if port else None,
            "about": f"Imported from {real.parent}", "imported": time.strftime("%Y-%m-%d"), "installed": True}
    (folder / "app.json").write_text(json.dumps(info, indent=2) + "\n")
    part = "" if info["services"] is None else f" (services: {', '.join(wanted)})"
    say(f"Imported {name} as {app_id}: {real}{part}")
    return 0


def forget(app_id):
    app = imported_app(app_id) if APP_ID.fullmatch(app_id) else None
    if not app:
        sys.exit(f"{app_id}: not an imported app")
    folder = EXTRAS / app_id
    (folder / "app.json").unlink()
    try:
        folder.rmdir()
    except OSError:
        pass  # something else of yours is in there: left alone
    say(f"{app['name']} is no longer in adlerOS. Its containers and files weren't touched.")
    return 0


def main(argv):
    if len(argv) == 2 and argv[0] == "scan":
        print(json.dumps(scan(argv[1])))
        return 0
    if len(argv) == 7 and argv[0] == "import":
        return import_app(*argv[1:])
    if len(argv) == 2 and argv[0] == "forget":
        return forget(argv[1])
    if len(argv) == 1 and argv[0] == "usage":
        try:
            print(json.dumps(usage(all_apps())))
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as e:
            print(json.dumps({"error": f"can't read Docker: {e}", "apps": {}}))
        return 0
    if len(argv) == 2 and argv[0] == "logs" and APP_ID.fullmatch(argv[1]):
        app = all_apps().get(argv[1])
        if not app:
            print(json.dumps({"error": f"{argv[1]} isn't an installed app", "lines": []}))
            return 0
        try:
            print(json.dumps(logs(app)))
        except (OSError, subprocess.TimeoutExpired) as e:
            print(json.dumps({"error": f"can't read the logs: {e}", "lines": []}))
        return 0
    if len(argv) == 1 and argv[0] == "status":
        try:
            report = app_status(all_apps())
        except (OSError, RuntimeError) as e:
            print(json.dumps({"error": f"can't read Docker: {e}", "apps": {}}))
            return 0
        print(json.dumps({"apps": report}))
        return 0
    if len(argv) != 2 or argv[0] not in COMMANDS or not APP_ID.fullmatch(argv[1]):
        sys.exit(f"usage: apps.py status | usage | logs APP | {{{'|'.join(COMMANDS)}}} APP | scan PATH | forget APP"
                 " | import NAME FILE SERVICES URL ICON PORT")
    app = every_app().get(argv[1])
    if not app:
        sys.exit(f"{argv[1]}: not an app the App Store manages")
    if argv[0] != "install" and not app["installed"]:
        sys.exit(f"{app['name']} isn't installed; install it first.")
    if not app["files"]:
        sys.exit(f"{app['name']}: no compose file found")
    return COMMANDS[argv[0]](app)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
