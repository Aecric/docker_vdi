#!/bin/sh
set -eu

if [ -z "${DISPLAY:-}" ]; then
    echo "错误：宿主机没有 DISPLAY；请从 X11 图形桌面的终端运行。" >&2
    exit 1
fi

VDI_UID=$(id -u)
VDI_GID=$(id -g)
export VDI_UID VDI_GID DISPLAY

image_name="sangfor-vdi:ubuntu20.04"

cleanup() {
    xhost -SI:localuser:root >/dev/null 2>&1 || true
    xhost -SI:localuser:"$(id -un)" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

# The container's vdi account uses the current host UID, allowing only that
# local user to connect to X instead of disabling X access control globally.
# The vendor's vdi_session executable is setuid-root, so the actual remote
# desktop window also needs the narrowly scoped local-root authorization.
xhost +SI:localuser:"$(id -un)" >/dev/null
xhost +SI:localuser:root >/dev/null

if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "首次运行：正在构建 $image_name ..."
    docker compose build sangfor-vdi
fi

docker compose up --no-build --remove-orphans sangfor-vdi
