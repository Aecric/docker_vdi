FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG VDI_UID=1000
ARG VDI_GID=1000

ENV LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    QT_X11_NO_MITSHM=1 \
    QT_PLUGIN_PATH=/usr/local/sangfor/vdiclient/bin/imageformats \
    LD_LIBRARY_PATH=/usr/local/sangfor/vdiclient/lib

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        compton \
        dbus-x11 \
        fonts-noto-cjk \
        gosu \
        iproute2 \
        libasound2 \
        libconfig9 \
        libcups2 \
        libfontconfig1 \
        libfreetype6 \
        libgl1 \
        libglib2.0-0 \
        libglu1-mesa \
        libgtk2.0-0 \
        libnss3 \
        libnss3-tools \
        libpulse0 \
        libudev1 \
        libusb-1.0-0 \
        libx11-6 \
        libx11-xcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
        libxrender1 \
        libxtst6 \
        locales \
        net-tools \
        pciutils \
        procps \
        psmisc \
        sudo \
        tini \
        usbutils \
        xdg-utils \
    && locale-gen zh_CN.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Compatibility libraries required by the vendor binaries but omitted from
# the package metadata. Keep these separate so the large GUI layer is cached.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libice6 \
        libidn11 \
        libldap-2.4-2 \
        librtmp1 \
        libxkbfile1 \
        libxv1 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${VDI_GID}" vdi \
    && useradd --uid "${VDI_UID}" --gid "${VDI_GID}" --create-home --shell /bin/bash vdi

COPY vdi-linux-client-x86_64-ubuntu.deb /tmp/vdi-client.deb

# The vendor package bundles Qt 4.8.7 for Ubuntu 20.04. Its maintainer script
# also creates the Sangfor layout and symlinks, so libqtgui4 is not required.
# Its old bundled libusb crashes while registering hotplug callbacks on newer
# host kernels. Keep the ABI name but use Ubuntu 20.04's compatible libusb.
RUN mkdir -p /system/usr/share/hwdata /run/sangfor/vdiclient \
    && chmod 0777 /run/sangfor/vdiclient \
    && dpkg -i /tmp/vdi-client.deb \
    && ln -sfn /lib/x86_64-linux-gnu/libusb-1.0.so.0 \
        /usr/local/sangfor/vdiclient/lib/libusb-1.0.so.0 \
    && rm -f /tmp/vdi-client.deb \
    && chown -R vdi:vdi /home/vdi

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/sangfor/vdiclient/bin/vdi_local_client"]
