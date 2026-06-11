<div align="center">

# Arjo Tools

**Modular PowerShell setup utility for configuring ARJO machines.**
 
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows&logoColor=white)
![Admin](https://img.shields.io/badge/Admin-Recommended-orange)

![GitHub Release](https://img.shields.io/github/v/release/archways404/arjo-tools?sort=semver&display_name=release&style=flat&logo=iterm2&label=&color=3DDB00)

 
</div>

## 🔥 Ignition

**Ignition** is an automated laptop provisioning pipeline built for ARJO device deployments. It takes a factory-fresh machine and brings it to a fully configured, update-ready state in one command — minimal manual intervention and remote visibility throughout the process.

Currently powering the **NL2026 deployment** (NLTIE site, ~126 devices), with the goal of expanding to all ARJO sites.

### What it does

Ignition runs a sequential pipeline of setup stages, reporting live progress to the arjo-metrics API after each step. Every stage streams console output to the server in real time via UDP, so you can monitor what's happening on any machine without being in front of it.

| Stage | What happens |
|:-----:|--------------|
| **Power Settings** | Applies the standard ARJO power profile — lid close does nothing, AC sleep and monitor timeout set to never |
| **Microsoft Teams** | Installs the latest Teams via winget or bootstrapper fallback if winget isn't available |
| **PC Metrics** | Collects hardware info (name, model, serial, MAC, OS) and registers the device with arjo-metrics |
| **Lenovo Drivers** | Runs a full LSUClient driver and firmware update cycle — downloads all packages, installs them, reboots automatically if needed, and resumes after reboot until no updates remain |

The Lenovo driver stage is self-sustaining — it registers a scheduled task that survives reboots and keeps running as SYSTEM until every update is applied, then removes itself.

### Run it

Open **PowerShell** (admin recommended) and run:

```powershell
irm https://arjo-metrics.k14net.org | iex
```

That's it. The pipeline starts immediately and handles everything from there.

### How it reports

- **HTTP** — structured JSON status updates sent to `arjo-metrics.k14net.org/install-status` after each stage and substep. If the API is unreachable, updates are queued locally and flushed automatically once connectivity is restored.
- **UDP** — raw console output streamed line by line to port `9999` on the metrics server, giving a live feed of exactly what each machine is doing.

### Notes

- Designed for **Lenovo hardware** — the driver stage uses LSUClient and is specific to Lenovo devices.
- The Lenovo update stage will reboot the machine up to 5 times if needed. This is expected — the scheduled task resumes automatically after each reboot with no user interaction required.
- The pipeline is currently scoped to the NL2026 deployment but is built to be site-agnostic. Expanding to other ARJO sites is planned.

---

### Step 2 — auto-swc

Once Ignition has finished and the machine is fully updated, **auto-swc** handles the SoftwareCentral and device management configuration. This is a separate Playwright-based Node.js automation tool that runs after Ignition and takes care of everything that requires interacting with external systems on behalf of the device.

#### What it automates

| Task | Description |
|:----:|-------------|
| **Device naming in LogMeIn** | Renames the device in LogMeIn to the correct ARJO naming convention |
| **Device naming in SWC** | Sets the device name in SoftwareCentral to match |
| **Application install queue** | Adds the required applications to the SWC install queue for the device based on its department/role |
| **Device template assignment** | Assigns the correct SWC device template |
| **Locale & regional settings** | Configures locale, language, and regional settings appropriate for the target site |
| **AD description** | Sets the Active Directory description field for the device |

#### How it works

auto-swc is driven by a batch config file (`ini.json`) per department, so the same tool handles different device roles without any manual input per machine. You load the config for the relevant department, point it at the list of devices, and it processes the entire batch automatically.

---

## Quick Start (Interactive Menu)
 
Open **PowerShell** and run:

```powershell
iex (irm "https://arjo.k14net.org")
```

> **Backup** (direct link):
> ```powershell
> iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1")
> ```
 
An interactive menu will appear — pick what you need, then press `0` to exit when done.
 
---
 
## Menu Options
 
| # | Option | Description |
|:-:|--------|-------------|
| `1` | **Add Printers** | Installs and configures standard network printers |
| `2` | **Set Power Settings** | Applies the standard ARJO power profile |
| `3` | **Fix Teams Add-in** *(Outlook Classic)*  *DISABLED* | Re-enables the Teams Meeting add-in when inactive or crash-disabled |
| `4` | **Lenovo System Updates** *(IN BETA)* | Scans and installs Lenovo driver and firmware updates — relaunches elevated if needed |
| `5` | **View Lenovo Update Logs** *(IN BETA)* | Lists and displays logs from previous Lenovo update runs |
| `6` | **View Local Admins** *(IN BETA)* | Lists users with local administrator rights on domain machines |
| `7` | **Nils & Kobby Net-User script** | Look up AD user details and group memberships by username or display name |
| `8` | **Get PC Info** | Displays local PC hardware and OS details (name, model, serial, MAC, OS) |
| `9` | **Get User License** | Looks up a user's M365 license and recommends MEC or LTSC Office install |

> After each task completes you are returned to the menu automatically.

---

## Notes

- Options marked **IN BETA** are still being tested and may not work in all environments.
- **Lenovo System Updates** requires the machine to be a Lenovo device. It will automatically relaunch as Administrator if not already elevated.
- **View Local Admins** scans machines in the SEMA3 OU. Offline machines are skipped automatically. Coverage depends on how many machines are online at the time of the scan.
 
## ✅ Requirements
 
- Windows PowerShell **5.1 or later**
- **Admin privileges recommended** — required for printer installation and power settings
 
&nbsp;
 
## Advanced & Optional
 
> These sections cover specific edge cases. Most users only need the Quick Start above.
 
<details>
<summary><strong>▶ Running from CMD instead of PowerShell</strong></summary>
&nbsp;
 
```cmd
powershell -Command "iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1')"
```
 
</details>
<details>
<summary><strong>▶ Execution policy is restricted (script is blocked)</strong></summary>
&nbsp;
 
If you see an error about execution policy, bypass it for the session with:
 
```cmd
powershell -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1')"
```
 
> **Note:** This bypasses the policy for that single session only — your system policy is not permanently changed.
 
</details>
<details>
<summary><strong>▶ Run a specific script directly (skip the menu)</strong></summary>
&nbsp;
 
Each component can be run standalone if you only need one specific fix:
 
```powershell
# Fix Teams add-in for Outlook Classic only
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/outlook-classic/ms_outlook16classic_teams_addin.ps1")
```
 
```powershell
# ThinkShield script
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/ThinkShield/script1.ps1")
```
 
</details>
<details>
<summary><strong>▶ Repository structure</strong></summary>
&nbsp;
 
```
arjo-tools/
├── main.ps1                                   # Interactive menu entrypoint
├── pipelines/
│   └── install26/                             # arjo-ignition pipeline (NL2026 deployment)
│       ├── install26.ps1                      # Pipeline entrypoint — runs all stages in order
│       └── components/
│           ├── power.ps1                      # Power settings stage
│           ├── teams.ps1                      # Microsoft Teams install stage
│           ├── metrics.ps1                    # PC info collection + reporting stage
│           └── drivers.ps1                    # Lenovo driver/firmware update stage (auto-resume)
└── components/
   ├── printers.ps1                            # Printer installation (exposes Add-Printers)
   ├── power.ps1                               # Power configuration (exposes Set-PowerSettings)
   ├── get-pc-info.ps1                         # PC hardware/OS info (exposes Get-PCInfo)
   ├── lenovo-updates.ps1                      # Lenovo driver/firmware updates (exposes Start-LenovoUpdates)
   ├── view-logs.ps1                           # Lenovo update log viewer (exposes Show-LenovoLogs)
   ├── list-local-admin-for-site.ps1           # Local admin listing (exposes Show-GroupMenu)
   ├── nk-net-user-lookup.ps1                  # AD user lookup (exposes Start-UserLookup)
   └── mslic.ps1                               # M365 license lookup + Office recommendation (exposes Get-UserLicense) 
```
 
Scripts under `components/` expose named functions and are loaded by `main.ps1` on demand.
Scripts in subdirectories run inline and can also be invoked directly without the menu.
 
</details>
<details>
<summary><strong>▶ What registry keys does the Teams fix touch?</strong></summary>
&nbsp;
 
All changes are written to **current user only** (`HKCU`) — no system-wide modifications.
 
| Registry Key | Purpose |
|--------------|---------|
| `HKCU:\...\Outlook\Addins\TeamsAddin.FastConnect` | Sets `LoadBehavior = 3` — marks the add-in as active on startup |
| `HKCU:\...\Outlook\Resiliency\DisabledItems` | Clears add-ins that Outlook has force-disabled after a crash |
| `HKCU:\...\Outlook\Resiliency\DoNotDisableAddinList` | Exempts Teams from being auto-disabled again in the future |
 
All operations are **idempotent** — safe to run multiple times with no side effects.
 
</details>
