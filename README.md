# Electrowave

An offline music library and player for Windows and Linux. Your own files, no accounts, no telemetry, no streaming, and no startup update checks.

## Listen and organize

- Add music folders in Settings or drop files and folders onto the window. Scans run in the background with progress and cancellation. Folders are rescanned on startup and watched for changes. Missing files stay visible and are skipped during playback.
- Browse tracks, albums, artists, folders, genres and years. Albums use album artist plus album name, including compilations and disc/track order. Tags and cover art are read in worker isolates with `audio_metadata_reader`; cached covers are resized for large libraries.
- Play through a gapless mpv playlist. Play next and Add to queue take priority over the original playback context. Shuffle, repeat, sleep timers, ReplayGain, playback speed and optional 0-12 second crossfade are available.
- Choose an output device or enable exclusive output in Settings. Exclusive mode resets speed and volume and disables processing and crossfade; actual exclusive access depends on the output driver and device.
- Use the 10-band EQ with automatic headroom, a preamp and custom presets. Presets can be exported and imported as JSON files.
- Windows system media controls and Linux MPRIS expose metadata and playback controls to the desktop. The tray, Now Playing view, local lyrics and always-on-top mini player provide other ways to listen.
- Click to select, Ctrl+click to toggle, Shift+click to select a range, and double-click or press Enter to play. Selection supports queueing, favorites, playlists, removal and bulk tag edits. Library removal is a soft delete; it keeps the file and history. Undo is offered after removal, playlist deletion and clearing the queue.
- Set 1-5 star ratings, find possible duplicates, put playlists into folders and define smart playlists with genre, artist, play-count, rating and year rules. Supported file writers save tags and cover art; MP3 ratings use POPM and FLAC ratings use Vorbis comments. Unsupported or read-only formats keep edits in the library and report the file-write limitation.
- Listening statistics measure audio actually heard, including crossfade tails. A play requires hearing 25% of the track. Export stats as CSV and playlists as M3U8; M3U/M3U8 import accepts local paths and skips network streams.
- The loudness scanner uses an installed `ffmpeg` executable to measure EBU R128 loudness and saves gain in the library. It does not re-encode audio or download ffmpeg. Enable normalization to use the measured gain when a file has no ReplayGain tags.

Formats: MP3, FLAC, M4A, Ogg, WAV, Opus, AAC, AIFF, WMA, APE, WavPack, MKA and DSF. Playback support follows the installed mpv build; metadata support varies by container.

## Shortcuts

| Key | Action |
| --- | --- |
| Space | Play / pause |
| Ctrl+F | Search library |
| Left / Right | Seek 5 seconds |
| Ctrl+Left / Right | Previous / next track |
| Ctrl+Up / Down | Volume |
| Ctrl+M | Mini player |
| Ctrl+N | Now Playing |
| Ctrl+A | Select all tracks in the focused list |
| Up / Down, Enter | Navigate tracks and play |
| Delete | Remove selected tracks |
| ? | Shortcut reference |

Shortcuts that affect playback leave text entry alone. Text size and light/dark/system appearance are in Settings. Window bounds and the paused playback session are remembered between launches.

## Data and recovery

All data stays on your computer:

- Windows: `%APPDATA%\Electrowave`
- Linux: `$XDG_DATA_HOME/electrowave` or `~/.local/share/electrowave`
- Portable: create an empty file named `portable` beside the executable; data then lives in `ElectrowaveData` beside it. Use a writable folder.

The database is `electrowave.sqlite`. Settings, session, covers, window state and rotating logs live alongside it. Existing Documents/Electrowave and legacy cover files are migrated automatically once; originals remain as recovery copies. Open the data and logs folders from Settings. Logs are never uploaded.

Export creates one `.ewbackup` ZIP containing a SQLite `VACUUM INTO` snapshot, settings, cached/referenced covers, session and a versioned manifest. Imports validate the database, manifest and archive paths, then stage the replacement for the next launch. A `before_import_*.ewbackup` recovery copy is saved before applying it. A filesystem journal rolls back an interrupted replacement. Imported session IDs are deliberately not resumed. Legacy `.sqlite` and `.db` backups remain importable.

Choose an automatic-backup folder in Settings to save weekly backups at startup and keep the latest five. Repair Broken Links prefers artist/album/path suffixes, then file size and duration. Ambiguous matches are left untouched.

## Install

Download a [release](../../releases).

- Windows: run `electrowave-setup.msi` for a per-user installation with Start menu, uninstaller and Open with associations. The ZIP remains available; extract all files and run `electrowave.exe`.
- Debian/Ubuntu: `sudo apt install ./electrowave-linux-installer.deb`
- Fedora/RHEL: `sudo dnf install ./electrowave-linux-installer.rpm`
- Arch/CachyOS: `sudo pacman -U electrowave.pkg.tar.zst`

Linux needs GTK 3, mpv and libayatana-appindicator. The desktop ID is `io.github.yuuge7.electrowave`; desktop-entry and icon names use that same ID.

## Build and test

Use Flutter stable with the Dart SDK constraint in `pubspec.yaml`. Windows needs the Visual Studio C++ desktop workload and Windows SDK. Linux development packages on Debian/Ubuntu:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libayatana-appindicator3-dev
flutter pub get
flutter analyze
flutter test
dart run build_runner build
flutter build linux --release
```

On Windows, use `flutter build windows --release`. Build the MSI with:

```powershell
./packaging/windows/build-installer.ps1
```

The script acquires the pinned WiX compiler from NuGet into the ignored build folder, includes the Visual C++ runtime, derives the version from pubspec.yaml and verifies the MSI tables. It leaves personal portable data out of the installer. Output: `build/installer/electrowave-setup.msi`.

Native audio/rendering tests are separate because they require a real mpv library and ffmpeg. On Windows, after a desktop build:

```powershell
$env:ELECTROWAVE_MPV = (Resolve-Path build/windows/x64/runner/Release/libmpv-2.dll).Path
$env:ELECTROWAVE_FFMPEG = (Get-Command ffmpeg).Source
flutter test test_native/audio_smoke_test.dart
```

These tests use generated audio and isolated temporary libraries. They cover native preloading/queue transitions, EQ and speed, crossfade, ffmpeg loudness measurement, and rendered desktop layouts including enlarged text. Rendered PNGs go to `build/verification`.

Run the desktop integration test to launch a visible app with real window, audio,
settings and session services (no platform mocks):

```powershell
flutter test integration_test/desktop_app_test.dart -d windows
```

It uses an isolated temporary library. Optional environment variables
`ELECTROWAVE_REPRO_DATABASE` (a database snapshot) and
`ELECTROWAVE_SETTINGS_SAMPLE` let it reproduce an existing library and settings;
`ELECTROWAVE_QA_OUTPUT` chooses where screenshots are saved. Existing music files
are played and read, while library changes stay in the temporary copy.

`build_desktop.yml` and `releases.yml` retain the existing desktop build/publishing structure. Both run analysis and unit/widget tests before building. Releases additionally build and verify the Windows MSI. No workflow is triggered or release published by a local build.

The repo intentionally omits Android, iOS and web application scaffolding. `web/music.png` remains because desktop icons and packaging use it. macOS runner sources are retained but are not part of the release matrix.

## License

[MIT](LICENSE).
