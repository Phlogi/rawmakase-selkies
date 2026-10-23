# RAWmakase in a browser

Runs the released Linux build of [RAWmakase](https://github.com/pch/rawmakase)
on a virtual display and streams it to a browser, using LinuxServer's
[Selkies](https://github.com/linuxserver/docker-baseimage-selkies) base image.
The app is not patched or ported: the browser gets the same binary a desktop
install runs. The image is a thin layer over the released `.deb`, in the spirit
of `linuxserver/docker-darktable`.

This is not an official image. Neither the RAWmakase project nor LinuxServer
publishes it; read LinuxServer's
[container branding](https://docs.linuxserver.io/general/container-branding/)
policy before redistributing it.

## Quick start

Images are published for amd64 and arm64:

```bash
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ./config:/config -v ./photos:/photos:ro \
  ghcr.io/phlogi/rawmakase-selkies:latest
```

To build it yourself instead:

```bash
git clone https://github.com/Phlogi/rawmakase-selkies.git
cd rawmakase-selkies
docker compose up -d --build
```

Open <https://localhost:3001> and accept the self-signed certificate. The
stream starts on the first click on the Play overlay, not on page load. Give
the session at least 1280x720, since the app window does not go below 900x650.
Port 3000 is plain HTTP for a TLS-terminating reverse proxy; browse 3001
directly because the stream needs a secure context.

## Photos and catalogs

`compose.yaml` mounts `./photos` read-only. In the session, choose **Add Photo
Folder...**, press Ctrl+L and enter `/photos`. Photos are never written to;
exports go to `/config` or another writable mount.

A catalog stores absolute photo paths, so an existing library must be mounted
at the same path it had on the machine that created it, and the catalog itself
needs a writable mount because edits and location changes are written to it:

```bash
mkdir -p ~/rawmakase-catalogs
cp /path/to/EditFotos/Photos.rawmakase ~/rawmakase-catalogs/
podman run -d --name rawmakase --shm-size=1gb -p 3001:3001 \
  -v ./config:/config \
  -v ~/rawmakase-catalogs:/catalogs \
  -v /path/to/EditFotos:/path/to/EditFotos:ro \
  ghcr.io/phlogi/rawmakase-selkies:latest
```

Open `/catalogs/Photos.rawmakase` with **Open catalog**. The original stays
untouched, and the app's **Synchronize Folder** relinks anything that moved.

The same mounts in `compose.yaml`, which ships them as commented examples:

```yaml
volumes:
  - ./config:/config
  - /path/on/host/EditFotos:/path/on/host/EditFotos:ro
  - ./catalogs:/catalogs
  - ./exports:/exports
```

`./photos` is the simple example: one folder, mounted at `/photos`. For an
existing library, the right-hand path must match the one in the catalog; the
left-hand path is wherever it lives on the host.

`RAWMAKASE_CLI` opens a catalog or a single photo at startup; the app's command
line does not accept a folder:

```bash
-e RAWMAKASE_CLI=/photos/CYH_5249.NEF
```

## Persistence

`/config` is the session user's home directory and the main persistent volume.
Everything the app creates by default lives there, so recreating the container
or rebuilding the image keeps the library, edits and settings:

| Path under `/config` | Contents |
| --- | --- |
| `.local/share/rawmakase/Photos.rawmakase` | The default catalog: metadata, edits, develop history, spots, red eye, masks, preserved Lightroom import. An existing catalog can live on its own mount (see above). |
| `.local/share/rawmakase/session.json` | Theme, panel and Library layout, last path, monitor profile, raw defaults, crop guides, demosaic and onboarding state. |
| `.local/share/rawmakase/camera-profiles/`, `lens-profiles/`, `xmp-presets/`, `themes/` | Imported DCP profiles, Adobe `.lcp` profiles, XMP presets and themes. |
| `.local/share/rawmakase/previews.sqlite3`, `.cache/rawmakase/decoded/` | Disposable thumbnail and decoded-image caches. The decoded cache is capped at 4 GB, least recently used removed first. |

`RAWMAKASE_DATA_DIR` and `RAWMAKASE_CACHE_DIR` move the data directory and the
decoded cache to other mounts if you prefer, in which case mount those too.

## GPU

The default is CPU only and mounts no device. Mesa's lavapipe gives wgpu a
software Vulkan adapter that can present the window, and preview rendering sees
a software adapter and falls back to the CPU renderer, the same path export
uses. Selkies encodes with x264; enable **FullColor 4:4:4** in the web client's
sidebar for accurate colors and crisp text. Expect 1:1 renders of large RAW
files to be the slow part.

With a GPU, mount `--device /dev/dri` and drop `AUTO_GPU=false`; previews then
use the GPU and the base image gets zero-copy encoding.

## Build and releases

Build arguments:

- `RAWMAKASE_VERSION` — the RAWmakase release to install. It is pinned only in
  the `Dockerfile`; the update workflow moves it and the publish workflow tags
  the image with it.
- `RAWMAKASE_DEB` — a full URL to a different package, such as a local mirror,
  a nightly or a hand-built `.deb`.
- `BASE_IMAGE` — the Selkies base image. LinuxServer tags it per architecture,
  so `debiantrixie` is amd64 and arm64 needs `arm64v8-debiantrixie`. CI passes
  the right one per platform; a local ARM build must do the same.

The package, rather than a copied binary, is installed deliberately: dpkg owns
`/usr/bin/rawmakase`, so the app never tries to self-update inside the
container. Move to a new release by rebuilding the image.

[`publish.yaml`](.github/workflows/publish.yaml) builds both architectures and
pushes `ghcr.io/phlogi/rawmakase-selkies` on changes to `main` or on a manual
run with publishing enabled. Pull requests build without pushing.

| Tag | Meaning |
| --- | --- |
| `latest`, `<version>` | Manifest lists covering `linux/amd64` and `linux/arm64`. |
| `latest-amd64`, `<version>-amd64`, and the same for `arm64` | Single-architecture images for pinning one platform. |

Once a day, [`update-app.yml`](.github/workflows/update-app.yml) checks
RAWmakase's latest release (prereleases and drafts ignored), verifies both
`.deb` files are attached, moves the pin and dispatches a publish run. A
release without those packages fails instead of producing an image it cannot
install.

## Notes and limits

- **Not a headless service.** This runs the GUI. Use the CLI subcommands
  (`rawmakase render`, `rawmakase control`) for unattended work.
- **The app is not supervised.** If it exits, start RAWmakase again from the
  right-click menu; the library and photos are unaffected.
- **One session per container.** The base image's authentication is a
  convenience, not a hardened gateway. Put it behind SWAG or a VPN rather than
  the open internet.
- **MIDI is unavailable.** The Linux build has no MIDI input, so the
  automation panel's MIDI rows do nothing.
- **Display stack.** The image runs the base image's X11 stack, which is what
  was tested. `PIXELFLUX_WAYLAND=true` switches to Wayland (untested).
- **Control API.** It listens on loopback inside the container, so it is not
  reachable through a published port. Enable the socket in Preferences, then:
  `podman exec -e HOME=/config rawmakase /usr/bin/rawmakase control state`.
- **Telemetry.** A fresh install asks once about the weekly usage report. Set
  `RAWMAKASE_NO_TELEMETRY=1` (or `DO_NOT_TRACK=1`) to skip it in kiosk or
  automated deployments.
- **Masking models.** Subject, Sky and Background masking download ONNX models
  on first use, so the container needs egress (or a pre-populated cache).
- **Diagnostics.** `podman exec -it rawmakase bash`, then `pgrep -a
  rawmakase`; `vulkaninfo --summary` (from `vulkan-tools`) shows the adapter
  wgpu gets.

## License

MIT, the same license as RAWmakase. See [LICENSE](LICENSE). RAWmakase is a
separate project; this repository only packages its releases.
