# A browser-streamed RAWmakase, on LinuxServer's Selkies base image
# (https://github.com/linuxserver/docker-baseimage-selkies). Selkies runs a
# window manager and the desktop build of the app on a virtual display, and
# streams that to a browser, so this image needs no port of the app.
#
# It installs the released Debian package, not a rebuild: the private LibRaw and
# Little CMS copies come with it, and an install that dpkg owns never
# self-updates (see "Build and releases" in the README).
#
# No GPU is required. Mesa's software Vulkan (lavapipe) gives wgpu an adapter
# that can draw the window; preview rendering sees a software adapter and falls
# back to the CPU renderer, which is the same path export uses.
# Pinned to the multi-arch index digest: Dependabot advances it when
# LinuxServer publishes a new build, and the tag stays for readability.
FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie@sha256:793fc3628ad6e089aecfd9f862de3ad5d9df05f1db783363c812f77d6541ccc3

# The release to install. This line is the only place the app version is
# written down: the update workflow moves it, the publish workflow tags the
# image with it, and nothing else repeats it. RAWMAKASE_DEB overrides the whole
# URL, for a local mirror, a nightly or a hand-built package.
ARG RAWMAKASE_VERSION=0.7.2
ARG RAWMAKASE_DEB=

ARG DEBIAN_FRONTEND=noninteractive

ENV TITLE="RAWmakase" \
    NO_GAMEPAD=true

# Upgrade the base image's packages first, so Debian security fixes published
# after LinuxServer built it are included even when the base digest is unchanged.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64|arm64) ;; *) echo "No RAWmakase package for $arch" >&2; exit 1 ;; esac; \
    url="${RAWMAKASE_DEB:-https://github.com/pch/rawmakase/releases/download/v${RAWMAKASE_VERSION}/rawmakase_${RAWMAKASE_VERSION}_${arch}.deb}"; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/rawmakase.deb "$url"; \
    apt-get install -y --no-install-recommends \
        /tmp/rawmakase.deb \
        fontconfig fonts-dejavu-core \
        libgl1-mesa-dri mesa-vulkan-drivers \
        xdg-desktop-portal xdg-desktop-portal-gtk; \
    rm -f /tmp/rawmakase.deb; \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# The app's catalog, session and presets live in the home directory, which is
# /config, so they survive image updates and PUID/PGID remapping.
COPY /root /

EXPOSE 3000 3001
VOLUME /config
