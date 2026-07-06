# vendor/

**Nothing in this directory is part of the git repo** (see `.gitignore` --
only this README is tracked). It's a local staging area you can use while
downloading installers, nothing more.

Five packages can't be fetched by `fetchurl` at build time, for two
different reasons:

- **Access-token-gated downloads.** `grandma3-onpc`: the download link is
  tied to your MA Lighting account session and will expire or stop
  working the moment Nix tries to re-fetch it later, on a new machine, or
  after `nix-collect-garbage`.
- **No public URL at all** (account/license-gated portal): `atem-software-control`,
  `dante-virtual-soundcard`.
- **Deliberately pinned** even though a public URL exists: `spotify`
  (Spotify's real download is an unversioned rolling build with no
  vendor-published hash, so auto-updating it could quietly ship a
  different build than last time with nothing to diff).

We initially tried checking these straight into git. That failed almost
immediately: `grandma3-onpc.pkg` alone is **697MB**, Blackmagic's
downloads run **hundreds of MB to multiple GB** (ATEM Switchers' is
5.7GB). GitHub hard-blocks any single file over 100MB without Git LFS, and
even LFS's free tier (1GB total) can't hold one of these, let alone all of
them. So instead, `packages.json` gives each of these a `"kindDetail"` of
`"external"` (or `"externalDmgContainsPkg"` -- see below) and a fixed
**absolute** `"localPath"` (e.g.
`/Users/Shared/nc-vendor/grandma3-onpc.pkg`) that lives completely outside
this repo. `overlays/production-apps.nix` reads straight from that path at
build time -- nothing is ever fetched or committed for these five.

**Blackmagic Desktop Video and ATEM Software Control are both a plain
`.dmg` wrapping the real installer `.pkg`** -- confirmed, not zip-wrapped.
Rather than making you extract the `.pkg` by hand, their `kindDetail` is
`"externalDmgContainsPkg"` and `"localPath"` points at the raw `.dmg`
itself (e.g. `blackmagic-desktop-video.dmg`) -- Nix pulls the `.pkg` out
of it automatically at build time (`lib/mac-apps.nix`'s
`mkPkgFromLocalDmg`), the same technique already used for the
URL-fetched `dante-controller`. Just place the downloaded `.dmg` at the
fixed path (renamed to match), nothing to unwrap yourself.

**Spotify is different from all the others: it's not a .dmg at all.**
Confirmed from the actual vendor contents -- Spotify's Mac download is
`"Install Spotify.app"`, a standalone executable installer *bundle* (a
directory, not a single file) that has to be *run* once to install the
real `Spotify.app`, not copied or symlinked. Its `"kind"` is
`"app-installer"` and `"localPath"` points at the whole `.app` directory
itself. Because it's a directory, there's no `builtins.hashFile`-based
integrity check possible here (that only works on single files) --
`packages.json` won't have a `"localSha256"` for this one, and that's
expected. `modules/mac-app-activation.nix` runs it from a LaunchAgent
(same reasoning as `desktoppr`: installing needs a real login/WindowServer
session, which the root activation script during `darwin-rebuild` doesn't
have), checking for `/Applications/Spotify.app` to know it's already done.

If `packages.json` has a `"localSha256"` for one of the single-file
entries, the overlay cross-checks the file at that path against it and
**fails the build loudly** if they don't match -- catching the case where
the wrong file (or no file) is sitting there.

## Provisioning a new Mac

This only matters once per machine, when you're setting it up for the
first time (or replacing a wiped one) -- after that the files just sit at
their fixed paths and every future `darwin-rebuild switch` reads them
as-is.

1. Download each installer this host's role needs from the vendor (see
   each package's `"homepage"` in `packages.json`, or run
   `python3 scripts/update_packages.py list-all`).
2. **Extraction needed only for `dante-virtual-soundcard`** (whatever
   `.dmg`/`.zip` Audinate ships it in -- pull out just the `.pkg`).
   Everything else is used as-is:
   - `blackmagic-desktop-video` / `atem-software-control` -- keep the raw
     `.dmg` Blackmagic gives you, don't extract it. Nix pulls the `.pkg`
     out of the `.dmg` automatically at build time.
   - `grandma3-onpc` -- already a plain `.pkg`.
   - `spotify` -- keep the whole `"Install Spotify.app"` bundle as-is
     (it's a directory, not a file that unzips/mounts into something
     else) -- don't dig inside it.
3. Drop the files (or, for Spotify, the whole `.app` bundle) into a
   staging folder (this `vendor/` directory works fine, or anywhere else --
   it's never read directly by Nix), renamed to match each package's
   `"localPath"` basename exactly (e.g. `grandma3-onpc.pkg`,
   `blackmagic-desktop-video.dmg`, `Install Spotify.app`) -- the
   provisioning step below matches by exact filename and copies whole
   directories intact.
4. Run the provisioning helper, either via the CLI or as a flake app:
   ```sh
   python3 scripts/update_packages.py provision --staging ./vendor
   # or, without even needing a checkout of the script on PATH:
   nix run .#provision-vendor -- --staging ./vendor
   ```
   This copies each matched file from staging into its real fixed path
   (creating directories as needed) and reports **OK** / **MISMATCH**
   (wrong file for that path -- compares against `packages.json`'s
   `localSha256`) / **MISSING** (not found in staging, with the vendor's
   homepage URL to go grab it from) for every manual-local package. Add
   `--status` to just check without copying anything. Exits non-zero if
   anything's not ready yet, so it can gate a setup script.
5. If a package doesn't have a `localSha256` recorded yet (a fresh
   `pkg add`, or you're intentionally updating to a new version), run:
   ```sh
   python3 scripts/update_packages.py pkg update <name> <version>
   ```
   This reads the file at its fixed path and writes both `"version"` and
   `"localSha256"` into `packages.json` -- the local equivalent of the
   normal `pkg update <name> <url>` flow, just without a download.
6. Run `darwin-rebuild build --flake .#<host>` to confirm it all resolves.
7. For the `.pkg`-based ones, after the first real install on the target
   Mac, run `pkgutil --pkgs | grep -i <vendor>` and make sure it matches
   `pkgId` in `packages.json` -- the ones there are best-guess placeholders.
   If they're wrong, `modules/mac-app-activation.nix`'s "already installed?"
   check never matches and it reinstalls on every `darwin-rebuild switch`.

## Licensing

These are actual copies of other vendors' software, not something Nix
fetched on demand. Keeping them entirely out of git (rather than, say,
Git LFS) also sidesteps a licensing question that would otherwise come up
the moment this repo is pushed anywhere -- redistributing a vendor's
proprietary installer, even privately, may not be allowed under their
terms. Worth knowing regardless: check Blackmagic's, Audinate's, MA
Lighting's, and Spotify's terms before you copy these installers anywhere
beyond the Macs you're licensed to run them on.
