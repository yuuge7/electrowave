# Electrowave

A beautiful local music player for the desktop, built with Flutter. Plays your own files — no streaming, no accounts, no telemetry.

## Features

- **Library** — point it at a folder and it scans recursively, reading tags and embedded album art (via `metadata_god`). Individual file import also supported. Removing a track is a soft delete, so your play history survives.
- **Playback** — powered by `media_kit`/mpv. Play/pause, seek, next/previous, shuffle, and repeat (off / all / one).
- **Queue system** — playing a track from any list sets that list as the playback context. On top of that sits a manual queue: *Play next* and *Add to queue* on every track, with a queue panel to inspect what's coming.
- **Playlists** — create playlists, add tracks from anywhere in the library.
- **Play tracking** — a listen is logged once a track crosses 25% played, feeding play counts and last-played dates.
- **Stats ("Wrapped")** — total listening time, top tracks, and top artists, filterable by month, year, or all time.
- **Backup & restore** — export the SQLite database anywhere; imports are staged and applied safely on the next launch.
- **System tray** — closes to tray instead of quitting; restore or quit from the tray icon.
- **Single instance** — launching a second copy focuses the running window instead of duplicating it.

## Installation (Linux)

Grab the latest [release](../../releases) and pick your format:

| Distro | File | Install |
|--------|------|---------|
| Debian / Ubuntu | `electrowave-linux-installer.deb` | `sudo apt install ./electrowave-linux-installer.deb` |
| Fedora / RHEL | `electrowave-linux-installer.rpm` | `sudo dnf install ./electrowave-linux-installer.rpm` |
| Arch / CachyOS | `electrowave.pkg.tar.zst` | `sudo pacman -U electrowave.pkg.tar.zst` |

Runtime dependencies: `gtk3`, `mpv`, `libayatana-appindicator`.

A Windows build (`electrowave-windows-x64.zip`) is also attached to each release — unzip and run `electrowave.exe`.

## Building from source

Requirements: Flutter (stable channel) and, on Linux, the GTK/mpv development headers:

```bash
# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libayatana-appindicator3-dev
```

```bash
flutter pub get
dart run build_runner build   # drift codegen
flutter build linux --release   # or: flutter build windows --release
```

The bundle lands in `build/linux/x64/release/bundle/`.

## Project structure

```
lib/
├── core/database/      # drift schema: tracks, playback history, playlists
├── features/
│   ├── library/        # scanning, track list
│   ├── player/         # playback, queue, scrobbling
│   ├── playlists/
│   ├── settings/       # backup/restore, wrapped stats provider
│   └── stats/
└── shared/
    ├── services/       # tray, single instance, desktop integration
    └── widgets/        # main shell, bottom player bar, queue panel
```

## CI

- `build_desktop.yml` — test builds (Linux `.deb`/`.rpm`/`.pkg.tar.zst` + Windows) on every push to `testing`
- `releases.yml` — builds and publishes a GitHub Release on every push to `main`

## License

See [LICENSE](LICENSE).
