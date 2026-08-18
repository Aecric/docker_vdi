#!/bin/sh
set -eu

if [ -z "${DISPLAY:-}" ]; then
    echo "错误：未设置 DISPLAY。请使用 ./run.sh 启动，或传入 DISPLAY 并挂载 /tmp/.X11-unix。" >&2
    exit 1
fi

mkdir -p /run/sangfor/vdiclient /run/systemd/users /home/vdi/.config /tmp/runtime-vdi
chmod 0777 /run/sangfor/vdiclient
chmod 0700 /tmp/runtime-vdi
chown -R vdi:vdi /home/vdi
chown vdi:vdi /tmp/runtime-vdi

# The vendor update check expects logind's per-user state file. Containers do
# not run systemd-logind, so provide the minimal active-session information it
# reads when deciding whether the client may continue after a version check.
vdi_uid=$(id -u vdi)
{
    printf '%s\n' '# This is compatibility data for the Sangfor VDI client.'
    printf '%s\n' 'NAME=vdi'
    printf '%s\n' 'STATE=active'
    printf '%s\n' 'STOPPING=no'
    printf 'RUNTIME=%s\n' '/tmp/runtime-vdi'
} >"/run/systemd/users/${vdi_uid}"
chmod 0644 "/run/systemd/users/${vdi_uid}"

# Docker does not run systemd. Start the privileged agent and wait until its
# Unix socket is ready before starting the web UI agent. Without this wait the
# client reports a misleading "network error" for https://127.0.0.1:31113.
if [ -x /usr/local/sangfor/vdiclient/bin/vdi_super_agent ]; then
    /usr/local/sangfor/vdiclient/bin/vdi_super_agent >/tmp/vdi-super-agent.log 2>&1 &
    super_agent_pid=$!

    socket_ready=false
    attempts=0
    while [ "$attempts" -lt 100 ]; do
        if [ -S /run/sangfor/vdiclient/vdi_super_agent.sock ]; then
            socket_ready=true
            break
        fi
        if ! kill -0 "$super_agent_pid" 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 0.1
    done

    if [ "$socket_ready" != true ]; then
        echo "错误：vdi_super_agent 未能创建本地通信 socket。" >&2
        cat /tmp/vdi-super-agent.log >&2 || true
        exit 1
    fi
fi

export HOME=/home/vdi
export USER=vdi
export LOGNAME=vdi
export XDG_RUNTIME_DIR=/tmp/runtime-vdi

if [ "$#" -eq 0 ]; then
    set -- /usr/local/sangfor/vdiclient/bin/vdi_local_client
fi

exec gosu vdi dbus-run-session -- sh -c '
    webui_ready=false
    attempts=0
    while [ "$attempts" -lt 10 ]; do
        /usr/local/sangfor/vdiclient/bin/vdi_webui_agent >>/tmp/vdi-webui-agent.log 2>&1 &
        webui_pid=$!
        checks=0
        while [ "$checks" -lt 20 ]; do
            if ss -ltn | grep -q "127.0.0.1:31113"; then
                webui_ready=true
                break
            fi
            if ! kill -0 "$webui_pid" 2>/dev/null; then
                break
            fi
            checks=$((checks + 1))
            sleep 0.1
        done
        if [ "$webui_ready" = true ]; then
            break
        fi
        wait "$webui_pid" 2>/dev/null || true
        attempts=$((attempts + 1))
        sleep 0.2
    done

    if [ "$webui_ready" != true ]; then
        echo "错误：vdi_webui_agent 未能监听 127.0.0.1:31113。" >&2
        cat /tmp/vdi-webui-agent.log >&2 || true
        exit 1
    fi

    # On a regular Ubuntu desktop, the vendor watchdog relaunches the GUI when
    # it intentionally exits for an update. In the container the GUI is the
    # foreground process, so reproduce that behavior only when its fresh log
    # explicitly reports the update-exit path.
    login_log=/var/log/sangfor/vdiclient/vdi_login_client.log
    restart_count=0
    while :; do
        before_lines=0
        if [ -f "$login_log" ]; then
            before_lines=$(wc -l <"$login_log")
        fi

        "$@"
        client_status=$?

        if [ "$client_status" -ne 0 ]; then
            exit "$client_status"
        fi

        if [ "$restart_count" -lt 3 ] \
            && [ -f "$login_log" ] \
            && tail -n "+$((before_lines + 1))" "$login_log" \
                | grep -q "client update! quit client and wait to start"; then
            restart_count=$((restart_count + 1))
            echo "VDI 客户端请求更新后重启（${restart_count}/3）..." >&2
            sleep 2
            continue
        fi

        exit 0
    done
' sh "$@"
