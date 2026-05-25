<div align="center">

# Arjo Tools

**Modular PowerShell setup utility for configuring ARJO machines.**
 
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows&logoColor=white)
![Admin](https://img.shields.io/badge/Admin-Recommended-orange)

![GitHub Release](https://img.shields.io/github/v/release/archways404/arjo-tools?sort=semver&display_name=release&style=flat&logo=iterm2&label=&color=3DDB00)

 
</div>

---
 
## Quick Start
 
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
| `3` | **Fix Teams Add-in** *(Outlook Classic)* | Re-enables the Teams Meeting add-in when inactive or crash-disabled |
| `4` | **Lenovo System Updates** *(IN BETA)* | Scans and installs Lenovo driver and firmware updates — relaunches elevated if needed |
| `5` | **View Lenovo Update Logs** *(IN BETA)* | Lists and displays logs from previous Lenovo update runs |
| `6` | **View Local Admins** *(IN BETA)* | Lists users with local administrator rights on domain machines |
| `7` | **Nils & Kobby Net-User script** | Look up AD user details and group memberships by username or display name |

> After each task completes you are returned to the menu automatically.

---

## Notes

- Options marked **IN BETA** are still being tested and may not work in all environments.
- **Lenovo System Updates** requires the machine to be a Lenovo device. It will automatically relaunch as Administrator if not already elevated.
- **View Local Admins** scans machines in the SEMA3 OU. Offline machines are skipped automatically. Coverage depends on how many machines are online at the time of the scan.
 
## ✅ Requirements
 
- Windows PowerShell **5.1 or later**
- **Admin privileges recommended** — required for printer installation and power settings
---
 
&nbsp;
 
---
 
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
├── main.ps1                                    # Interactive menu entrypoint
├── components/
│   ├── printers.ps1                            # Printer installation (exposes Add-Printers)
│   └── power.ps1                               # Power configuration (exposes Set-PowerSettings)
├── outlook-classic/
│   └── ms_outlook16classic_teams_addin.ps1     # Teams add-in fix for Outlook 16 Classic
└── ThinkShield/
    └── script1.ps1                             # ThinkShield configuration
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
