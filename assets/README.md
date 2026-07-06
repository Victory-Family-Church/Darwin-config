# assets/

Drop an optional logo here to have it composited into the generated
wallpaper (see `modules/wallpaper.nix` / `lib/mk-wallpaper.nix`).

- Expected file: `assets/logo.png`
- Use a PNG with an **alpha channel** (transparent background) -- it gets
  centered over the solid background color, so anything transparent shows
  the background color through.
- If `assets/logo.png` doesn't exist, `modules/common.nix` just leaves
  `production.wallpaper.foregroundImage` unset and every host gets a plain
  solid-color wallpaper (black by default) with the hostname watermark in
  the bottom-left corner -- nothing breaks either way.

**Important (flakes + git):** this is a Nix flake, and flakes only see
files that are tracked by git -- an untracked file in your working
directory is invisible to the build, even before you commit. After adding
a logo:

```sh
git add assets/logo.png
darwin-rebuild build --flake .#NC-Production-Main-CG-1   # confirm it's picked up
git commit -m "add wallpaper logo"
```

If `darwin-rebuild` still can't find it after `git add`, that's the tell --
it means the file genuinely isn't staged yet.

If your logo lives in a *different* repo instead of this one, don't copy it
in by hand -- pull it in properly so it stays hash-pinned and updatable:

```nix
# flake.nix
inputs.logo-assets = { url = "github:your-org/branding-assets"; flake = false; };

# wherever you set production.wallpaper (e.g. modules/common.nix), with
# `inputs` threaded through via specialArgs like hostName already is:
production.wallpaper.foregroundImage = "${inputs.logo-assets}/logo.png";
```

To use a different filename, or set different colors/sizes per host, set
`production.wallpaper.*` directly in that host's `hosts/<name>/default.nix`
(or in a role module) instead of relying on the `assets/logo.png` default,
e.g.:

```nix
production.wallpaper = {
  backgroundColor = "#0a0a0a";
  foregroundImage = ../../assets/some-other-logo.png;
  textColor = "#cccccc";
};
```
