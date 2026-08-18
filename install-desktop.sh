#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
desktop_dir=${XDG_DESKTOP_DIR:-}

if [ -z "$desktop_dir" ] && command -v xdg-user-dir >/dev/null 2>&1; then
    desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || true)
fi
if [ -z "$desktop_dir" ] || [ "$desktop_dir" = "$HOME" ]; then
    desktop_dir="$HOME/Desktop"
fi

command_dir="$HOME/.local/bin"
application_dir="$HOME/.local/share/applications"
icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
launcher_name="深信服-VDI.desktop"

mkdir -p "$command_dir" "$application_dir" "$icon_dir" "$desktop_dir"

# Keep the portable desktop entry free of a checkout-specific absolute path.
# Only this per-user symlink records where the current checkout is located.
ln -sfn "$script_dir/run.sh" "$command_dir/sangfor-vdi"
cp "$script_dir/sangfor-vdi.png" "$icon_dir/sangfor-vdi.png"
cp "$script_dir/sangfor-vdi.desktop" "$application_dir/sangfor-vdi.desktop"
cp "$script_dir/sangfor-vdi.desktop" "$desktop_dir/$launcher_name"
chmod 0755 "$desktop_dir/$launcher_name"

if command -v gio >/dev/null 2>&1; then
    gio set "$desktop_dir/$launcher_name" metadata::trusted true 2>/dev/null || true
fi

printf '桌面启动器已安装：%s\n' "$desktop_dir/$launcher_name"
