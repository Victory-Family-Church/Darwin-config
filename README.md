# nc-production-nix-darwin

nix-darwin flake for the four NC production Mac Minis (M4):

| Hostname | Username | Role |
|---|---|---|
| `NC-Production-Main-CG-1` | `CG-1` | Main service presentation (ProPresenter + Decklink) |
| `NC-Production-Main-CG-2` | `CG-2` | Front of House audio |
| `NC-Production-Main-CG-3` | `CG-3` | Lighting (grandMA3 onPC) |
| `NC-Production-NextGen-CG-1` | `CG-1` | Student ministry (SA) presentation |

All app installs are plain Nix -- there is **no Homebrew dependency**. Every
vendor app is defined once in `packages.json` and built by the in-repo
overlay at `overlays/production-apps.nix`.

## Repo layout

```
flake.nix                       darwinConfigurations for the 4 hosts
packages.json                   version/url/sha256 for every vendor app (source of truth)
lib/mac-apps.nix                builders: extract an .app from .dmg/.zip, wrap a .pkg
lib/mk-wallpaper.nix            builds a wallpaper PNG: bg color + optional logo + hostname text
overlays/production-apps.nix    reads packages.json -> exposes pkgs.macApps.<name>
assets/                         drop assets/logo.png here to have it composited into the wallpaper
modules/
  common.nix                   hostname/computer name, nix settings, apps every Mac gets
  cg-account.nix                parameterized CG-* user account (admin + autologin)
  mac-app-activation.nix        installs pkgs.macApps entries during darwin-rebuild activation
  wallpaper.nix                  generates + sets the wallpaper via desktoppr (see below)
  roles/
    main-presentation.nix       ProPresenter, Word, PowerPoint
    foh.nix                     Spotify, Wireless Workbench, Klang:fabrik, DVS, Dante Controller, Reaper
    lighting.nix                 grandMA3 onPC
    nextgen-presentation.nix    ProPresenter only
hosts/
  nc-production-main-cg-1/      NC-Production-Main-CG-1
  nc-production-main-cg-2/      NC-Production-Main-CG-2 (FOH)
  nc-production-main-cg-3/      NC-Production-Main-CG-3 (lighting)
  nc-production-nextgen-cg-1/   NC-Production-NextGen-CG-1
scripts/update_packages.py      manages packages.json (bulk sync + per-package add/update/info/delete/revert)
```

## How app installs work

There's no Homebrew cask here -- `pkgs.macApps.<name>` is built straight from
`packages.json`:

- **`.dmg` / `.zip` apps** (ProPresenter, Dropbox, Spotify, REAPER) are
  unpacked with `undmg`/`unzip` into a Nix store path, then
  `modules/mac-app-activation.nix` symlinks the `.app` into `/Applications`
  during `darwin-rebuild switch`.
- **`.pkg` installers** (Microsoft Word/PowerPoint, Wireless Workbench,
  Dante Controller, Tailscale, TeamViewer, Blackmagic Desktop Video, ATEM
  Software Control) are fetched as hash-pinned store paths and run through
  the real `/usr/sbin/installer` on activation -- this is intentional. A
  from-scratch Nix rebuild of what Apple's installer(8) does (kernel
  extensions, launch daemons, licensing helpers) is not something worth
  reimplementing; letting the vendor's own installer run against a
  hash-pinned artifact gets correct behavior and is still fully
  reproducible. It's idempotent via `pkgutil --pkg-info`, so re-running
  `darwin-rebuild switch` won't reinstall unnecessarily.

## Wallpaper

Every host gets a generated wallpaper (`modules/wallpaper.nix` +
`lib/mk-wallpaper.nix`): a solid background color (`#252A35` by default),
an optional centered logo, and the hostname watermarked in the bottom-left
corner. It's built with ImageMagick at evaluation time and set via
[`desktoppr`](https://github.com/scriptingosx/desktoppr) (packaged like
everything else, no Homebrew) running from a LaunchAgent at login --
`osascript ... tell "System Events"` is the more commonly suggested
approach but it routinely no-ops when run from a non-interactive root
activation script, which is exactly the context `darwin-rebuild` runs in.

Options (settable per-host in `hosts/<name>/default.nix`, or fleet-wide in
`modules/common.nix`):

```nix
production.wallpaper = {
  enable = true;               # default
  backgroundColor = "#252A35"; # default
  foregroundImage = null;      # default: none: see assets/README.md
  width = 2560; height = 1440;
  fontSize = 72;
  textColor = "white";
  margin = 80;
};
```

To composite in a logo: drop a transparent PNG at `assets/logo.png` and
`git add` it (flakes only see git-tracked files, even before you commit --
see `assets/README.md` for the full explanation and the case where the
logo lives in a separate repo instead).

## Dock

`modules/common.nix` sets `system.defaults.dock.persistent-apps = [ ];`,
`persistent-others = [ ];`, and `show-recents = false;` fleet-wide -- no
pinned apps, no "recent applications" clutter. Finder/Trash still show
(macOS always keeps those), and whatever's actually running still appears
in the Dock while it's running; it just doesn't stay pinned afterward. To
pin something specific on a given host instead, override
`system.defaults.dock.persistent-apps` in that host's `default.nix` with a
list like `[ "/Applications/ProPresenter.app" ]`.

## Before your first `darwin-rebuild switch`

**1. Wipe and set up macOS.** Not something Nix can do for you -- erase each
Mac Mini (Erase All Content and Settings, or a clean reinstall), get through
Setup Assistant, connect to Wi-Fi/Ethernet, and enable Remote Login/apply
whatever MDM profile you use.

**2. Install Nix + nix-darwin.** e.g. via the
[Determinate Systems installer](https://install.determinate.systems/), then
follow nix-darwin's bootstrap instructions to point it at this flake:

```sh
git clone <this repo> ~/nc-production-nix-darwin
cd ~/nc-production-nix-darwin
sudo darwin-rebuild switch --flake .#NC-Production-Main-CG-1   # or -CG-2 / -CG-3 / NextGen-CG-1
```

**3. Fill in the 5 placeholder packages.** `blackmagic-desktop-video`,
`atem-software-control`, `dante-virtual-soundcard`, `klang-fabrik`, and
`grandma3-onpc` don't have a stable, publicly-discoverable download URL
(vendor product picker / license-gated account), so `packages.json` ships
them with `"url": "REPLACE_ME"` and a zeroed hash. **The build will fail
until you fix these** for any host that needs them (all 4 hosts need the
two Blackmagic packages; CG-2/FOH also needs the Dante/Klang ones; CG-3/
lighting needs grandMA3 onPC). Download each installer manually from the
vendor once, then run:

```sh
python3 scripts/update_packages.py pkg update blackmagic-desktop-video <url-you-got>
python3 scripts/update_packages.py pkg update atem-software-control <url-you-got>
python3 scripts/update_packages.py pkg update dante-virtual-soundcard <url-you-got>
python3 scripts/update_packages.py pkg update klang-fabrik <url-you-got>
python3 scripts/update_packages.py pkg update grandma3-onpc <url-you-got>
```

For `grandma3-onpc` specifically: after the first manual install, run
`pkgutil --pkgs | grep -i grandma` on that Mac and make sure it matches
`pkgId` in `packages.json` (currently a guess, `com.malighting.grandma3onpc`)
-- otherwise the activation script's "already installed?" check never
matches and it reinstalls every `darwin-rebuild switch`.

This downloads the file, computes its sha256, and writes the real
version/url/hash into `packages.json` for you.

**4. Set account passwords + enable autologin.** Nix intentionally can't set
macOS login passwords (no plaintext secrets belong in the Nix store), so
after the first activation creates the `CG-1`/`CG-2` account:

```sh
sudo passwd CG-1     # or CG-2 / CG-3
```

Then confirm System Settings > Users & Groups > Login Options has
"Automatically log in as" set to that account. `system.defaults.loginwindow.autoLoginUser`
is set in `modules/cg-account.nix`, but macOS's autologin keychain entry is
tied to the account having a password already set, so double-check this by
hand the first time.

**5. Sign the Main CG-1 Mac into Mail.** "It also should be signed into main
pro in the mail app" isn't scriptable -- Internet Accounts / Mail sign-in
needs an interactive password or OAuth flow. Do this once by hand: Mail >
Settings > Accounts > Add Account, using the Main Pro mailbox credentials.

## Managing packages

`scripts/update_packages.py` has three layers: `sync` for bulk updates,
`list-all` for a fleet-wide overview, and `pkg <add|update|info|delete|revert>`
for working on one package at a time. Run `python3 scripts/update_packages.py --help`
or `... pkg <subcommand> --help` for the full option list.

`nix-shell` (see `shell.nix`) puts both `update-packages` and
`update_packages.py` on `PATH`, so you can drop the `python3 scripts/` part
and run e.g. `update-packages list-all` from anywhere in the repo.

### See everything at a glance

```sh
python3 scripts/update_packages.py list-all
```

Prints every package's kind/version/update-strategy in one table, and
flags anything still sitting at the `REPLACE_ME` placeholder.

### Bulk update everything

```sh
python3 scripts/update_packages.py sync             # check + update every package with an automatic strategy
python3 scripts/update_packages.py sync --dry-run    # preview without writing packages.json
```

10 of the 14 packages (ProPresenter, Microsoft Word/PowerPoint, Dropbox,
Spotify, REAPER, Wireless Workbench, Dante Controller, Tailscale, TeamViewer)
have an automatic strategy that polls the vendor's own update-check endpoint,
downloads the new build, and rewrites `packages.json` with the new
version/url/sha256. `sync` skips the 4 manual packages (see step 3 above) --
those need `pkg update <name> <url>` each time the vendor ships an update,
since there's no feed to poll. Review the diff (`git diff packages.json`)
before committing -- especially for Microsoft Office and Wireless Workbench,
whose installers make system-level changes.

### One package at a time

```sh
# Add a brand-new package (kind is dmg/zip/pkg; use --app-name for dmg/zip,
# --pkg-id for pkg). sha256 is computed automatically if you don't pass one.
python3 scripts/update_packages.py pkg add obs-studio dmg 31.2.0 \
    https://cdn.example.com/OBS-31.2.0.dmg --app-name "OBS.app"

# Update an existing package:
python3 scripts/update_packages.py pkg update reaper                       # guess the latest version+url automatically (same strategy 'sync' uses)
python3 scripts/update_packages.py pkg update klang-fabrik <url>           # give it a URL, version is guessed from the filename
python3 scripts/update_packages.py pkg update reaper 7.77 <url>           # or set both explicitly

# Show current version + full git-history of version changes for a package:
python3 scripts/update_packages.py pkg info reaper

# Remove a package entirely:
python3 scripts/update_packages.py pkg delete obs-studio

# Roll a package's version/url/hash back to what it was at an earlier commit
# (find the commit hash with `pkg info` first):
python3 scripts/update_packages.py pkg revert reaper 8f3a1c2
```

`add`/`update`/`info`/`delete`/`revert` also accept their first-letter aliases
(`a`/`u`/`i`/`d`/`r`). `pkg info` and `pkg revert` read git history for
`packages.json`, so they only do anything useful once this directory is an
actual git checkout with commits behind it -- `pkg info` will tell you if it
isn't.

## Applying / re-applying a host

```sh
sudo darwin-rebuild switch --flake .#NC-Production-Main-CG-1
sudo darwin-rebuild switch --flake .#NC-Production-Main-CG-2
sudo darwin-rebuild switch --flake .#NC-Production-Main-CG-3
sudo darwin-rebuild switch --flake .#NC-Production-NextGen-CG-1
```

Run `darwin-rebuild build --flake .#<host>` first if you just want to check
the config evaluates/builds without switching the running system.

## Notes / things worth double-checking

- This was written against nix-darwin's `master` branch API as of mid-2026
  (`system.primaryUser`, `system.activationScripts.postActivation`,
  `users.users.<name>.isAdminUser`, `system.defaults.loginwindow.autoLoginUser`,
  `launchd.user.agents.<name>`). Pin a specific nix-darwin release in
  `flake.lock` and run `darwin-rebuild build` before your first real switch
  -- if any option name has moved, the error will point you at exactly
  which one.
- `system.stateVersion` in `modules/common.nix` is set to `5` as a
  placeholder; check nix-darwin's release notes for the value that matches
  the release you actually pin.
- All four Macs are configured as `aarch64-darwin` (Apple Silicon M4) in
  `flake.nix`.
- The wallpaper generator (`lib/mk-wallpaper.nix`) needs `imagemagick`
  buildable/cached for `aarch64-darwin`, which it is on the standard
  nixpkgs binary cache -- if you're pointed at a from-source/limited
  channel it'll compile from source the first time instead, which is slow
  but not wrong.
