# Build a desktop wallpaper PNG on the fly: solid background color, an
# optional foreground image (e.g. a logo, composited centered -- use a PNG
# with an alpha channel so the background shows through), and the hostname
# stamped in the bottom-left corner. Pure Nix + ImageMagick, no external
# asset pipeline needed.
{ pkgs, lib }:

{ backgroundColor # ImageMagick color spec, e.g. "#000000" or "black"
, hostname # text stamped in the bottom-left corner
, foregroundImage ? null # optional path to a (presumably transparent) PNG
, foregroundScale ? 0.45 # fraction of canvas height the fg image is scaled to
, width ? 2560
, height ? 1440
, font ? "Gotham" # ImageMagick font name (or an absolute path to a .otf/.ttf)
, fontSize ? 42
, textColor ? "white"
, margin ? 80
}:

let
  fgHeight = builtins.floor (height * foregroundScale);
in

pkgs.runCommand "wallpaper-${hostname}.png"
  {
    nativeBuildInputs = [ pkgs.imagemagick ];
  }
  ''
    convert -size ${toString width}x${toString height} xc:"${backgroundColor}" base.png

    ${lib.optionalString (foregroundImage != null) ''
      convert "${foregroundImage}" -resize x${toString fgHeight} fg.png
      convert base.png fg.png -gravity center -composite base.png
    ''}

    convert base.png \
      -gravity SouthWest \
      -font "${font}" \
      -pointsize ${toString fontSize} \
      -fill "${textColor}" \
      -stroke black -strokewidth 2 \
      -annotate +${toString margin}+${toString margin} "${hostname}" \
      "$out"
  ''
