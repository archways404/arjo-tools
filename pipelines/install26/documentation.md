# arjo-tools — Install26 Pipeline (Ignition)

Unattended, post-imaging setup pipeline for new/refreshed laptops. One
command runs an orchestrator (`setup.ps1`) that pulls and executes a fixed
sequence of components straight from GitHub, reports live progress to a
central metrics service, and — for the one step that needs it (Lenovo
driver/firmware updates) — survives multiple reboots on its own until
finished.

---

## 1. What it does, in one paragraph

`setup.ps1` runs four steps in order — **Power Settings → Microsoft Teams →
PC Metrics → Lenovo Drivers**. Each step's script is fetched fresh from
GitHub and executed in-memory (`iex`), so the machine always runs whatever
is currently on `master`. Every step reports its progress to
`https://arjo-metrics.k14net.org/install-status` (for the dashboard/API) and
mirrors every log line over UDP to `arjo-metrics.k14net.org:9999` (for live
tailing during deployment). If any step before Lenovo fails, the pipeline
stops, runs `cleanup.ps1`, and exits with an error. The Lenovo step is
different: it can trigger a reboot mid-pipeline, and resumes itself
afterward via a scheduled task — the orchestrator's job for that step ends
once it's kicked off; `drivers.ps1` manages its own status reporting from
then on.

---

## 2. Running it

From an elevated PowerShell prompt on the target machine:

```powershell
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/setup.ps1")
```

*(Adjust the URL/shortlink to whatever entry point you've actually wired
up — the pipeline itself references its components relative to
`pipelines/install26/components/` on `master`, so `setup.ps1` needs to live
one directory above that.)*

You do **not** need to run this as SYSTEM or pre-elevate every step
individually — the orchestrator itself just needs to run elevated once;
the Lenovo step handles its own re-elevation if it somehow ends up
non-elevated (see [§5.4](#54-self-elevation)).

---

## 3. Architecture

```
pipelines/install26/
├── setup.ps1                  # orchestrator (this doc's main subject)
└── components/
    ├── power.ps1               # wired into $steps
    ├── teams.ps1                # wired into $steps
    ├── metrics.ps1               # wired into $steps
    ├── drivers.ps1                # wired into $steps (= lenovo-updates.ps1 logic)
    ├── cleanup.ps1                 # auto-run by setup.ps1 on failure
    ├── removal.ps1                  # NOT auto-run — manual full-uninstall utility (see §8)
    ├── logitech_g_hub.ps1             # NOT wired into $steps — standalone/optional (see §7)
    └── vxl.ps1                         # NOT wired into $steps — per-user only (see §7)
```

Only **power, teams, metrics, drivers** are part of the automated
`$steps` array in `setup.ps1`. `cleanup.ps1` is invoked automatically, but
only on failure. `removal.ps1`, `logitech_g_hub.ps1`, and `vxl.ps1` exist in
the repo as available components but are **not called by `setup.ps1` at
all** — see [§7](#7-components-not-wired-into-the-pipeline) and
[§8](#8-removalps1--full-uninstall-manual-only) for what they're for and
how to run them.

### How a component gets loaded

`Invoke-PipelineScript -Url $step.Url -EntryPoint $step.EntryPoint`:

1. Downloads the raw script content as text (`Invoke-WebRequest`, content
   only — not saved to disk except by `drivers.ps1` itself, see
   [§5.2](#52-persistence--the-one-exception)).
2. Strips a UTF-8 BOM if present.
3. `iex`'s the content — this defines the component's function(s) in the
   current session.
4. If `EntryPoint` is non-empty, calls that function.

---

## 4. Logging & telemetry

Two independent channels, both **best-effort** — neither blocks or fails
the pipeline if unreachable:

| Channel | Destination | Purpose | Failure behavior |
|---|---|---|---|
| UDP broadcast | `arjo-metrics.k14net.org:9999` | Every `Log` call is mirrored as a raw UDP packet (`PCNAME \| HH:mm:ss \| [LEVEL] message`) for live tailing during a deployment | Wrapped in try/catch, silently dropped if unreachable — `Init-UdpLogger`/`Send-UdpLog` never throw |
| HTTP status API | `https://arjo-metrics.k14net.org/install-status` (POST) | Structured JSON progress per pipeline stage, for a dashboard/tracking system | `Send-PipelineStatus` swallows errors (`-ErrorAction SilentlyContinue`); `drivers.ps1`'s equivalent (`Send-InstallStatus`) additionally **queues failed POSTs to disk** and retries them later (see [§5.3](#53-status-queueing-network-resilience)) |

### Status payload shape (`Send-PipelineStatus` / `Send-InstallStatus`)

```json
{
  "PCName": "PC021051",
  "Serial": "R90ABCDE",
  "Stage": "teams",
  "Status": "running",
  "Message": "Running Microsoft Teams",
  "CurrentStep": "Microsoft Teams",
  "CompletedSteps": 1,
  "TotalSteps": 4,
  "Timestamp": "2026-08-07T09:15:00.000Z",
  "Extra": { "Pipeline": "install26" }
}
```

`Status` values used across the pipeline: `running`, `completed`, `failed`,
`warning`, `rebooting`.

---

## 5. Step-by-step breakdown

### 5.1 Step 1 — Power Settings (`power.ps1` → `Set-PowerSettings`)

Applies one policy to the **active** power scheme (whatever it is):

- Lid-close action → **Do Nothing** (both AC and DC)
- Sleep timeout (AC) → **Never**
- Monitor timeout (AC) → **Never**

Simple, synchronous, no network calls of its own. Fails only if
`powercfg` itself errors.

### 5.2 Step 2 — Microsoft Teams (`teams.ps1` → `Install-MicrosoftTeams`)

1. Skips entirely if `Get-AppxPackage -Name "MSTeams"` already shows it
   installed.
2. If `winget` is available: installs via `winget install --id
   XP8BT8DW290MPQ --source msstore` (silent, auto-accept agreements).
3. If `winget` is **not** available: falls back to downloading the Teams
   bootstrapper (`go.microsoft.com/fwlink/?linkid=2243204`) to `%TEMP%`
   and running it silently (`-p`), then deletes the temp file regardless
   of success/failure (`finally` block).

### 5.3 Step 3 — PC Metrics (`metrics.ps1` → `Send-PCInfo`)

Collects and POSTs a hardware/OS inventory snapshot to
`https://arjo-metrics.k14net.org/pc-info` (a **separate** endpoint from
the pipeline status API):

| Field | Source |
|---|---|
| `PCName` | `Win32_ComputerSystem.Name` |
| `Manufacturer` | `Win32_ComputerSystem.Manufacturer` |
| `Model` | `Win32_ComputerSystem.SystemSKUNumber`, with any `...FM_` prefix stripped |
| `ProductCode` | `Win32_BaseBoard.Product` |
| `Serial` | `Win32_BIOS.SerialNumber` |
| `MACAddresses` | MAC of the first **Up**, physical, non-Wi-Fi/non-Bluetooth adapter whose name starts with `Ethernet` |
| `OSCaption` | `Win32_OperatingSystem.Caption` |
| `OSRelease` | `DisplayVersion` from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` |
| `OSBuild` | `Win32_OperatingSystem.BuildNumber` |

The submitted values are echoed to console/UDP after sending, so you can
visually confirm what was captured during a live deployment.

This script also has a **standalone fallback**: if run directly (not
dot-sourced) and no `Log` function exists in scope yet, it defines a
minimal local one — so it can be tested in isolation without the full
pipeline loaded.

### 5.4 Step 4 — Lenovo Drivers (`drivers.ps1` → `Start-LenovoUpdates`)

By far the most involved step, because Lenovo driver/BIOS installs
routinely require **multiple reboots**, and the pipeline needs to survive
all of them unattended. Key mechanisms:

#### Single-instance lock
A named global mutex (`Global\ArjoLenovoUpdatesMutex`) prevents two
copies running simultaneously — relevant because this step re-launches
itself after every reboot via a scheduled task.

#### Persistence — the one exception
Unlike every other step (which runs purely in-memory via `iex`), this is
the **only** component that writes itself to disk:
`C:\ProgramData\ArjoTools\lenovo-updates.ps1`. It has to — a scheduled
task needs a real file path to point `-File` at after reboot; you can't
schedule an in-memory `iex` blob.

#### Self-elevation
If `Start-LenovoUpdates` finds it isn't running elevated, it builds a
base64-encoded bootstrap command (re-downloads itself to
`C:\ProgramData\ArjoTools\lenovo-updates.ps1`, then relaunches with
`-AutoRun`) and calls `Start-Process ... -Verb RunAs` to trigger a UAC
elevation prompt. This path assumes an interactive session — under the
main pipeline (elevated already) it's not hit.

#### The resume task
`Register-ResumeTask` creates a scheduled task named **`Ignition
LenovoDriverUpdate`**:
- Trigger: **At startup**, 2-minute delay
- Runs as: **SYSTEM**, highest privileges, no login required
- Command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
  "C:\ProgramData\ArjoTools\lenovo-updates.ps1" -Resume -AutoRun`
- Settings: runs on battery, doesn't stop on battery, retries 5× at
  5-minute intervals, 3-hour execution time limit

The task is only removed once there are genuinely no updates left
(`Complete-Run` → `Remove-ResumeTask`).

#### The update loop
Up to **5 rounds**. Each round:
1. `Get-LSUpdate` scans for available updates (a known LSUClient quirk —
   `"Argument types do not match"` thrown *after* the scan still
   completes — is caught and treated as non-fatal, using whatever updates
   were already collected).
2. If zero updates found → `Complete-Run` (writes
   `LenovoUpdatesCompleted.txt`, removes the scheduled task, reports
   `completed`, stops).
3. Otherwise: downloads all of them (`Save-LSUpdate`), then installs all
   of them (`Install-LSUpdate -SaveBIOSUpdateInfoToRegistry`) — reporting
   progress per-package to the status API throughout.
4. After install, if updates were installed **or** `Test-PendingReboot`
   detects a pending reboot flag (CBS `RebootPending`, WU
   `RebootRequired`, or a non-empty `PendingFileRenameOperations`) →
   reports `rebooting`, waits 30s, `Restart-Computer -Force`, and returns.
   The scheduled task picks it back up 2 minutes after the next boot.
5. If 5 rounds pass without finishing, it re-checks once more; if still
   not empty, reports a `warning` status and lets the scheduled task try
   again next startup rather than looping forever in one session.

#### Status queueing (network resilience)
If `Send-InstallStatus`'s POST fails (e.g. no network yet right after
boot), the JSON payload is appended to
`C:\ProgramData\ArjoTools\install-status-queue.jsonl` instead of being
lost. Every subsequent status send first calls `Flush-StatusQueue`, which
retries each queued line and only removes it from the file once it posts
successfully. `Start-LenovoUpdates` also explicitly waits up to 5 minutes
for the API to become reachable at the very start of each run
(`Wait-ForNetwork`) before proceeding.

#### Important behavioral note for the orchestrator
Because this step can legitimately end the *entire PowerShell process*
via `Restart-Computer`, `setup.ps1` treats it specially — after launching
it, `setup.ps1` does **not** overwrite its status with a `completed` call
the way it does for the other three steps (see the `if ($step.Stage -ne
"lenovo")` check). `drivers.ps1` reports its own final `completed`/`failed`/
`warning`/`rebooting` status independently, since it may still be running
across reboots long after `setup.ps1`'s own process has ended.

---

## 6. Failure handling

If any step **other than Lenovo's internal reboot loop** throws (Power,
Teams, Metrics, or Lenovo's own top-level bootstrap/elevation code before
it starts self-managing):

1. `setup.ps1` reports that stage as `failed` (with the exception message
   in `Extra.Error`).
2. The step loop breaks — no later steps run.
3. `cleanup.ps1` is fetched and run: it removes
   `C:\ProgramData\ArjoTools\lenovo-updates.ps1` only (not the whole
   `ArjoTools` folder — see [§8](#8-removalps1--full-uninstall-manual-only)
   for the difference from `removal.ps1`).
4. Cleanup's own success/failure is reported (`Stage: "cleanup"`).
5. The UDP logger is closed and the script `exit 1`s.

If everything succeeds, the script logs `"Pipeline completed. Lenovo task
may continue after reboot."` and closes the UDP logger — note the wording:
a clean exit here does **not** guarantee Lenovo updates are actually
finished, only that the pipeline successfully *kicked off* that step (or
that it already had nothing to do).

---

## 7. Components not wired into the pipeline

These exist in `components/` but `setup.ps1`'s `$steps` array never
references them. Run them manually/separately if needed.

### `logitech_g_hub.ps1`
Plain top-level script (no function wrapper, no `Log` calls) — downloads
and silently installs Logitech G HUB from `download01.logi.com`. Since it
doesn't call `Log`, it's safe to run standalone even outside the pipeline
context:

```powershell
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/components/logitech_g_hub.ps1")
```

### `vxl.ps1` (`Install-VXL2`)
Explicitly commented **"PER USER ONLY"** — do not run this as SYSTEM or
inside the Lenovo-style elevated/unattended flow. It:
- Adds a temporary Internet Zone trusted-site entry under **`HKCU`**
  (`vincesoftware.org\vpm2`) — a per-user hive, meaningless under SYSTEM.
- Launches a ClickOnce install via `rundll32 dfshim.dll,
  ShOpenVerbApplication` and drives the install dialog with
  **`SendKeys`** — this requires an actual interactive desktop session
  with a logged-in user, which SYSTEM/scheduled-task context doesn't
  reliably have.
- Removes the trusted-site entry again afterward.

Run this only while logged in as the actual user, e.g. after the main
pipeline has finished and the tech is doing final per-user app setup.

---

## 8. `removal.ps1` — full uninstall (manual only)

```powershell
Remove-Item -Path "C:\ProgramData\ArjoTools" -Recurse -Force
Log -Level SUCCESS -Message "Cleaned up C:\ProgramData\ArjoTools"
```

This deletes the **entire** `ArjoTools` working directory — logs,
`LenovoUpdatesCompleted.txt`, the status queue file, everything —  not
just the persisted Lenovo script the way `cleanup.ps1` does.

**Nothing in the current pipeline calls this automatically.** That means
after a fully successful run, `C:\ProgramData\ArjoTools` (logs, completion
marker, etc.) is left on disk indefinitely by design — useful for
after-the-fact troubleshooting/audit, but worth knowing if you expect the
folder to self-clean. Run `removal.ps1` by hand once you're done needing
that history for a given machine:

```powershell
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/components/removal.ps1")
```

Since it calls `Log` (not wrapped with a standalone fallback the way
`teams.ps1`/`metrics.ps1`/`vxl.ps1` are), make sure a `Log` function is in
scope first if running it outside a full pipeline session — otherwise
define one ad hoc or just run the `Remove-Item` line directly.

---

## 9. Files & paths reference

| Path | Written by | Purpose |
|---|---|---|
| `C:\ProgramData\ArjoTools\` | `drivers.ps1` | Base working directory for the Lenovo step |
| `C:\ProgramData\ArjoTools\lenovo-updates.ps1` | `drivers.ps1` (`Ensure-LocalScript`) | Persisted copy of the driver script — the only file the scheduled task can point to across reboots |
| `C:\ProgramData\ArjoTools\Logs\lsuclient_<timestamp>.log` | `drivers.ps1` (`Start-Transcript`) | Full PowerShell transcript per Lenovo run/resume |
| `C:\ProgramData\ArjoTools\LenovoUpdatesCompleted.txt` | `drivers.ps1` (`Complete-Run`) | Marker written once no updates remain — timestamp, computer, user context, log file path |
| `C:\ProgramData\ArjoTools\install-status-queue.jsonl` | `drivers.ps1` (`Add-StatusToQueue`) | Queued status POSTs that failed to send, retried on next flush |

| Name | Type | Notes |
|---|---|---|
| `Ignition LenovoDriverUpdate` | Scheduled task | Created by `Register-ResumeTask`, removed by `Complete-Run`. If a machine is stuck rebooting in a loop, this is the first thing to check (`Get-ScheduledTask -TaskName "Ignition LenovoDriverUpdate"`) |
| `Global\ArjoLenovoUpdatesMutex` | Named mutex | Prevents concurrent Lenovo update runs on the same machine |

---

## 10. Troubleshooting

| Symptom | Likely cause | What to check / do |
|---|---|---|
| Pipeline exits 1 right after a step starts | That step's script threw before completing | Check the console/UDP log for `[ERROR]` from that stage; the `Extra.Error` field in the failed status POST has the exception message |
| Machine reboots but Lenovo updates never resume | Scheduled task wasn't created, was deleted, or didn't fire | `Get-ScheduledTask -TaskName "Ignition LenovoDriverUpdate"` — check `State` and `LastRunTime`/`LastTaskResult` in Task Scheduler |
| Machine reboots repeatedly without ever finishing | Genuine repeated Lenovo update rounds (normal for BIOS+driver-heavy machines) vs. a stuck package | Check `C:\ProgramData\ArjoTools\Logs\lsuclient_*.log` for the most recent run — look for repeated identical `Install-LSUpdate` failures for the same title |
| `LenovoUpdatesCompleted.txt` never appears | Still mid-rounds, or hit the 5-round cap with updates still remaining (reported as `warning`, not `failed`) | Check status API / logs for a `warning` status with `Stage: lenovo-updates` — this is expected to retry on next scheduled-task startup, not a hard failure |
| PC Metrics step "succeeds" but no data shows up in the dashboard | POST to `/pc-info` is fire-and-forget with `-ErrorAction Stop` inside its own try/catch — a failure there logs `[ERROR] Failed to send PC info` but doesn't fail the pipeline stage itself | Check the console output for that specific error line; the pipeline's own `completed` status for the `metrics` stage only reflects that `Send-PCInfo` didn't throw an *uncaught* error, not that the POST necessarily succeeded |
| `install-status-queue.jsonl` keeps growing | API endpoint (`arjo-metrics.k14net.org`) unreachable from that network segment | Confirm DNS/firewall reaches `arjo-metrics.k14net.org` on the relevant ports; once reachable, the queue drains automatically on the next status send |
| Teams installs via bootstrapper every time instead of winget | `winget` genuinely not present/not on PATH on that image | Expected fallback behavior — not an error. If you want winget used going forward, make sure it's part of the base image |
| VXL2 install does nothing / times out | Was run as SYSTEM or in a non-interactive session | Re-run interactively as the logged-in user — see [§7](#7-components-not-wired-into-the-pipeline) |
| `C:\ProgramData\ArjoTools` still present long after deployment finished | Expected — nothing auto-cleans it (see [§8](#8-removalps1--full-uninstall-manual-only)) | Run `removal.ps1` manually once you no longer need the logs/history |

---

## 11. Quick reference — manual recovery on a stuck machine

```powershell
# 1. Check if the resume task exists and its last result
Get-ScheduledTask -TaskName "Ignition LenovoDriverUpdate" | Select State
Get-ScheduledTaskInfo -TaskName "Ignition LenovoDriverUpdate"

# 2. Check the latest Lenovo transcript
Get-ChildItem "C:\ProgramData\ArjoTools\Logs" | Sort-Object LastWriteTime -Descending | Select -First 1

# 3. Check for a completion marker
Test-Path "C:\ProgramData\ArjoTools\LenovoUpdatesCompleted.txt"

# 4. Manually re-trigger the Lenovo step (elevated)
& "C:\ProgramData\ArjoTools\lenovo-updates.ps1" -Resume -AutoRun

# 5. Full manual wipe (only once genuinely done with the machine)
Remove-Item -Path "C:\ProgramData\ArjoTools" -Recurse -Force
Unregister-ScheduledTask -TaskName "Ignition LenovoDriverUpdate" -Confirm:$false -ErrorAction SilentlyContinue
```
