# RAWmakase in a browser

A container that runs the released Linux build of
[RAWmakase](https://github.com/pch/rawmakase) on a virtual display and streams it
to a browser, on LinuxServer's
[Selkies](https://github.com/linuxserver/docker-baseimage-selkies) baseimage.

The app is not changed, patched or ported in any way: Selkies is a remote
display, so a browser session gets the same binary a desktop install runs. The
image is a thin layer over a released `.deb`, in the spirit of
`linuxserver/docker-darktable` (the same approach for another native RAW
developer).

This is not an official image. Neither the RAWmakase project nor LinuxServer
publishes it, and anyone redistributing it should read LinuxServer's
[container branding](https://docs.linuxserver.io/general/container-branding/)
policy first.

## What works without a GPU

The target is a host with no GPU at all, so the image ships Mesa's software
rasterizers and mounts no device:

- **Drawing the window.** wgpu asks for a presentable adapter; lavapipe
  (`mesa-vulkan-drivers`) is a software Vulkan device that can present, so the
  window opens and the stream carries it. `WGPU_BACKEND=gl` with
  `libgl1-mesa-dri` (llvmpipe) is the fallback if Vulkan is unavailable.
- **Previews.** The engine refuses software and OpenGL adapters for its compute
  path, so `PreviewRenderer` falls back to the CPU renderer
  ([preview_renderer.rs](https://github.com/pch/rawmakase/blob/main/crates/rawmakase-engine/src/develop/preview_renderer.rs)).
  That is the same renderer export already uses, so results are identical, only
  slower.
- **Encoding.** Selkies encodes on the CPU with x264. Enable **FullColor 4:4:4**
  in the web client's sidebar for accurately colored photos and crisp text.

Expect Fit, the library and the inspector to be comfortable, and full-size 1:1
renders of large RAW files to be the slow part. Measure with your own files
before promising a frame rate.

With a GPU on the host, mount it (`--device /dev/dri`, drop `AUTO_GPU=false`)
and previews use the GPU instead; the base image also gets zero-copy encoding.

## Quick start

The published image is built for amd64 and arm64 from the same Dockerfile:

```bash
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ./config:/config -v /path/to/photos:/photos:ro \
  ghcr.io/phlogi/rawmakase-selkies:latest
```

To build it yourself instead:

```bash
git clone https://github.com/Phlogi/rawmakase-selkies.git
cd rawmakase-selkies
docker compose up -d --build
```

Either way, open <https://localhost:3001> and accept the self-signed certificate.
The web client opens on a Play overlay over a black canvas: the stream starts on
the first click, not on page load. Give the session at least 1280×720 in the web
client's sidebar, since the app's window does not go below 900×650.

Port 3000 is plain HTTP and only for a reverse proxy that terminates TLS; the
stream needs a secure context, so browse 3001 directly.

## Published images

[`publish.yaml`](.github/workflows/publish.yaml) builds both architectures and
pushes them to `ghcr.io/phlogi/rawmakase-selkies` whenever `main` changes, and
on a manual run with publishing switched on. Pull requests build the same two
images without publishing them.

| Tag | Meaning |
| --- | --- |
| `latest`, `<version>` | Manifest lists covering `linux/amd64` and `linux/arm64`; `<version>` is the RAWmakase release the image installs. |
| `latest-amd64`, `<version>-amd64`, and the same for `arm64` | The single-architecture images those manifests point at, for pinning one. |

The repository and its package are private for now, so pulling needs a login:
`docker login ghcr.io` with a token that has `read:packages`. Making the
repository public and making the container package public are two separate
steps, and the package is not published by making the repository public.

### Keeping up with RAWmakase releases

RAWmakase publishes new Linux packages often, and this image only has to pin a
version to pick one up. Once a day,
[`update-app.yml`](.github/workflows/update-app.yml) asks GitHub for the latest
release (prereleases and drafts are ignored), checks that the two `.deb` files
the image installs are really attached to it, moves the pin in the Dockerfile,
commits and then dispatches the publish run. A release without those packages
fails the run instead of building an image around a version it cannot install.

The Dockerfile is the only place the version is written down, so there is
nothing else for the bot, or for a person, to keep in step. A commit made with
the workflow's own token does not trigger other workflows, which is why the
update dispatches the publish run rather than relying on its push.

Dependabot watches the actions and the baseimage tag, but not the app version:
that comes from releases, not from a tag on an image.

## Photos

Photos arrive through a mount, and `compose.yaml` already expects one at
`./photos` next to the compose file. Read-only is enough to open, develop and
preview, and it is the right default for a folder you care about:

```bash
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ./config:/config \
  -v /Users/you/EditFotos:/photos:ro \
  ghcr.io/phlogi/rawmakase-selkies:latest
```

In the session, choose **Add Photo Folder…** and press Ctrl+L to type `/photos`.
`rawmakase [PATH]` takes a catalog or a single photo, not a folder, so adding a
folder is done in the app; `RAWMAKASE_CLI` passes the same argument at startup
(`-e RAWMAKASE_CLI=/photos/CYH_5249.NEF`) when the container should open
something specific.

Exports need a writable destination: `/config` always is one, or mount a second
folder read-write for them. Photos themselves are never written to.

### An existing library

A catalog records each photo's absolute path, and this container is another
computer to it, so mount the photo folder at the same path it has on the machine
that added the photos. Keep the catalog itself on a writable mount, because
every edit, folder change and location it learns is written to it:

```bash
mkdir -p ~/rawmakase-catalogs
cp /Users/you/EditFotos/Photos.rawmakase ~/rawmakase-catalogs/
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ./config:/config \
  -v /Users/you/rawmakase-catalogs:/catalogs \
  -v /Users/you/EditFotos:/Users/you/EditFotos:ro \
  ghcr.io/phlogi/rawmakase-selkies:latest
```

Open `/catalogs/Photos.rawmakase` with **Open catalog**: it is the copy, so the
original is untouched, and the photos resolve because the folder is mounted
where the catalog says they are. If something has moved on the host, the app's
relinking and **Synchronize Folder** handle it.

## Where the library and settings live

`/config` is the session user's home directory and the only thing that outlives
the container. Everything below is kept under it, so recreating the container or
rebuilding the image keeps the library, the edits and the settings; nothing has
to be imported again.

| Path under `/config` | What it holds |
| --- | --- |
| The `.rawmakase` catalog you choose | Metadata, every edit, develop history, spots, red eye, masks and a preserved Lightroom import. A fresh install starts its own catalog at `.local/share/rawmakase/Photos.rawmakase`. |
| `.local/share/rawmakase/session.json` | The app's settings: theme, panel and Library layout, last path, monitor profile, raw defaults, crop guides, demosaic, and whether onboarding finished. |
| `.local/share/rawmakase/camera-profiles/` | DCP profiles imported with **Import profile…** (including ones copied from a Camera Raw install) or `rawmakase import-profiles`. |
| `.local/share/rawmakase/lens-profiles/` | Adobe `.lcp` lens profiles imported with `rawmakase import-lens-profiles`. |
| `.local/share/rawmakase/xmp-presets/` | Imported XMP presets, with `Imported/` for the ones the app copied; `preset-favorites.json` and `curves/` sit beside it. |
| `.local/share/rawmakase/` | `themes/` (imported themes), and the usage-report state: `usage-stats.json` and the installation's random `computer-id-*`. |
| `.local/share/rawmakase/previews.sqlite3`, `.cache/rawmakase/decoded/` | Library thumbnails and developed camera images. Disposable caches, remade on demand; the decoded folder is capped at 4 GB, least recently used removed first. Losing them costs time, not edits. |

Imported profiles and presets are ordinary files in the data directory, so they
persist exactly like the catalog does: import them once in the browser and they
are still there in the next container. `RAWMAKASE_DATA_DIR` and
`RAWMAKASE_CACHE_DIR` move the data directory and the decoded cache onto other
mounts if you prefer, in which case mount those too. The app's own account of
these locations is in its
[data map](https://github.com/pch/rawmakase/blob/main/docs/code-map.md).

## How it is put together

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Installs the released `.deb` over the Selkies baseimage and the extra runtime pieces (portals, fonts, software rasterizers). |
| `root/defaults/autostart_wayland` | The command labwc starts: `rawmakase`, plus `RAWMAKASE_CLI` for user arguments. |
| `root/defaults/autostart` | The same for the Openbox/X11 stack (`PIXELFLUX_WAYLAND=false`). |
| `root/defaults/menu*.xml` | Right-click menu with a terminal and RAWmakase, so a closed app can be brought back. |
| `compose.yaml` | Ports, volumes, `shm_size` and the CPU-only environment. |
| `.github/workflows/publish.yaml` | Builds amd64 and arm64 and pushes them to ghcr.io, merging the two into manifest lists. |
| `.github/workflows/update-app.yml` | Moves the pinned RAWmakase version to the latest release and republishes. |
| `.github/dependabot.yml` | Keeps the actions and the baseimage tag current. |

Build arguments:

- `RAWMAKASE_VERSION` — the RAWmakase release to install, pinned in the
  Dockerfile and moved by the update workflow. Override it for a one-off build.
- `RAWMAKASE_DEB` — a full URL to a different package, for a local mirror, a
  nightly or a hand-built `.deb`.
- `BASE_IMAGE` — the baseimage, which LinuxServer tags per architecture:
  `debiantrixie` is amd64 and arm64 needs
  `arm64v8-debiantrixie`. CI passes the right one per platform; a local ARM
  build has to do the same.

Installing the package, rather than a copy of the binary in a portable folder,
is deliberate: dpkg owns `/usr/bin/rawmakase`, so the app's updater recognizes a
package-managed install and never tries to replace itself inside the container.
Move to a new release by rebuilding the image.

## Notes and limits

- **Not a headless service.** This runs the GUI. Unattended work belongs on the
  CLI subcommands (`rawmakase render`, `rawmakase control`), which need no
  display.
- **The app is not supervised.** If the session ends up without it, open the
  right-click menu and start RAWmakase again; the library and photos are
  unaffected.
- **One session per container.** The base image's authentication is a
  convenience for keeping the household out, not a hardened gateway. Expose it
  through SWAG or a VPN rather than the open internet.
- **MIDI.** The Linux build has no MIDI input (`midir` is macOS and Windows
  only), so the automation panel's MIDI rows do nothing here.
- **Display stack.** The image runs the baseimage's X11 stack, which is what the
  test below verifies. `PIXELFLUX_WAYLAND=true` switches to the Wayland stack
  (untested here; lavapipe does expose a Wayland surface).
- **Automation API.** The control protocol listens on loopback inside the
  container, so it is not reachable through a published port. Drive it from
  inside instead, after enabling the socket in Preferences:
  `podman exec -e HOME=/config rawmakase /usr/bin/rawmakase control state`.
  The app binary carries the client as its `control` subcommand, so nothing
  extra has to be installed.
- **Usage report.** A fresh install asks once about the weekly usage report. For
  kiosk or automated deployments set `RAWMAKASE_NO_TELEMETRY=1` (or
  `DO_NOT_TRACK=1`) to skip it. The released package has the feature in; a
  packager who builds from source can leave it out entirely with
  `--no-default-features`, which also drops the question and the Preferences
  row.
- **Masking models.** Subject, Sky and Background masking downloads its ONNX
  models on first use, so the container needs egress (or a pre-populated cache)
  for that feature.
- **Diagnostics.** `podman exec -it rawmakase bash`, then `pgrep -a rawmakase`,
  `cat /config/.config/openbox/autostart` on the X11 stack
  (`/config/.config/labwc/autostart` on Wayland), and
  `apt-get install -y vulkan-tools && vulkaninfo --summary` to see which adapter
  wgpu gets.

## Verification

Run on macOS arm64 with Podman 6.1.4 (libkrun VM, 10 CPUs, 3.7 GB RAM, no GPU)
and no devices mounted, using `rawmakase_0.3.2_arm64.deb` and a library of 174
NEFs. The plain `debiantrixie` tag is amd64 only, so the arm64 tag was passed
explicitly:

```bash
podman build --build-arg BASE_IMAGE=ghcr.io/linuxserver/baseimage-selkies:arm64v8-debiantrixie \
  -t rawmakase-selkies:0.3.2 .
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ~/rawmakase-config:/config -e AUTO_GPU=false rawmakase-selkies:0.3.2
```

Confirmed:

- The app runs in the session and initializes its catalog:
  `/config/.local/share/rawmakase` holds `Photos.rawmakase`, `session.json`,
  `previews.sqlite3`, `themes/` and the usage-report files, and the decoded
  cache appears at `/config/.cache/rawmakase/decoded`. Nothing writes to
  `/config/.config`, which the base image keeps for the desktop session.
- wgpu finds a presentable adapter with nothing mounted: `vulkaninfo --summary`
  reports a `PHYSICAL_DEVICE_TYPE_CPU` device, `llvmpipe (LLVM 19.1.7)` via
  lavapipe, with `VK_KHR_xcb_surface` and `VK_KHR_wayland_surface` available.
- The session runs the X11 stack (the baseimage default): Selkies logs
  `X11 (:1) capture, encoder h264enc` and `[pixelflux] No hardware encoder ...
  dlopen failed`, so encoding is software.
- The window renders. Captured with `xwd` inside the container and converted
  with `xwdtopnm | pnmtopng`, the screenshot shows the Library, the inspector
  and the first-run usage-report prompt, whose payload reads
  `"os": "linux", "arch": "aarch64", "channel": "deb", "display": "x11",
  "gpu": "cpu"`.
- A photo folder mounted read-only lists and reads: 174 NEFs appear under
  `/photos` in the session, and a write probe inside the container fails with
  `Read-only file system`, which is the point.
- The app can be brought back on a live display:
  `podman exec -d -u abc -e DISPLAY=:1 -e HOME=/config rawmakase
  /usr/bin/rawmakase` reopens the window on the running Xvfb, which is what the
  right-click menu does.
- `https://127.0.0.1:3001/` answers `200` inside the container.
- dpkg owns both `/usr/bin/rawmakase` and `/usr/lib/rawmakase/rawmakase`, so the
  install is package-managed and never self-updates.

Not verified, and worth doing before relying on this: a real browser session
across a network (stream latency, FullColor, clipboard, file dialogs), CPU
preview timings on large RAW files, importing a profile and reopening a catalog
after a rebuild, and the Wayland stack. The virtual screen starts at 1024×768
until a client connects and asks for more, so the window opens clamped to that
and wants maximizing afterwards.

## License

MIT, the same license as RAWmakase. See [LICENSE](LICENSE). RAWmakase is a
separate project; this repository only packages its releases.
