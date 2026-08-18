# Ubuntu 20.04 深信服 VDI Docker

在 Ubuntu 20.04 Docker 容器中运行深信服 VDI Linux 客户端，并把登录窗口和
远程桌面显示到 Linux 宿主机当前的 X11/XWayland 桌面。

本项目解决了客户端在普通容器中常见的几个问题：

- 启动脚本只在镜像不存在时构建，日常启动不会重复执行 `apt-get update`。
- 使用 Docker bridge/NAT 直连，不继承宿主机的 HTTP/HTTPS/ALL_PROXY 代理，
  也不使用 Mihomo 的 `127.0.0.1` 代理端口或虚拟网卡。
- 模拟客户端所需的最小 systemd 用户会话，并按顺序启动深信服后台代理。
- 固定容器 MAC，避免容器重建后设备标识和本地加密数据发生变化。
- 为 setuid-root 的 `vdi_session` 提供精确 X11 授权，解决“获取桌面资源成功，
  正在连接会话”后无法打开远程桌面的问题。
- 使用 Ubuntu 20.04 的 `libusb 1.0.23`，解决安装包内置旧版 libusb 在新内核上
  注册 USB 热插拔回调时触发 `signal 11`、远程桌面闪退的问题。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `Dockerfile` | 构建 Ubuntu 20.04 VDI 镜像 |
| `compose.yaml` | X11 挂载、固定 MAC、持久化配置和 bridge 网络 |
| `docker-entrypoint.sh` | 启动厂商代理、D-Bus 和客户端 |
| `run.sh` | X11 授权、首次构建和日常启动 |
| `install-desktop.sh` | 为当前用户安装桌面启动器、命令和图标 |
| `sangfor-vdi.desktop` | 不包含检出目录绝对路径的 GNOME 启动器 |
| `sangfor-vdi.png` | 桌面图标 |

厂商 deb 和导出的 tar 镜像体积大且可能受分发许可限制，已经由 `.gitignore`
排除，不应提交到 Git 仓库。

## 前置条件

宿主机需要：

- Docker Engine
- Docker Compose v2 插件（`docker compose`）
- `xhost`
- 正在运行的 X11 桌面，或者启用了 XWayland 的 Wayland 桌面

将厂商安装包放在项目根目录，并使用以下文件名：

```text
vdi-linux-client-x86_64-ubuntu.deb
```

本项目当前按照深信服客户端 `5.9.1.530` 验证。deb 不会被 Git 跟踪，但会由
`.dockerignore` 明确放入 Docker 构建上下文。

## 启动

```bash
chmod +x run.sh
./run.sh
```

第一次运行且本地没有 `sangfor-vdi:ubuntu20.04` 镜像时，脚本会执行构建。
之后运行会使用 `docker compose up --no-build`，不会再次构建，也不会重新运行
`apt-get update`。

客户端配置保存在 Docker 卷 `docker_vdi_vdi-home` 中，重建或替换容器不会删除
登录配置。除非确定不再需要这些数据，否则不要删除该卷。

## GNOME 桌面图标

运行安装脚本：

```bash
chmod +x install-desktop.sh
./install-desktop.sh
```

安装脚本会：

- 在 `~/.local/bin/sangfor-vdi` 创建指向当前项目 `run.sh` 的用户级软链接。
- 将图标安装为 `~/.local/share/icons/hicolor/256x256/apps/sangfor-vdi.png`。
- 将不含用户目录和项目绝对路径的桌面文件安装到应用菜单和当前桌面。

桌面文件通过登录 shell 查找 `sangfor-vdi` 命令，因此仓库移动或换用户名时无需
修改 `.desktop` 内容；移动仓库后重新执行一次 `install-desktop.sh` 更新软链接即可。

## 网络行为

容器使用 Docker bridge/NAT，通过宿主机的默认物理出口访问 VDI 服务器。Compose
没有配置 `network_mode: host`，也不会传入下列代理变量：

```text
HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
```

客户端日志中的 `127.0.0.1:31113` 是容器内部 `vdi_local_client` 与
`vdi_webui_agent` 的本地通信端口，不是网络代理，不能删除或改成 VDI 服务器地址。

Compose 固定使用 MAC `02:42:ac:12:00:02`。如果同一二层网络中需要同时运行多份
该项目，请为每份实例设置不同的 MAC。

## X11 授权

登录界面以当前宿主用户对应的 UID 运行，而厂商的 `vdi_session` 是 setuid-root
程序。两者都需要访问 X Server。`run.sh` 仅添加以下两项精确授权，并在退出时
自动撤销：

```bash
xhost +SI:localuser:$(id -un)
xhost +SI:localuser:root
```

脚本没有使用会关闭全部 X11 访问控制的 `xhost +`。

如果不使用 `run.sh` 而是手动执行 Compose，需要自行添加并撤销上述授权。

## libusb 兼容修复

客户端安装包带有较旧的 `libusb-1.0.so.0.1.0`。在较新的宿主内核上，会话可能在
成功连接显示通道后崩溃，日志通常表现为：

```text
UsbRedirectorManager::start_hotplug_event_listener
signal 11
```

Dockerfile 显式安装 Ubuntu 20.04 的 `libusb-1.0-0`，并让客户端的 ABI 链接指向
系统实现：

```text
/lib/x86_64-linux-gnu/libusb-1.0.so.0
```

该修复已经验证可以完成 X11 初始化、远程显示通道连接和 USB 热插拔回调注册。

## Qt4 与顶部托盘图标

此版本 deb 已自带 Ubuntu 20.04 所需的 Qt 4.8.7，包括 `libQtCore.so.4`、
`libQtGui.so.4` 和 `libQtNetwork.so.4`，不需要从非官方旧源安装 `libqtgui4`。

GNOME Shell 和托盘运行在宿主机，不在容器中。在 Ubuntu 20.04 宿主机看不到托盘
图标时，可在宿主机安装：

```bash
sudo apt-get install gnome-tweaks gnome-shell-extension-top-icons-plus
```

注销并重新登录后，在“优化 → 扩展”中启用 TopIcons Plus。

## 保存与加载镜像

导出离线镜像：

```bash
docker save -o sangfor-vdi-ubuntu20.04.tar sangfor-vdi:ubuntu20.04
sha256sum sangfor-vdi-ubuntu20.04.tar
```

在另一台机器加载：

```bash
docker load -i sangfor-vdi-ubuntu20.04.tar
```

`*.tar` 已被 `.gitignore` 排除，请通过合适的内部文件分发方式传输，不要提交到
源码仓库。

## 排查

查看容器状态和输出：

```bash
docker compose ps
docker compose logs --tail=200 sangfor-vdi
```

查看客户端关键日志：

```bash
container_id=$(docker compose ps -q sangfor-vdi)
docker exec "$container_id" tail -n 200 \
  /var/log/sangfor/vdiclient/vdi_session.log
```

- 每次点击都重新构建：确认使用的是 `./run.sh`，并确认镜像
  `sangfor-vdi:ubuntu20.04` 存在。
- 登录时提示网络异常：先检查 `vdi_webui_agent` 是否监听容器内部
  `127.0.0.1:31113`，不要把该地址误认为代理。
- 卡在“正在连接会话”：搜索 `open X display failed`，并确认通过 `run.sh` 启动。
- 远程桌面刚出现就退出：搜索 `signal 11`，并确认镜像内 libusb 链接指向系统库。

不要把完整日志直接提交到公开 Issue；日志可能包含用户名、服务器地址、会话令牌
或其他认证信息。

## 当前限制

- 纯 Wayland 且禁用 XWayland 时无法显示窗口。
- 默认没有把 `/dev/bus/usb` 或宿主内核模块交给容器，因此实际 USB 设备重定向
  不可用。开启它需要额外容器权限，会扩大安全边界。
- 音频依赖已安装，但项目没有默认挂载宿主机的 PulseAudio/PipeWire socket。
- 固定 MAC 适用于单实例；多实例需要分别配置。
