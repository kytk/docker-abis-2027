# ABiS Lin4Neuro launcher

Double-click launchers that hide the `docker` command line from tutorial
participants. `abis-2027-launcher-windows/` and `abis-2027-launcher-macos/`
contain the same four steps; only the platform-specific parts differ.
A fifth step changes Docker's resources from a script, which works
differently on each platform: `4_Configure_WSL` on Windows,
`4_Configure_Docker` on macOS (see below).

**Distribution.** The launchers are developed here but distributed from
<https://github.com/kytk/abis-web-2027>: the two archives are attached to a
GitHub Release of that repository, and participants fetch them with the
one-liners in `INSTALL_macos.md` / `INSTALL_windows.md`:

| Platform | URL |
|---|---|
| macOS | `https://github.com/kytk/abis-web-2027/releases/latest/download/abis-2027-launcher-macos.tar.gz` |
| Windows | `https://github.com/kytk/abis-web-2027/releases/latest/download/abis-2027-launcher-windows.zip` |

The scripts themselves are not committed to `abis-web-2027`; only the release
assets are. See "Before distributing" step 5.

| Script | When | What it does |
|---|---|---|
| `0_Check_Environment` | before the course | Writes `abis_check_result.txt`: OS, RAM, disk, Docker VM memory/CPU/disk, whether the image is present. Offers to start Docker Desktop if the engine is down, because none of the Docker figures can be measured without it. Participants send this file if something is wrong. |
| `1_Download_Image` | before the course, and to update | Confirms, then `docker pull` - **every time, also when the image is already there**. Compares the image ID before and after the pull to tell an update from a copy that was already current, and offers to delete the build it replaced. |
| `2_Start_Lin4Neuro` | every session | Docker check -> image check -> share folder dialog -> `docker run --rm` -> wait for HEALTHCHECK -> open noVNC. |
| `3_Stop_Lin4Neuro` | every session | `docker stop` (the container is removed by `--rm`), then offers to quit Docker Desktop. |
| `4_Configure_WSL` (Windows) | when `0_Check_Environment` says the memory is too small | Shows `%USERPROFILE%\.wslconfig`, sets `memory` / `swap` in `[wsl2]`, restarts WSL. Run again to undo. |
| `4_Configure_Docker` (macOS) | when `0_Check_Environment` says the memory is too small or Rosetta is off | Sets `MemoryMiB`, `SwapMiB` and (Apple Silicon) `UseVirtualizationFrameworkRosetta` in Docker Desktop's `settings-store.json`, restarting Docker Desktop. Run again to undo. |

## Design decisions

- **Disposable containers.** `docker run --rm` every time, and the share folder
  is chosen on every start. Nothing is installed inside the container during
  the course, so there is no state worth keeping - and a changed drive letter
  or a moved folder can never break a stored container.
- **Fixed image tag** (`kytk/abis-2027:26.12`), never `latest`, so that every
  participant runs the same environment for the whole season.
- **`1_Download_Image` always pulls.** The tag is fixed, but the image behind
  it is rebuilt during the season, so "the image is here" does not mean "the
  image is current". The pull transfers only the layers that changed, and the
  image ID from before it is compared with the one after, which is how the
  script knows what to report - docker's own output is localised. Two
  consequences are handled there: a pull that fails while a usable copy is
  already present is reported as "could not check for updates", not as an
  error; and after a successful update the build that was replaced is still on
  disk, untagged, taking its full ~38 GB, so the script offers to remove it
  (with `docker image rm`, no `-f`, which refuses while a container uses it).
- **Whole-GB requirements are compared after rounding.** Docker reports the
  memory of its VM minus the VM's own overhead - 8 GB assigned arrives as
  7.9 GB - and Windows reports installed RAM minus what the hardware reserves.
  Comparing those figures directly told correctly configured machines to raise
  a setting that was already at 8 GB. The exact figure is still displayed.
- **Docker's memory on Windows is set in `.wslconfig`, by a script.** With the
  WSL 2 backend (the default, and the only one on Windows Home) Docker
  Desktop's Settings -> Resources has no memory slider: the engine runs in the
  WSL 2 utility VM, which is sized by the `[wsl2]` section of
  `%USERPROFILE%\.wslconfig` (defaults: memory 50 % of RAM, swap 25 %).
  `4_Configure_WSL` sets `memory` to half of the RAM under 16 GB (the default,
  so Windows stays usable), otherwise RAM - 8 GB up to 32 GB
  (8 -> 4, 12 -> 6, 16 -> 8, 32 -> 24, 40+ -> 32), and `swap` to at least
  8 GB. It never lowers either value and changes nothing else:
  - every other line of an existing file is kept, and the participant's file
    is copied to `.wslconfig.abis-backup` once, before the first change;
  - a marker comment in `[wsl2]` records that the launcher changed it; with
    the marker present the script only offers to undo (restore the backup,
    or delete the file if there was none);
  - the file is written as UTF-8 without BOM - PowerShell 5.1's `Out-File`
    would write UTF-16, which WSL cannot read;
  - the change needs `wsl --shutdown`, which also stops every other WSL
    distribution, so the script asks first, refuses while Lin4Neuro is
    running, quits Docker Desktop before the shutdown and restarts it after.
  With the Hyper-V backend (detected from the engine's kernel, `linuxkit`
  instead of `...-WSL2`) `.wslconfig` has no effect and the script points to
  Settings -> Resources -> Advanced instead.
- **Docker's resources on macOS are set in `settings-store.json`, by a
  script.** Docker Desktop for Mac has sliders for all of it, but walking
  participants through the settings screens is slower than a double-click.
  `4_Configure_Docker` edits
  `~/Library/Group Containers/group.com.docker/settings-store.json`
  (Docker Desktop 4.35+; key names checked on a real Mac on 2026-10-13):
  `MemoryMiB` = the same target as on Windows, `SwapMiB` = 4096
  if smaller, and on Apple Silicon `UseVirtualizationFrameworkRosetta` =
  true - only when `UseVirtualizationFramework` is not false and Rosetta 2 is
  installed (`pgrep oahd`). This is an internal file, not a documented
  interface, hence:
  - only those keys are touched; the JSON is edited with
    `lib/docker_settings.js` through `osascript -l JavaScript` (part of every
    macOS - no jq or python3 needed), which keeps every other key and writes
    atomically. The same file runs under Node.js for testing;
  - Docker Desktop is quit first (it keeps its settings in memory and writes
    them back on quit) and started again afterwards if it was running;
    refused while Lin4Neuro runs;
  - the original values of exactly the changed keys are saved to
    `~/.abis-docker-settings` before writing; its presence means "changed by
    the launcher", and a second run only offers to put those values back.
    Restoring the keys, rather than a copy of the whole file, keeps whatever
    Docker Desktop itself changed in the meantime.
  The virtual disk size (`DiskSizeMiB`) is only reported, with advice to
  raise it in the GUI: shrinking it deletes every image, and whether an
  edited value is grown in place has not been tested.
- **`127.0.0.1:6080`,** not `0.0.0.0:6080`: the desktop has a published
  password, so it must not be reachable from the local network.
- **Docker Desktop is started by the scripts.** `0`, `1` and `2` launch it if
  the engine is not answering and poll `docker info` until it is (up to 180 s),
  instead of telling the participant to go and start it themselves. `3` does
  not - there is nothing to stop if Docker is down.
- **Waiting is done with the image's HEALTHCHECK** (`docker inspect
  --format '{{.State.Health.Status}}'`), which turns healthy only after the
  window manager is up *and* noVNC answers. No fixed sleep, no port guessing.
- **Start and stop are separate files** so that "clicking it again" cannot
  stop a running session by accident.
- **English code, Japanese messages.** Comments, identifiers and file names
  are English (file names stay ASCII so that they survive zipping and copying
  between platforms); every message shown to a participant is Japanese.

### Encoding rules - do not change these by accident

| File | Encoding | Why |
|---|---|---|
| `abis-2027-launcher-windows/lib/*.ps1` | **UTF-8 with BOM** | Windows PowerShell 5.1 reads a BOM-less `.ps1` using the system ANSI code page (CP932 on a Japanese Windows) and would show mojibake. |
| `abis-2027-launcher-windows/*.bat` | **Shift-JIS (CP932), CRLF** | `cmd.exe` renders console output in the OEM code page, which is 932 on a Japanese Windows. Same convention as `setup.bat` in this repository. |
| `abis-2027-launcher-macos/**` | **UTF-8, no BOM** | Terminal.app and bash 3.2 are UTF-8; a BOM would be executed as part of the first line. |
| `abis_check_result.txt` | UTF-8 (BOM on Windows) | Written by the check script; opens correctly in Notepad and in chat clients. |

One section is deliberately **English**: `[WSL2]` in the environment check.
`wsl.exe` writes UTF-16LE and localises its labels, so on a Japanese Windows
that text arrives mis-decoded through the console code page. The section is
built from ASCII values only - version numbers matched by a regular
expression, and distribution names from `wsl -l -q` / `wsl -l --running -q`,
which print no header and no localised state column.

To edit a `.bat`, convert to UTF-8 first and convert back afterwards:
`nkf -w in.bat > tmp` ... `nkf -s -Lw tmp > out.bat`.

## Before distributing

1. Push the image and set the tag in **both** config files:
   - `abis-2027-launcher-windows/lib/common.ps1` -> `$Script:ImageTag`
   - `abis-2027-launcher-macos/lib/common.sh` -> `IMAGE_TAG`
2. Tell the participants to run `1_Download_Image` again. It is what picks up
   a rebuilt image; `2_Start_Lin4Neuro` deliberately never pulls.
3. Check the download size and time shown in the confirmation dialog
   (`ImageSizeText` / `IMAGE_SIZE_TEXT`, `ImageTimeText` / `IMAGE_TIME_TEXT`).
   For `26.12` these are "about 20 GB" (measured: 18.3 GB compressed) and
   "40-60 minutes"; re-measure if the image is rebuilt.
4. Build both archives on a Mac, with one version number:

   ```
   ./make_release.sh                # version = today, YYYY.MM.DD
   ./make_release.sh 2026.10.13.2   # or explicitly
   ```

   Without an argument the version is today's date; if a release with that
   date already exists on `kytk/abis-web-2027`, `.2`, `.3`, ... is appended.
   The script asks before building when the launcher folder has
   uncommitted changes (commit first, so that the commit recorded in
   `VERSION.txt` describes the archive). It then runs the two archive scripts
   described below, which can also be run on their own.

   Each archive gets two generated files, written only into the staging copy
   (never into the source folder) by `release_common.sh`:

   - `VERSION.txt` - ASCII only: `version`, build time, git commit (with
     `(dirty)` if there were uncommitted files), image, release page URL.
     The launchers read its `version:` line and show it in every title and in
     `abis_check_result.txt` ("ランチャーの版"), so a tutor can tell from a
     participant's report which launcher they have. Without the file (scripts
     run from the repository) the version shows as `dev`.
   - `README.txt` - for participants, in Japanese, from
     `templates/README-<platform>.txt` (`@VERSION@`, `@BUILT@`, `@IMAGE@`,
     `@URL@` are filled in). UTF-8 + LF on macOS; UTF-8 with BOM + CRLF on
     Windows, like the scripts.

   The two archives are packed **differently on purpose**, so that each platform's way of
   extracting produces exactly one `abis-2027-launcher-*` folder and nothing
   nested inside it. Both are uploaded as GitHub Release assets of
   `kytk/abis-web-2027` (step 5); the one-liners in `INSTALL_*.md` use
   `releases/latest/download/...`, so the URL never changes between
   releases.

   - **Windows - no folder inside the archive.** Explorer's "Extract All"
     already creates a folder named after the zip, so an archive that also
     contains `abis-2027-launcher-windows/` extracts to
     `abis-2027-launcher-windows\abis-2027-launcher-windows\`. The *contents*
     are packed by:

     ```
     ./make_windows_zip.sh
     ```

     which also enforces the encoding rules below (a `.bat` with a BOM, in
     UTF-8 or with LF line ends, or a `.ps1` without a BOM, stops the build)
     and checks that bsdtar - the same libarchive as Windows' `tar.exe` -
     extracts it byte for byte.

     Participants install with the PowerShell one-liner in
     `INSTALL_windows.md`: `curl.exe` and `tar.exe` (built into Windows 10
     1803 and later) write no Mark of the Web, so SmartScreen never warns and
     no "Unblock" step is needed. It stays a zip, not a tar.gz, because the
     fallback - download in a browser, Properties -> Unblock, "Extract All" -
     must work on Windows 10, whose Explorer cannot open a tar.gz. The
     one-liner writes the zip to `%TEMP%` first: a PowerShell 5.1 pipe would
     corrupt binary data, and 5.1 has no `&&`, hence `if ($?) { ... }`.

   - **macOS - a tar.gz fetched with curl, not a zip.** A zip downloaded in a
     browser gets `com.apple.quarantine`, Archive Utility copies it onto every
     extracted file, and Gatekeeper then blocks each unsigned `.command`
     separately - on macOS 15 only through System Settings -> Privacy &
     Security -> "Open Anyway". `curl` and `tar` set no quarantine, so
     participants install with the one-liner in `INSTALL_macos.md` and nothing
     is ever blocked. Build the archive on a Mac with:

     ```
     ./make_macos_tarball.sh
     ```

     It copies the folder without extended attributes (macOS `tar` would
     otherwise pack them as `._*` entries - including `com.dropbox.attrs` from
     this Dropbox folder, or a quarantine flag if one is present), drops
     `.DS_Store` and `abis_check_result.txt`, sets scripts to 755, and verifies
     the result.

   `zip` adds to an existing archive instead of replacing it, so delete the old
   `.zip` first. The Windows zip must not contain `abis_check_result.txt`
   (written by `0_Check_Environment` when it is run from the folder).

5. Test the archives on a clean machine of each platform - see `TESTING.md`.

6. Publish them (needs `gh`, logged in with write access to
   `kytk/abis-web-2027`; runs on macOS or Linux):

   ```
   ./publish_release.sh             # new release launcher-<version>
   ./publish_release.sh --replace   # overwrite the files of that release
   ```

   The version is read from `VERSION.txt` inside the two archives - never
   typed in - and the script stops if the two disagree, if the release
   already exists (unless `--replace`), or if `gh` is missing or logged out.
   It shows the tag, commit, image and sha256 of both files and asks before
   publishing. The release is created with `--latest`: `releases/latest`
   resolves only to the newest release that is neither a draft nor a
   pre-release. Afterwards it downloads both files through the URLs in
   `INSTALL_*.md` and compares the checksums (with `--replace`, through the
   release's own tag URL, since it may not be the latest).

   Then install once with the one-liners in `INSTALL_*.md` and check that
   `README.txt` and the window titles show the new version.

## Files

```
make_release.sh          build both archives with one version (Mac)
make_macos_tarball.sh    build the macOS archive (called by make_release.sh)
make_windows_zip.sh      build the Windows archive (called by make_release.sh)
publish_release.sh       publish them as a release of kytk/abis-web-2027
release_common.sh        version and VERSION.txt / README.txt generation
templates/README-*.txt   participants' README.txt, per platform

abis-2027-launcher-windows/       abis-2027-launcher-macos/
  0_Check_Environment.bat           0_Check_Environment.command
  1_Download_Image.bat              1_Download_Image.command
  2_Start_Lin4Neuro.bat             2_Start_Lin4Neuro.command
  3_Stop_Lin4Neuro.bat              3_Stop_Lin4Neuro.command
  4_Configure_WSL.bat               4_Configure_Docker.command
  (VERSION.txt, README.txt)         (VERSION.txt, README.txt)
  lib/common.ps1                    lib/common.sh
  lib/check_environment.ps1         lib/check_environment.sh
  lib/pull_image.ps1                lib/pull_image.sh
  lib/start_lin4neuro.ps1           lib/start_lin4neuro.sh
  lib/stop_lin4neuro.ps1            lib/stop_lin4neuro.sh
  lib/configure_wsl.ps1             lib/configure_docker.sh
                                    lib/docker_settings.js
```

The `.bat` files exist only because `.ps1` files open in Notepad when
double-clicked; each one calls its `.ps1` with
`-NoProfile -ExecutionPolicy Bypass`, which applies to that process only and
changes no system setting.
