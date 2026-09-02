---
name: zapret-gui
description: >-
  Works on the Flowseal zapret-discord-youtube GUI wrapper (zapret-gui.ps1).
  Use when changing the zapret UI, strategies, user lists, Discord/YouTube
  live checks, service install, or packing the EXE.
---

# Zapret GUI wrapper

## Architecture

- **Wrapper only.** Do not patch `general*.bat` / `service.bat` in the zapret folder; GitHub updates replace them.
- **User lists:** `lists\list-general-user.txt` (and other `*user*.txt`). The GUI discovers them; strategies already wire `list-general-user`.
- **Live Discord/YouTube:** hosts from `utils\targets.txt` (`DiscordMain`, `DiscordGateway`, … / `YouTubeWeb`, …). Fallback URLs only if the file is missing. Custom poll hosts live in `%APPDATA%\ZapretGUI\settings.json` (`CustomHealthHosts`); the main window shows a third column only when that list is not empty.
- **Two windows:** main = status, start/stop, live checks, add-site. Settings = path, strategies, service, tests, lists, custom poll hosts, log. About is a small dialog from the left-rail **i** button (it also checks GitHub for a newer wrapper). The beetle button under it opens a GitHub issue and copies the GUI log to the clipboard. After a GUI self-update, rewrite Windows Startup to the new EXE path.
- **Window host:** `[ZapretUiHost]::StartMainLoop()` / `ShowSettings()`. Read the PowerShell WPF skill before touching window lifetime.

## Version / download

- **Versions:** wrapper version is `VERSION` in the project root (shown as GUI x.y.z). Zapret package version comes from `LOCAL_VERSION` in `service.bat`. Running state is scanned from service `zapret` and process `winws` (path matched to the connected folder).
- When GUI behavior changes: bump `VERSION` and add an entry to `CHANGELOG.md`. Pack the EXE with `build-exe.ps1` into local `dist/`. Do not `git push` or publish a GitHub Release unless the user explicitly asks.
- Restore a snapshot: `git checkout vX.Y.Z`. Do not move or delete existing tags (`v1.0.20` is the first public snapshot).
- Releases API for the zapret engine zip. Overlay shows download progress. Remember path in `%APPDATA%\ZapretGUI\settings.json`.

## Service

Install by capturing `winws.exe` args from the running strategy (same idea as `service.bat` → Install Service): `sc create zapret … start= auto`. Do not reimplement by rewriting strategy bats.

## Process and service safety

- Match `winws.exe` by its resolved executable path under the connected zapret root. Never stop every process by name or capture the first command line returned by CIM.
- Preserve the existing `zapret` service definition before tests or replacement. Restore it if testing is cancelled, no strategy passes, or installation fails.
- A strategy with zero successful target checks is not a valid “best” result.
- Do not remove shared WinDivert services without proving this installation owns them.
- Invoke `sc.exe` with an argument array. Do not build an elevated `cmd.exe /c` string from paths or captured process arguments.
- Download only the expected release asset, reject archive entries outside the extraction root, and verify upstream checksums/signatures when available.
- Keep folder discovery and selection read-only. Validate the package and require an explicit user action before executing any discovered `service.bat`, strategy, or utility with elevated rights.
- Prefer a valid explicitly saved `ZapretPath`; scan nearby folders only as fallback.
- Keep unpacked `zapret-discord-youtube-*` folders out of version control. Machine-local GUI state is `%APPDATA%\ZapretGUI\settings.json` (not a sidecar next to the EXE). Launch the root wrapper/packaged EXE, not a stale GUI copied inside the zapret package.

## When the GUI “fails to start”

If a MessageBox names `StartMainLoop` but the dark window is already visible, search the **Loaded handler, timer, log flush, and health-check UI**, not `ZapretUiHost`. Common crashes: `@($HealthResults)` on a `List[object]`, or `[void]` / `$null =` on a void .NET method (`List.Add`, `Enqueue`, `Inlines.Add`).
