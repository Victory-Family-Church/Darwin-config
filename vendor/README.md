# vendor/

For the rare package where the vendor genuinely has no stable, fetchable
URL -- specifically **access-token-gated downloads** (grandMA3 onPC: the
download link is tied to your MA Lighting account session and will expire
or stop working the moment Nix tries to re-fetch it later, on a new
machine, or after `nix-collect-garbage`) -- the installer is checked into
the repo itself instead of referenced by URL.

`overlays/production-apps.nix` reads `packages.json` entries with
`"kindDetail": "local"` and points straight at `vendor/<localPath>` as a
plain Nix path, so it never needs the network at build time.

## Adding a package here

1. Log in and download the installer from the vendor's site.
2. Save it at the path named in that package's `"localPath"` field in
   `packages.json` (e.g. `vendor/grandma3-onpc.pkg`).
3. **`git add` it.** Same rule as `assets/logo.png` -- Nix flakes only see
   git-tracked files, even before you commit, so an untracked file here is
   invisible to `darwin-rebuild`.
4. Update that package's `"version"` in `packages.json` to match what you
   downloaded.
5. Run `darwin-rebuild build --flake .#<host>` to confirm it resolves.

## Before you commit: licensing

This directory holds an actual copy of someone else's commercial
installer, not something Nix fetched on demand. That's fine for internal,
private use the way you're already licensed to run it -- but if this repo
is public (or ever becomes public), redistributing a vendor's proprietary
installer may not be allowed under their terms, separate from whatever
license you picked for your own Nix/Python code. Worth a quick check
against MA Lighting's (or whoever's) EULA before pushing this directory to
a public remote.
