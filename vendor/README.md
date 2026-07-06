# vendor/

For packages where the vendor genuinely has no stable, fetchable URL, the
installer is checked into the repo itself instead of referenced by URL.
That covers two different situations, currently four packages:

- **Access-token-gated downloads.** `grandma3-onpc`: the download link is
  tied to your MA Lighting account session and will expire or stop working
  the moment Nix tries to re-fetch it later, on a new machine, or after
  `nix-collect-garbage`.
- **No public URL at all** (account/license-gated portal, no direct link
  to poll): `blackmagic-desktop-video`, `atem-software-control`,
  `dante-virtual-soundcard`.

`overlays/production-apps.nix` reads `packages.json` entries with
`"kindDetail": "local"` and points straight at `vendor/<localPath>` as a
plain Nix path, so it never needs the network at build time.

## Adding a package here

1. Log in and download the installer from the vendor's site.
2. **If it's a .dmg, extract the real installer first.** Blackmagic and
   Audinate both ship their macOS installers as a `.dmg` wrapping the
   actual `.pkg` -- mount it in Finder (or `undmg` it) and pull out just
   the `.pkg`. Only the extracted `.pkg`/`.app` goes in this directory; the
   raw `.dmg` is gitignored (`*.dmg`) on purpose so it can't get committed
   by accident, even via `git add -A`.
3. Save it at the path named in that package's `"localPath"` field in
   `packages.json` (e.g. `vendor/blackmagic-desktop-video.pkg`).
4. **`git add` it explicitly.** Same rule as `assets/logo.png` -- Nix
   flakes only see git-tracked files, even before you commit, so an
   untracked file here is invisible to `darwin-rebuild`.
5. Update that package's `"version"` in `packages.json` to match what you
   downloaded.
6. Run `darwin-rebuild build --flake .#<host>` to confirm it resolves.
7. After the first real install on the target Mac, run
   `pkgutil --pkgs | grep -i <vendor>` and make sure it matches `pkgId` in
   `packages.json` -- the ones here are best-guess placeholders. If they're
   wrong, `modules/mac-app-activation.nix`'s "already installed?" check
   never matches and it reinstalls on every `darwin-rebuild switch`.

## Before you commit: licensing

This directory holds actual copies of other vendors' commercial
installers, not something Nix fetched on demand. That's fine for internal,
private use the way you're already licensed to run them -- but if this
repo is public (or ever becomes public), redistributing a vendor's
proprietary installer may not be allowed under their terms, separate from
whatever license you picked for your own Nix/Python code. Worth a quick
check against Blackmagic's, Audinate's, and MA Lighting's EULAs before
pushing this directory to a public remote.
