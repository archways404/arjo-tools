# CDM L-Drive Mapper — Deployment Guide

This component deploys the L: drive mapping solution (used to work around the
Cloud Drive Mapper V2 → V3 deprecation) onto a machine. It creates `C:\Scripts`,
writes `Map_L_Drive.ps1` and `CDM-L-DriveMapper.xml` into it, and leaves the
scheduled task import as a manual step (see below).

---

## What it does

1. Creates the folder `C:\Scripts` if it doesn't already exist.
2. Downloads the **contents** of two files from GitHub (not the files
   themselves) and writes them to disk locally using `Set-Content`:
   - `C:\Scripts\Map_L_Drive.ps1`
   - `C:\Scripts\CDM-L-DriveMapper.xml`
3. Logs every step.

### Why it fetches content instead of downloading the file directly

Files downloaded directly with `Invoke-WebRequest -OutFile`, a browser, or
BITS get tagged with a **Mark-of-the-Web (MOTW)** — a hidden
`Zone.Identifier` alternate data stream that marks the file as coming from
the internet. Security tooling on Arjo endpoints flags and blocks scripts
carrying this tag.

By fetching the raw **content** as text and writing it to disk ourselves
with `Set-Content`, the resulting file is treated as locally created and
does not carry the MOTW flag, so it's allowed to run.

---

## Source files (GitHub)

| File | Source |
|---|---|
| `Map_L_Drive.ps1` | `https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/Map_L_Drive.ps1` |
| `CDM-L-DriveMapper.xml` | `https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/CDM-L-DriveMapper.xml` |

---

## Normal usage (automated)

1. Run the `arjo-tools` main menu script.
2. Select **"Deploy CDM L-Drive Mapper (L Drive)"**.
3. Confirm the log output shows:
   - `Creating folder: C:\Scripts`
   - `Writing C:\Scripts\Map_L_Drive.ps1`
   - `Writing C:\Scripts\CDM-L-DriveMapper.xml`
   - `CDM L-Drive Mapper files deployed to C:\Scripts.`
4. Manually import the scheduled task (see [Registering the scheduled
   task](#registering-the-scheduled-task) below) — this step is intentionally
   not automated.

---

## Registering the scheduled task

The deployment script only **writes the files** — it does not register the
scheduled task automatically. Do this manually:

1. Open **Task Scheduler** (`taskschd.msc`).
2. In the right-hand pane, click **Import Task…**
3. Browse to `C:\Scripts\CDM-L-DriveMapper.xml` and select it.
4. Review the task's General/Triggers/Actions tabs in the import dialog —
   confirm the **Action** points to:
   ```
   powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Map_L_Drive.ps1"
   ```
5. Click **OK** to finish the import.
6. Right-click the new task → **Run** to test it immediately, then check
   `C:\Scripts\Logs\Map_L_Drive.log` to confirm it mapped successfully.

If Task Scheduler refuses to import the XML (rare, but can happen on locked-
down machines), register it from an elevated PowerShell/cmd prompt instead:

```powershell
schtasks /Create /TN "CDM-L-DriveMapper" /XML "C:\Scripts\CDM-L-DriveMapper.xml" /F
```

---

## Manual fallback — if the automated deployment script fails or won't run

If the menu option fails, is blocked, or you just need to do it by hand on a
single machine:

### Step 1: Create the folder

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
```

### Step 2: Create `Map_L_Drive.ps1`

Open Notepad (or PowerShell ISE / VS Code) **on the target machine itself**
— don't copy a file over from a network share or USB drive, since that will
also carry MOTW. Paste in the script content, then save as:

```
C:\Scripts\Map_L_Drive.ps1
```

Make sure "Save as type" is set to **All Files**, not `.txt`, so it doesn't
end up as `Map_L_Drive.ps1.txt`.

### Step 3: Create `CDM-L-DriveMapper.xml`

Same approach — open the raw XML content from GitHub in a browser, copy the
full text, paste into Notepad on the target machine, and save as:

```
C:\Scripts\CDM-L-DriveMapper.xml
```

### Step 4: Verify no MOTW flag was set

From PowerShell:

```powershell
Get-Item -Path "C:\Scripts\Map_L_Drive.ps1" -Stream Zone.Identifier -ErrorAction SilentlyContinue
```

- **No output** → good, no MOTW tag, file will run.
- **Output showing a `Zone.Identifier` stream** → the file was flagged
  (likely because it was downloaded/copied rather than typed/pasted and
  saved locally). Unblock it with:
  ```powershell
  Unblock-File -Path "C:\Scripts\Map_L_Drive.ps1"
  Unblock-File -Path "C:\Scripts\CDM-L-DriveMapper.xml"
  ```

### Step 5: Register the scheduled task

Follow [Registering the scheduled task](#registering-the-scheduled-task)
above.

### Step 6: Test it

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Map_L_Drive.ps1"
```

Then check the log:

```powershell
Get-Content "C:\Scripts\Logs\Map_L_Drive.log" -Tail 20
```

You should see a line ending in:

```
Successfully mapped L: to 'R:\NLTIE - Customer Sales - Documenten'
=== Script finished successfully ===
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Menu option runs but nothing appears in `C:\Scripts` | `Invoke-WebRequest` failed silently (network/proxy) | Re-run; check `[ERROR] Failed to fetch...` in console output. Confirm the machine can reach `raw.githubusercontent.com`. |
| Script runs but is blocked / "cannot be loaded because running scripts is disabled" | Execution policy | Run the task/script with `-ExecutionPolicy Bypass` (already set in the task action above). |
| Script runs but flagged by AV/EDR anyway | File still carries MOTW, or was copied from another machine/share after creation | Re-create using Step 2–3 above (type/paste + save locally, don't copy the file itself). Check with the `Zone.Identifier` command in Step 4. |
| `Map_L_Drive.log` shows repeated `WARN Waiting for 'R:\...' to become available` then fails after 30 attempts | R: drive (Cloud Drive Mapper) not mounted yet or CDM V3 migration incomplete on that user profile | Confirm CDM V3 is installed and the user has signed in at least once so R: exists before the task runs. |
| `subst` fails with "Invalid parameter" or L: already in use | L: already mapped to something else (real network drive, another subst, etc.) | Manually run `subst L: /d` to clear it, then re-run the script. |
| Task Scheduler import dialog is greyed out / import fails | XML file is corrupted or wasn't saved as UTF-8 without the wrong line endings | Re-fetch the raw XML content from GitHub directly in a browser and re-paste/save it. |

---

## File reference

| Path | Purpose |
|---|---|
| `C:\Scripts\Map_L_Drive.ps1` | The mapping script — waits for `R:\NLTIE - Customer Sales - Documenten`, then `subst`s it to `L:`. |
| `C:\Scripts\CDM-L-DriveMapper.xml` | Scheduled Task definition to import into Task Scheduler; runs `Map_L_Drive.ps1`. |
| `C:\Scripts\Logs\Map_L_Drive.log` | Execution log — check here first for any issue. Auto-rotates once it exceeds ~5MB. |