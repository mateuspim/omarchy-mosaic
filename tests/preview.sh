#!/usr/bin/env bash
# Render the Mosaic panel offscreen with sample tiles, one PNG per scene.
# Usage: MOSAIC_PREVIEW_DIR=<absolute dir> bash tests/preview.sh
# MOSAIC_PREVIEW_COLORS=<colors.toml> renders under another theme (default:
# tests/offscreen/colors.toml, the README captures' slate-teal sample).
# Never opens a window on a display, never talks to Hyprland, the browser or
# the running shell, and never reads the user's config or state.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="${MOSAIC_PREVIEW_DIR:?set MOSAIC_PREVIEW_DIR to an absolute output directory}"
[[ "$out_dir" == /* ]] || { echo "MOSAIC_PREVIEW_DIR must be absolute: $out_dir" >&2; exit 2; }
mkdir -p "$out_dir"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mosaic-preview.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

# Commons and Ui come from the installed Omarchy shell; KeyboardPanel needs a
# layer-shell PanelWindow, so it is swapped for an Item stand-in.
ln -s /usr/share/omarchy/shell/Commons "$work_dir/Commons"
mkdir "$work_dir/Ui"
ln -s /usr/share/omarchy/shell/Ui/* "$work_dir/Ui/"
ln -sf "$repo_dir/tests/offscreen/KeyboardPanel.qml" "$work_dir/Ui/KeyboardPanel.qml"

# A copy of the panel and its logic, plus the fake service. The service
# itself (MosaicService.qml) is never loaded.
mkdir "$work_dir/plugin"
cp "$repo_dir"/{Panel.qml,Model.js,manifest.json} "$work_dir/plugin/"
cp "$repo_dir/tests/offscreen/FakeService.qml" "$work_dir/plugin/FakeService.qml"
# The large layout editor is a full-screen layer surface that the preview
# never opens; offscreen there is no layer shell, so draw it as a plain
# window instead.
sed -i -e 's/^  PanelWindow {$/  FloatingWindow {/' \
  -e '/^    WlrLayershell\./d' -e '/^    exclusionMode: /d' \
  -e '/^    anchors { top: true; bottom: true; left: true; right: true }$/d' \
  "$work_dir/plugin/Panel.qml"
cp "$repo_dir/tests/Preview.qml" "$work_dir/shell.qml"

mkdir -p "$work_dir/home/.local/state/omarchy/current/theme" "$work_dir/runtime"
cp "${MOSAIC_PREVIEW_COLORS:-$repo_dir/tests/offscreen/colors.toml}" "$work_dir/home/.local/state/omarchy/current/theme/colors.toml"
chmod 700 "$work_dir/runtime"
status=0
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$work_dir/home" XDG_CONFIG_HOME="$work_dir/home/.config" \
  XDG_RUNTIME_DIR="$work_dir/runtime" XDG_CACHE_HOME="$work_dir/cache" \
  XDG_STATE_HOME="$work_dir/state" XDG_DATA_HOME="$work_dir/home/.local/share" \
  MOSAIC_BRIDGE_SOCKET="$work_dir/runtime/pym-mosaic.sock" \
  MOSAIC_PREVIEW_DIR="$out_dir" QT_QPA_PLATFORM=offscreen \
  QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-2}" QT_STYLE_OVERRIDE=Fusion QT_QPA_PLATFORMTHEME=xdgdesktopportal \
  timeout 40s quickshell -p "$work_dir/shell.qml" --no-color >"$work_dir/output" 2>&1 || status=$?
cat "$work_dir/output"
[[ "$status" -eq 0 ]]
if grep -Ei '(TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign|Unable to assign|Binding loop|MOSAIC_PREVIEW_FAILED)' "$work_dir/output"; then
  exit 1
fi
grep -q MOSAIC_PREVIEW_OK "$work_dir/output"
