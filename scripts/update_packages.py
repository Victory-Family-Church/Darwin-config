#!/usr/bin/env python3
"""
Manage packages.json (version/url/sha256) for the NC production nix-darwin
repo, so overlays/production-apps.nix picks up changes without
hand-editing Nix.

Bulk update everything with an automatic strategy:
    python3 scripts/update_packages.py sync
    python3 scripts/update_packages.py sync --dry-run

List every package (name, kind, version, strategy, and whether it still
needs a manual URL):
    python3 scripts/update_packages.py list-all

Manage one package at a time:
    python3 scripts/update_packages.py pkg add <name> <kind> <version> <url> [options]
    python3 scripts/update_packages.py pkg update <name> [version] [url]
    python3 scripts/update_packages.py pkg info <name>
    python3 scripts/update_packages.py pkg delete <name>
    python3 scripts/update_packages.py pkg revert <name> <commit>

    (aliases: add=a, update=u, info=i, delete=d, revert=r)

`pkg update <name>` with no version/url guesses the latest upstream
version/url the same way `sync` would, using that package's `update.strategy`
in packages.json. Give it just a URL (`pkg update <name> <url>`) to guess
the version from the filename instead. For "manual-local" packages (no URL
at all -- see vendor/README.md) pass just the new version instead:
`pkg update <name> <version>` rehashes whatever's already sitting at that
package's localPath.

`pkg info` and `pkg revert` read git history for packages.json, so they only
work once this repo is an actual git checkout with some commits behind it.

One-time provisioning for "manual-local"/"external" vendor installers
(grandMA3 onPC, Blackmagic Desktop Video/ATEM Software Control, Dante
Virtual Soundcard, Spotify -- all too large or too access-gated to fetch
or commit to git, see vendor/README.md):
    python3 scripts/update_packages.py provision --staging ~/Downloads
    python3 scripts/update_packages.py provision --status

Copies each one from --staging into its fixed system path (creating
directories as needed) and verifies it against packages.json's
localSha256, or with --status just reports what's already in place vs.
still missing/mismatched. This is also exposed as a flake app:
`nix run .#provision-vendor -- --staging ~/Downloads`.

Only the Python standard library is used (urllib, hashlib, json, re,
subprocess, xml.etree) so this runs anywhere Python 3.8+ is available -- no
`pip install` needed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
PACKAGES_JSON = ROOT / "packages.json"
PACKAGES_JSON_REL = "packages.json"

USER_AGENT = "nc-production-nix-darwin-updater/1.0"

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def http_get(url: str) -> tuple[bytes, str]:
    """GET url, following redirects. Returns (body, final_url)."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read(), resp.geturl()


def http_head_location(url: str) -> str:
    """Resolve a redirecting URL to its final destination without
    downloading the (often large) body -- used for vendor "latest"
    redirect links."""

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        resp = opener.open(req, timeout=30)
        return resp.geturl()
    except urllib.error.HTTPError as e:
        location = e.headers.get("Location")
        if location:
            return location
        raise


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sparkle_latest(xml_bytes: bytes) -> tuple[str, str]:
    """Parse a Sparkle-style appcast and return (version, enclosure_url)
    for the first <item>."""
    root = ElementTree.fromstring(xml_bytes)
    item = root.find(".//item")
    if item is None:
        raise RuntimeError("no <item> found in appcast")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise RuntimeError("no <enclosure> found in appcast item")
    version = enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString") or enclosure.get(
        f"{{{SPARKLE_NS}}}version"
    )
    url = enclosure.get("url")
    if not (version and url):
        raise RuntimeError("appcast enclosure missing version/url attributes")
    return version, url


# ---------------------------------------------------------------------------
# Per-vendor update strategies.
# Each takes the package's dict (from packages.json) and returns
# (new_version, new_url). Raise on failure -- the caller reports and skips.
# ---------------------------------------------------------------------------

def strategy_propresenter(pkg):
    api = (
        "https://api.renewedvision.com/v1/pro/upgrade"
        "?platform=macos&osVersion=99&appVersion=0&buildNumber=0&includeNotes=0"
    )
    body, _ = http_get(api)
    data = json.loads(body)
    upgrades = data.get("upgrades") or []
    if not upgrades:
        raise RuntimeError("no upgrades returned by renewedvision API")
    latest = upgrades[0]
    version = f'{latest["version"]},{latest["buildNumber"]}'
    url = (
        "https://renewedvision.com/downloads/propresenter/mac/"
        f'ProPresenter_{latest["version"]}_{latest["buildNumber"]}.zip'
    )
    return version, url


def strategy_ms_office_fwlink(pkg):
    linkid = pkg["update"]["linkid"]
    prefix = pkg["update"]["filenamePrefix"]
    final_url = http_head_location(f"https://go.microsoft.com/fwlink/p/?linkid={linkid}")
    m = re.search(rf"{re.escape(prefix)}([0-9.]+)_Installer\.pkg", final_url)
    if not m:
        raise RuntimeError(f"couldn't parse version out of {final_url}")
    return m.group(1), final_url


def strategy_dropbox(pkg):
    final_url = http_head_location(
        "https://www.dropbox.com/download?plat=mac&full=1&arch=arm64"
    )
    m = re.search(r"Dropbox%20([0-9.]+)", final_url)
    if not m:
        raise RuntimeError(f"couldn't parse version out of {final_url}")
    return m.group(1), final_url


def strategy_spotify(pkg):
    # Spotify's macOS build is an unversioned rolling download with no
    # vendor-published hash (Homebrew marks it `sha256 :no_check`). Just
    # re-download and re-hash; "rolling" is the best we can say for version.
    return "rolling", "https://download.scdn.co/SpotifyARM64.dmg"


def strategy_reaper(pkg):
    body, _ = http_get("https://www.cockos.com/reaper/latestversion/?p=osx_64")
    text = body.decode().strip()
    m = re.search(r"v?(\d+(?:\.\d+)+)", text)
    if not m:
        raise RuntimeError(f"couldn't parse version out of '{text}'")
    version = m.group(1)
    parts = version.split(".")
    major = parts[0]
    major_minor_nodots = "".join(parts[:2])
    url = f"https://dlcf.reaper.fm/{major}.x/reaper{major_minor_nodots}_universal.dmg"
    return version, url


def strategy_wireless_workbench(pkg):
    final_url = http_head_location("https://www.shure.com/en-US/sw/wwb-mac")
    m = re.search(r"Wireless-Workbench-macOS-([0-9.]+)\.pkg", final_url)
    if not m:
        raise RuntimeError(f"couldn't parse version out of {final_url}")
    return m.group(1), final_url


def strategy_dante_controller(pkg):
    body, _ = http_get(
        "https://audinate.jfrog.io/artifactory/ad8-software-updates-prod/"
        "DanteController/appcast/DanteController-apple_silicon.xml"
    )
    return sparkle_latest(body)


def strategy_sparkle_appcast(pkg):
    cfg = pkg["update"]
    body, _ = http_get(cfg["appcastUrl"])
    version, url = sparkle_latest(body)
    if "urlTemplate" in cfg:
        url = cfg["urlTemplate"].format(version=version)
    return version, url


def strategy_teamviewer(pkg):
    # macupdates.xml wants a "current" version to ask "anything newer than
    # this?" -- probe with 0.0.0 to just get the latest back.
    probe = (
        "https://download.teamviewer.com/download/update/macupdates.xml"
        "?id=0&lang=en&version=0.0.0&os=macos&osversion=14.0&type=1&channel=1"
    )
    body, _ = http_get(probe)
    return sparkle_latest(body)


def strategy_github_release(pkg):
    cfg = pkg["update"]
    repo = cfg["repo"]
    asset_pattern = cfg.get("assetPattern", r"\.pkg$")
    body, _ = http_get(f"https://api.github.com/repos/{repo}/releases/latest")
    data = json.loads(body)
    asset = next(
        (a for a in data.get("assets", []) if re.search(asset_pattern, a["name"])), None
    )
    if asset is None:
        raise RuntimeError(f"no release asset matching '{asset_pattern}' found for {repo}")
    m = re.search(r"[0-9]+(?:[._-][0-9]+)+", asset["name"])
    version = m.group(0) if m else data.get("tag_name", "unknown").lstrip("v")
    return version, asset["browser_download_url"]


STRATEGIES = {
    "propresenter": strategy_propresenter,
    "ms_office_fwlink": strategy_ms_office_fwlink,
    "dropbox": strategy_dropbox,
    "spotify": strategy_spotify,
    "reaper": strategy_reaper,
    "github_release": strategy_github_release,
    "wireless_workbench": strategy_wireless_workbench,
    "dante_controller": strategy_dante_controller,
    "sparkle_appcast": strategy_sparkle_appcast,
    "teamviewer": strategy_teamviewer,
}


# ---------------------------------------------------------------------------
# Manifest I/O
# ---------------------------------------------------------------------------

def load_manifest():
    return json.loads(PACKAGES_JSON.read_text())


def save_manifest(manifest):
    PACKAGES_JSON.write_text(json.dumps(manifest, indent=2) + "\n")


def find_pkg(manifest, name):
    return next((p for p in manifest["packages"] if p["name"] == name), None)


# ---------------------------------------------------------------------------
# Git helpers (for `pkg info` / `pkg revert`)
# ---------------------------------------------------------------------------

def run_git(args):
    try:
        result = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
        )
    except FileNotFoundError:
        raise RuntimeError("git is not installed")
    except subprocess.CalledProcessError as e:
        raise RuntimeError((e.stderr or e.stdout or "").strip() or f"git {' '.join(args)} failed")
    return result.stdout


def is_git_repo():
    try:
        run_git(["rev-parse", "--is-inside-work-tree"])
        return True
    except RuntimeError:
        return False


def packages_json_history():
    """[(commit_hash, date)] touching packages.json, newest first."""
    out = run_git(
        ["log", "--follow", "--pretty=format:%H|%ad", "--date=short", "--", PACKAGES_JSON_REL]
    )
    history = []
    for line in out.splitlines():
        if not line.strip():
            continue
        h, d = line.split("|", 1)
        history.append((h, d))
    return history


def package_at_commit(commit, name):
    """The full package dict for `name` as it existed in packages.json at
    `commit`, or None if the file/package didn't exist there."""
    try:
        blob = run_git(["show", f"{commit}:{PACKAGES_JSON_REL}"])
    except RuntimeError:
        return None
    try:
        data = json.loads(blob)
    except json.JSONDecodeError:
        return None
    return find_pkg(data, name)


# ---------------------------------------------------------------------------
# `sync` -- bulk update every automatic-strategy package
# ---------------------------------------------------------------------------

def sync_one(pkg, dry_run):
    strategy_name = pkg["update"]["strategy"]

    if strategy_name == "manual":
        print(f"-  {pkg['name']}: manual strategy, skipping (use 'pkg update {pkg['name']} <url>')")
        return False

    if strategy_name == "manual-local":
        print(
            f"-  {pkg['name']}: manual-local strategy, skipping -- this one lives at "
            f"{pkg.get('localPath', '?')} in the repo, not a URL. See vendor/README.md."
        )
        return False

    fn = STRATEGIES.get(strategy_name)
    if fn is None:
        print(f"!  {pkg['name']}: unknown update strategy '{strategy_name}', skipping")
        return False

    print(f".. {pkg['name']}: checking for updates...")
    try:
        new_version, new_url = fn(pkg)
    except Exception as e:
        print(f"!  {pkg['name']}: failed to check latest version: {e}")
        return False

    if new_version == pkg["version"] and new_url == pkg["url"]:
        print(f"=  {pkg['name']}: already up to date ({pkg['version']})")
        return False

    print(f".. {pkg['name']}: downloading {new_url}")
    try:
        data, _ = http_get(new_url)
    except Exception as e:
        print(f"!  {pkg['name']}: download failed: {e}")
        return False

    new_hash = sha256_of(data)

    if new_hash == pkg["sha256"] and new_version == pkg["version"]:
        print(f"=  {pkg['name']}: hash unchanged, nothing to do")
        return False

    print(f"+  {pkg['name']}: {pkg['version']} -> {new_version}")
    if not dry_run:
        pkg["version"] = new_version
        pkg["url"] = new_url
        pkg["sha256"] = new_hash
    return True


def cmd_sync(args):
    manifest = load_manifest()
    changed = False
    for pkg in manifest["packages"]:
        if sync_one(pkg, args.dry_run):
            changed = True

    if changed and not args.dry_run:
        save_manifest(manifest)
        print("\npackages.json updated. Review the diff, then commit it.")
    elif args.dry_run:
        print("\n(dry run -- packages.json not written)")
    else:
        print("\nNo changes.")


def cmd_list_all(args):
    manifest = load_manifest()
    packages = manifest["packages"]
    if not packages:
        print("packages.json has no packages.")
        return

    name_w = max(len("NAME"), max(len(p["name"]) for p in packages))
    kind_w = max(len("KIND"), max(len(p["kind"]) for p in packages))
    version_w = max(len("VERSION"), max(len(p["version"]) for p in packages))
    strategy_w = max(len("STRATEGY"), max(len(p["update"]["strategy"]) for p in packages))

    def row(name, kind, version, strategy, note):
        return f"{name:<{name_w}}  {kind:<{kind_w}}  {version:<{version_w}}  {strategy:<{strategy_w}}  {note}"

    header = row("NAME", "KIND", "VERSION", "STRATEGY", "NOTE")
    print(header)
    print("-" * len(header))

    manual_count = 0
    local_count = 0
    placeholder_count = 0
    for p in sorted(packages, key=lambda p: p["name"]):
        strategy = p["update"]["strategy"]
        is_placeholder = p.get("url") == "REPLACE_ME" or p["version"] == "REPLACE_ME"
        if strategy == "manual":
            manual_count += 1
        if strategy == "manual-local":
            local_count += 1
        if is_placeholder:
            placeholder_count += 1
        if strategy == "manual-local":
            where = p.get("localPath", "?")
            if is_placeholder:
                note = f"NEEDS {where} (see vendor/README.md)"
            elif not p.get("localSha256"):
                note = f"local: {where} (no hash yet -- pkg update {p['name']} <version>)"
            else:
                note = f"local: {where}"
        elif is_placeholder:
            note = "NEEDS pkg update <name> <url>"
        elif strategy == "manual":
            note = "manual"
        else:
            note = ""
        print(row(p["name"], p["kind"], p["version"], strategy, note))

    print(
        f"\n{len(packages)} packages -- {manual_count} manual-strategy, "
        f"{local_count} local (vendor/), {placeholder_count} still REPLACE_ME."
    )


# ---------------------------------------------------------------------------
# `provision` -- one-time setup for manual-local vendor installers
# ---------------------------------------------------------------------------

def sha256_of_path(path: Path):
    """sha256 of a file, or None for a directory (e.g. an .app bundle --
    installer-app packages like Spotify are a whole bundle, not a single
    file, and there's no single-file hash to compute)."""
    if path.is_dir():
        return None
    return sha256_of(path.read_bytes())


def copy_path(src: Path, dst: Path):
    """Copy a file or a whole directory tree (e.g. an .app bundle)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)


def cmd_provision(args):
    manifest = load_manifest()
    packages = [p for p in manifest["packages"] if p["update"]["strategy"] == "manual-local"]

    if not packages:
        print("No manual-local packages in packages.json -- nothing to provision.")
        return

    staging = None
    if args.staging:
        staging = Path(args.staging).expanduser()
        if not staging.is_dir():
            print(f"error: staging directory '{staging}' doesn't exist or isn't a directory")
            sys.exit(1)

    ok, missing, mismatched = [], [], []

    for pkg in packages:
        local_path_str = pkg.get("localPath")
        if not local_path_str:
            continue
        # ROOT / <absolute string> just returns the absolute path as-is
        # (standard pathlib behavior) -- this correctly handles both
        # kindDetail "local" (repo-relative) and "external" (absolute)
        # without needing to know which one we're looking at.
        target = ROOT / local_path_str
        expected_hash = pkg.get("localSha256")

        if not target.exists() and staging and not args.status:
            candidate = staging / target.name
            if candidate.exists():
                print(f".. copying {candidate} -> {target}")
                copy_path(candidate, target)

        if not target.exists():
            missing.append((pkg["name"], str(target), pkg.get("homepage", "")))
            continue

        actual_hash = sha256_of_path(target)
        if actual_hash is None:
            # Directory (.app bundle, e.g. Spotify's installer-app) -- no
            # single-file hash possible, so just existing at the right
            # path is the whole integrity check.
            ok.append((pkg["name"], str(target), None, expected_hash))
        elif expected_hash and actual_hash != expected_hash:
            mismatched.append((pkg["name"], str(target), expected_hash, actual_hash))
        else:
            ok.append((pkg["name"], str(target), actual_hash, expected_hash))

    print(f"OK ({len(ok)}):")
    for name, target, actual_hash, expected_hash in ok:
        print(f"  {name:<28} {target}")
        if actual_hash is None:
            print("      directory (.app bundle) -- no single-file hash to track, path presence is the check")
        elif not expected_hash:
            print(
                f"      no localSha256 recorded yet -- run: "
                f"pkg update {name} <version>  (this file's sha256 is {actual_hash[:16]}...)"
            )

    if mismatched:
        print(f"\nMISMATCH ({len(mismatched)}) -- wrong file at that path:")
        for name, target, expected, actual in mismatched:
            print(f"  {name:<28} {target}")
            print(f"      expected sha256 {expected}")
            print(f"      actual   sha256 {actual}")

    if missing:
        print(f"\nMISSING ({len(missing)}):")
        for name, target, homepage in missing:
            print(f"  {name:<28} {target}")
            if homepage:
                print(f"      get it from: {homepage}")

    print()
    if missing or mismatched:
        print(
            f"{len(missing)} missing, {len(mismatched)} mismatched -- "
            f"not ready for darwin-rebuild on this host yet."
        )
        sys.exit(1)
    else:
        print(f"All {len(ok)} manual-local packages are in place and verified.")


# ---------------------------------------------------------------------------
# `pkg add|update|info|delete|revert`
# ---------------------------------------------------------------------------

def cmd_pkg_add(args):
    manifest = load_manifest()
    if find_pkg(manifest, args.name) is not None:
        print(f"error: '{args.name}' already exists in packages.json -- use 'pkg update {args.name}' instead")
        sys.exit(1)

    if args.kind in ("dmg", "zip") and not args.app_name:
        print(f"error: --app-name is required for kind '{args.kind}' (e.g. --app-name 'Foo.app')")
        sys.exit(1)
    if args.kind == "pkg" and not args.pkg_id:
        print(
            "error: --pkg-id is required for kind 'pkg' "
            "(the identifier pkgutil should check for, e.g. com.vendor.pkg.Foo)"
        )
        sys.exit(1)

    if args.sha256:
        sha256 = args.sha256
    else:
        print(f".. downloading {args.url} to compute sha256 (pass --sha256 to skip this)")
        data, _ = http_get(args.url)
        sha256 = sha256_of(data)

    entry = {
        "name": args.name,
        "kind": args.kind,
        "version": args.version,
        "url": args.url,
        "sha256": sha256,
        "update": {"strategy": args.strategy},
    }
    if args.kind in ("dmg", "zip"):
        entry["appName"] = args.app_name
    else:
        entry["pkgId"] = args.pkg_id
    if args.homepage:
        entry["homepage"] = args.homepage
    if args.note:
        entry["note"] = args.note

    manifest["packages"].append(entry)
    save_manifest(manifest)
    print(f"added '{args.name}' {args.version} ({args.kind}) sha256={sha256}")
    print(
        f'Now add "{args.name}" to production.macApps.apps in the relevant '
        "modules/roles/*.nix (or modules/common.nix) to actually install it on a host."
    )


def update_manual_local(manifest, pkg, version):
    """`pkg update <name> <version>` for a manual-local package: rehash the
    file already sitting at pkg['localPath'] and record version +
    localSha256. There's no download here -- the vendor file is expected
    to already be in place (see vendor/README.md)."""
    local_path = ROOT / pkg["localPath"]
    if not local_path.exists():
        print(
            f"error: {local_path} doesn't exist yet -- save the installer there first, "
            f"then re-run this (see vendor/README.md)"
        )
        sys.exit(1)

    new_hash = sha256_of_path(local_path)
    old_version = pkg["version"]
    pkg["version"] = version
    if new_hash is None:
        # Directory (.app bundle) -- no single-file hash possible. Drop
        # any stale localSha256 rather than leave a misleading one behind.
        pkg.pop("localSha256", None)
        save_manifest(manifest)
        print(f"updated '{pkg['name']}': {old_version} -> {version}  (directory -- no hash tracked)")
    else:
        pkg["localSha256"] = new_hash
        save_manifest(manifest)
        print(f"updated '{pkg['name']}': {old_version} -> {version}  (localSha256={new_hash[:12]}...)")
    # NB: `local_path` (ROOT / pkg["localPath"]) is always absolute -- ROOT
    # itself is absolute, so that alone can't tell "external" apart from
    # "local". Check the *original* string instead.
    if pkg["localPath"].startswith("/"):
        print(
            f"{pkg['localPath']} is an external path -- not part of git, nothing to add/commit "
            f"there. Just don't forget to `git add packages.json` for this version/hash update."
        )
    else:
        print(f"Don't forget to `git add {pkg['localPath']}` if you haven't already.")


def cmd_pkg_update(args):
    manifest = load_manifest()
    pkg = find_pkg(manifest, args.name)
    if pkg is None:
        print(f"error: no package named '{args.name}' in packages.json -- use 'pkg add' first")
        sys.exit(1)

    version_arg, url_arg = args.version, args.url

    # Allow `pkg update NAME <url>` (a single positional that's a URL) --
    # argparse would otherwise bind it to `version`.
    if version_arg and not url_arg and re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", version_arg):
        version_arg, url_arg = None, version_arg

    if pkg["update"]["strategy"] == "manual-local":
        if url_arg:
            print(
                f"error: '{args.name}' is manual-local -- there's no URL to fetch, so a URL "
                f"argument doesn't apply. Overwrite {pkg.get('localPath', '?')} with the new "
                f"installer yourself, then run: pkg update {args.name} <version>"
            )
            sys.exit(1)
        if not version_arg:
            print(
                f"error: pass the new version: pkg update {args.name} <version> "
                f"(after saving the new installer at {pkg.get('localPath', '?')})"
            )
            sys.exit(1)
        update_manual_local(manifest, pkg, version_arg)
        return

    if version_arg and not url_arg:
        print(
            "error: a version alone isn't enough. Pass both <version> <url>, "
            "just <url> (version is guessed from the filename), or neither "
            "(latest is auto-detected)."
        )
        sys.exit(1)

    old_version = pkg["version"]

    if url_arg:
        new_url = url_arg
        new_version = version_arg  # may be None -> guess from filename below
    else:
        # Nothing given -- try to guess the latest upstream version/url,
        # the same way `sync` does.
        strategy_name = pkg["update"]["strategy"]
        if strategy_name == "manual":
            print(
                f"error: '{args.name}' has no automatic update strategy "
                "(vendor requires a manual/gated download)."
            )
            print(
                f"Supply the URL yourself: pkg update {args.name} <url>  "
                f"(or  pkg update {args.name} <version> <url>)"
            )
            sys.exit(1)
        fn = STRATEGIES.get(strategy_name)
        if fn is None:
            print(f"error: unknown update strategy '{strategy_name}' for '{args.name}'")
            sys.exit(1)
        print(f".. guessing latest upstream version/url for '{args.name}' (strategy={strategy_name})...")
        try:
            new_version, new_url = fn(pkg)
        except Exception as e:
            print(f"error: couldn't determine the latest version automatically: {e}")
            sys.exit(1)

    print(f".. downloading {new_url}")
    data, final_url = http_get(new_url)
    new_hash = sha256_of(data)

    if new_version is None:
        filename = final_url.rsplit("/", 1)[-1]
        m = re.search(r"[0-9]+(?:[._][0-9]+)+", filename)
        new_version = m.group(0).replace("_", ".") if m else old_version
        print(f"   (guessed version '{new_version}' from filename -- fix in packages.json if wrong)")

    pkg["version"] = new_version
    pkg["url"] = new_url
    pkg["sha256"] = new_hash
    save_manifest(manifest)
    print(f"updated '{args.name}': {old_version} -> {new_version}  ({new_hash[:12]}...)")


def cmd_pkg_info(args):
    manifest = load_manifest()
    pkg = find_pkg(manifest, args.name)
    if pkg is None:
        print(f"error: no package named '{args.name}' in packages.json")
        sys.exit(1)

    print(f"{pkg['name']}  (kind={pkg['kind']}, strategy={pkg['update']['strategy']})")
    print(f"  current version: {pkg['version']}")
    print(f"  current url:     {pkg['url']}")
    print(f"  current sha256:  {pkg['sha256']}")

    if not is_git_repo():
        print("\n(not a git repository -- no version history available)")
        return

    try:
        history = packages_json_history()
    except RuntimeError as e:
        print(f"\n(couldn't read git history: {e})")
        return

    if not history:
        print("\n(packages.json has no git history yet)")
        return

    print("\nVersion history (most recent commit for each distinct version, newest first):")
    sentinel = object()
    last_version = sentinel
    rows = []
    for commit, date in history:
        p = package_at_commit(commit, args.name)
        version = p["version"] if p else "(not present)"
        if version != last_version:
            rows.append((commit[:10], date, version, p["url"] if p else ""))
            last_version = version

    for commit, date, version, url in rows:
        print(f"  {commit}  {date}  {version:<20} {url}")

    print(f"\nRevert with: python3 {Path(__file__).name} pkg revert {args.name} <commit-hash>")


def cmd_pkg_delete(args):
    manifest = load_manifest()
    pkg = find_pkg(manifest, args.name)
    if pkg is None:
        print(f"error: no package named '{args.name}' in packages.json")
        sys.exit(1)

    manifest["packages"] = [p for p in manifest["packages"] if p["name"] != args.name]
    save_manifest(manifest)
    print(f"deleted '{args.name}' from packages.json")
    print(
        "Don't forget to remove it from production.macApps.apps in any "
        "modules/roles/*.nix or modules/common.nix that referenced it."
    )


def cmd_pkg_revert(args):
    if not is_git_repo():
        print("error: not a git repository -- nothing to revert from")
        sys.exit(1)

    try:
        old = package_at_commit(args.commit, args.name)
    except RuntimeError as e:
        print(f"error: {e}")
        sys.exit(1)

    if old is None:
        print(f"error: package '{args.name}' not found in packages.json at commit {args.commit}")
        sys.exit(1)

    manifest = load_manifest()
    pkg = find_pkg(manifest, args.name)
    if pkg is None:
        print(f"'{args.name}' isn't in the current packages.json -- adding it back from {args.commit[:10]}")
        manifest["packages"].append(old)
    else:
        idx = manifest["packages"].index(pkg)
        manifest["packages"][idx] = old

    save_manifest(manifest)
    print(f"reverted '{args.name}' to its state as of {args.commit[:10]}: version={old['version']}")


# ---------------------------------------------------------------------------
# CLI wiring
# ---------------------------------------------------------------------------

def build_parser():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    top = parser.add_subparsers(dest="command", required=True)

    p_sync = top.add_parser("sync", help="bulk-update every package with an automatic strategy")
    p_sync.add_argument("--dry-run", action="store_true", help="show what would change without writing")
    p_sync.set_defaults(func=cmd_sync)

    p_list_all = top.add_parser(
        "list-all", help="list every package in packages.json with kind/version/strategy"
    )
    p_list_all.set_defaults(func=cmd_list_all)

    p_provision = top.add_parser(
        "provision",
        help="one-time setup: copy/verify manual-local vendor installers into their fixed paths",
    )
    p_provision.add_argument(
        "--staging",
        metavar="DIR",
        help="directory containing downloaded installers to copy in (matched by filename)",
    )
    p_provision.add_argument(
        "--status", action="store_true", help="only report status, don't copy anything"
    )
    p_provision.set_defaults(func=cmd_provision)

    p_pkg = top.add_parser("pkg", help="add/update/inspect/delete/revert a single package")
    pkg_sub = p_pkg.add_subparsers(dest="pkg_command", required=True)

    p_add = pkg_sub.add_parser("add", aliases=["a"], help="add a brand-new package")
    p_add.add_argument("name")
    p_add.add_argument("kind", choices=["dmg", "zip", "pkg"])
    p_add.add_argument("version")
    p_add.add_argument("url")
    p_add.add_argument("--sha256", help="skip downloading; use this hash directly")
    p_add.add_argument("--app-name", help="required for kind=dmg/zip, e.g. 'Foo.app'")
    p_add.add_argument("--pkg-id", help="required for kind=pkg, the pkgutil identifier")
    p_add.add_argument("--homepage")
    p_add.add_argument("--note")
    p_add.add_argument(
        "--strategy",
        default="manual",
        help="update.strategy to record in packages.json (default: manual)",
    )
    p_add.set_defaults(func=cmd_pkg_add)

    p_update = pkg_sub.add_parser(
        "update", aliases=["u"], help="update version/url/sha256 of an existing package"
    )
    p_update.add_argument("name")
    p_update.add_argument(
        "version",
        nargs="?",
        help="omit (with url) to auto-detect the latest release; or pass a URL here alone",
    )
    p_update.add_argument("url", nargs="?")
    p_update.set_defaults(func=cmd_pkg_update)

    p_info = pkg_sub.add_parser(
        "info", aliases=["i"], help="show current + git version history for a package"
    )
    p_info.add_argument("name")
    p_info.set_defaults(func=cmd_pkg_info)

    p_delete = pkg_sub.add_parser("delete", aliases=["d"], help="remove a package")
    p_delete.add_argument("name")
    p_delete.set_defaults(func=cmd_pkg_delete)

    p_revert = pkg_sub.add_parser(
        "revert", aliases=["r"], help="restore a package to its state at a given git commit"
    )
    p_revert.add_argument("name")
    p_revert.add_argument("commit")
    p_revert.set_defaults(func=cmd_pkg_revert)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
