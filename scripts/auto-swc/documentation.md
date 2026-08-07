# auto-swc

A Playwright-based automation wrapper for the **SWC** (Software Central)
portal. Given a list of PCs in `ini.json`, it drives the SWC web UI to:

1. Set the computer's **template** (Edit Computer)
2. *(optional, currently disabled)* Set the **AD computer description**
3. Add and install **software** (Manage Software)
4. *(optional, currently disabled)* Export the **software install status**
   for each PC as JSON

It runs as a real, visible Chromium browser (not headless) since SWC is a
Telerik/RadControls-heavy ASP.NET site that's flaky to drive headlessly.

---

## Requirements

- Node.js 18+ (uses native `fs`/ESM, no build step)
- Network access to your SWC instance
- An SWC service account with permission to edit computers / manage
  software for the relevant role(s)

---

## Installation

```bash
git clone <repo-url>
cd auto-swc
npm install
npx playwright install chromium
```

`npx playwright install chromium` downloads the actual browser binary
Playwright drives — required once after `npm install`.

---

## Configuration

### 1. Environment variables

Copy the example file and fill in your credentials:

```bash
cp .env.example .env
```

```dotenv
SWC_USERNAME=ARJO\username
SWC_PASSWORD=password
SWC_URL=https://arjoswc.arjo.local
SWC_BASE_URL=https://arjoswc.arjo.local
```

| Variable | Purpose |
|---|---|
| `SWC_USERNAME` | HTTP Basic Auth username (domain-qualified, e.g. `ARJO\username`) sent by Playwright's browser context |
| `SWC_PASSWORD` | HTTP Basic Auth password |
| `SWC_URL` | Landing page the script navigates to first |
| `SWC_BASE_URL` | Base URL used to build all subsequent page routes (`/EditComputer`, `/ManageSoftwareSingle`, etc.) |

`.env` is loaded automatically via `dotenv/config` at the top of
`auto-swc.js`. **Never commit `.env`** — only `.env.example` should be in
version control.

### 2. `ini.json` — the batch job list

This is the list of PCs to process. It sits at the project root, next to
`auto-swc.js`.

```json
[
  {
    "pc": "PC025710",
    "pc-type": "T14",
    "firstName": "",
    "lastName": "",
    "software": ["LogMeIn"]
  }
]
```

| Field | Type | Description |
|---|---|---|
| `pc` | string | Exact computer name as it appears in SWC (e.g. `PC025710`) |
| `pc-type` | string | Key into `maps/pcTypeMap.js` (e.g. `T14`, `L16`) — resolved to a human-readable model name, currently only used to build the AD description |
| `firstName` / `lastName` | string | User's name — only used to build the AD description (`computerADdescription`). Can be left blank if the AD-description step stays disabled |
| `software` | string[] | List of keys into `maps/softwareMap.js` (e.g. `LogMeIn`, `Office365`) — resolved to the exact SWC package name before searching |

Each entry in the array is processed as one independent job, in order.

---

## Running it

Two npm scripts are provided:

```bash
npm run dev    # node auto-swc.js --dry-run
npm run prod   # node auto-swc.js
```

### Dry run (`--dry-run`)

Use this first, always, especially after editing `ini.json` or before a
large batch. It runs the **entire navigation and search flow for real** —
opening SWC, searching for each PC, selecting the template, searching for
and checking off each software package — but skips every step that would
actually commit a change:

- **Apply Changes** (template) is skipped
- **Save** (AD computer) is skipped
- **Add or Remove Software** (install trigger) is skipped

This lets you visually confirm in the browser that every PC and every
software name resolves and gets found correctly, with zero risk of
pushing a real install or template change.

### Production run

```bash
npm run prod
```

Runs the same flow with all commit/apply/save/install actions enabled for
real. A Chromium window opens and you'll see it click through each PC in
`ini.json` sequentially.

---

## What each PC goes through (current pipeline)

Defined in `run()` in `auto-swc.js`. For each entry in `ini.json`, in order:

1. **Navigate & select role**
   `navigateTo(SWC_URL)` → `clickRole(page, "NLTIE")`
   *(role is currently hardcoded to `"NLTIE"` — see [Available
   roles](#available-roles) to change it)*

2. **Edit Computer**
   Open Edit Computer → search for the PC → select template
   `"NLTIE (NL)"` → Apply Changes

3. **Edit AD Computer** — *currently commented out in `auto-swc.js`*
   Would open Edit AD Computer → search for the PC → set description to
   `"{firstName} {lastName} {resolved pc-type}"` → Save

4. **Manage Software**
   Open Manage Software → search for the PC → add each software item
   resolved from `entry.software` → click install (Add or Remove Software)

5. **Software Status** — *currently commented out in `auto-swc.js`*
   Would open Software Status → search/select the PC in the grid → export
   the install status grid to JSON and log it

Steps 3 and 5 are left in the code (commented) because they work but
aren't part of the normal batch flow right now. See
[Re-enabling a disabled step](#re-enabling-a-disabled-step) below.

Each step is wrapped in `withRetry(label, fn)`, which retries up to 3 times
with a 2s delay on failure before giving up and throwing. If a PC's entire
`run()` throws, that PC is logged as failed and the script **moves on to
the next PC** rather than aborting the whole batch — see
[Output & failure handling](#output--failure-handling).

---

## Project structure

```
auto-swc/
├── auto-swc.js                  # entry point / pipeline orchestration
├── ini.json                     # batch job list (you edit this per run)
├── .env                         # credentials (not committed)
├── .env.example                 # template for .env
├── package.json
├── functions/
│   ├── sharedFunctions.js       # navigateTo, clickRole, withRetry, computerADdescription
│   ├── editComputers.js         # Edit Computer page actions (template)
│   ├── editADComputer.js        # Edit AD Computer page actions (description)
│   ├── manageSoftware.js        # Manage Software page actions (install)
│   └── softwareStatus.js        # Software Status page actions (export/read grid)
└── maps/
    ├── pcTypeMap.js              # "T14" -> "ThinkPad T14 Gen 6", etc.
    └── softwareMap.js            # "LogMeIn" -> exact SWC package string, etc.
```

---

## Extending it

### Adding a new PC model

Edit `maps/pcTypeMap.js`:

```javascript
const PC_TYPE_MAP = {
  T14: "ThinkPad T14 Gen 6",
  L16: "ThinkPad L16 Gen 2",
  X1:  "ThinkPad X1 Carbon Gen 12",   // new entry
};
```

Then reference `"pc-type": "X1"` in `ini.json`. `resolvePcType()` throws if
the key isn't found, so a typo in `ini.json` fails fast at runtime instead
of silently producing a wrong description.

### Adding a new software package

Edit `maps/softwareMap.js` with the **exact** package name string as it
appears in SWC's Manage Software search (copy it directly from the SWC
UI to avoid typos):

```javascript
const SOFTWARE_MAP = {
  LogMeIn: "LogmeinLogmeinclient_4.1.16006_EN_01",
  // ...
  Zoom: "ZoomZoomClient_6.1.0_EN_01_(x64)",   // new entry
};
```

Then reference `"software": ["Zoom"]` in `ini.json`. Unlike
`resolvePcType`, `resolveSoftware()` does **not** throw on an unknown key —
it logs a `[WARN] Unknown software flag "X", skipping` and filters it out,
so one bad entry in `ini.json` won't kill the whole batch.

### Re-enabling a disabled step

In `auto-swc.js`, uncomment the relevant block inside `run()`. For example,
to re-enable AD description updates:

```javascript
// EDIT AD COMPUTER
await withRetry("openEditADComputer", () => openEditADComputer(page));
await withRetry("searchPCEditADComputer", () =>
  searchPCEditADComputer(page, pc),
);
await withRetry("setDescription", () => setDescription(page, adDescription));
await withRetry("saveADComputer", () =>
  saveADComputer(page, { dryRun: DRY_RUN }),
);
```

Make sure `firstName`/`lastName` are populated in `ini.json` for any PC
that will hit this step, since `adDescription` is built from them.

### Available roles

`clickRole(page, roleName)` clicks the role tile matching `roleName` on the
SWC landing page. Currently hardcoded to `"NLTIE"` in `auto-swc.js`. Valid
values (from the comment block in `sharedFunctions.js`):

| Role | ID |
|---|---|
| A1 | 119 |
| DKLY2 | 34 |
| NLTIE | 15 |
| NOOS2 | 30 |
| Partners-Devoteam | 169 |
| SEMA3 | 33 |
| SESTO | 35 |

To target a different site, change the `clickRole(page, "NLTIE")` call in
`auto-swc.js`, and update the template name in `selectTemplate(page,
"NLTIE (NL)")` to match a template that exists under that role.

---

## Output & failure handling

The script processes `ini.json` entries **sequentially in one browser
session** (not in parallel — SWC's UI state is single-threaded per page).

- Per-PC progress is printed as it runs (`[RUN]`, `[ACTION]`, `[RETRY]`,
  `[SKIP]`, `[DRY RUN]` lines).
- If a PC's pipeline throws after retries are exhausted, that PC is added
  to a `failed` list and the loop **continues to the next PC** — one bad
  PC doesn't stop the batch.
- At the end, a summary is printed:

```
[DONE] All entries processed

[SUMMARY] 1 PC(s) failed:
  - PC025692: openManageSoftware gave up after 3 attempts: Timeout 15000ms exceeded.
```

or, if everything succeeded:

```
[SUMMARY] All PCs completed successfully
```

There's no automatic log file — capture output yourself if you need a
persistent record, e.g.:

```bash
npm run prod | tee run-$(date +%Y%m%d-%H%M%S).log
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Error: Unknown PC type: "X"` | `pc-type` in `ini.json` isn't in `maps/pcTypeMap.js` | Add the mapping, or fix the typo in `ini.json` |
| `[WARN] Unknown software flag "X", skipping` | `software` entry in `ini.json` isn't in `maps/softwareMap.js` | Add the mapping — the run continues, but that software is silently skipped for that PC |
| `PC {name} not found in grid` / search throws `Unexpected match` | PC name doesn't exist in SWC under the selected role, or was typed with wrong casing/spacing | Verify the PC name in the SWC UI manually under the same role (`NLTIE`) |
| `[SKIP] No results for "X" — already installed or not found, skipping` | Software already assigned to that PC, or the resolved package string doesn't match anything in SWC's search | Check SWC directly — if it's a genuine mismatch, correct the string in `softwareMap.js` |
| Script hangs waiting on a selector, eventually times out and retries | SWC page loaded slower than expected, or a Telerik popup/modal appeared unexpectedly | Usually resolves itself via `withRetry`; if it fails 3x consistently, watch the (non-headless) browser during a `dev` run to see what's actually on screen |
| Login fails immediately (`401`) | Wrong `SWC_USERNAME`/`SWC_PASSWORD`, or missing domain prefix | Confirm `.env` has the domain-qualified username (`ARJO\username`) and the account isn't locked |
| `npx playwright install chromium` needed again after an update | `playwright` version bumped in `package.json` (browser binaries are version-locked) | Re-run `npx playwright install chromium` after any `npm install` that changes the `playwright` version |
| Everything works in `dev` (dry-run) but fails for real in `prod` | A commit/apply step (Apply Changes, Save, Install) is slower than the fixed `waitForTimeout` after it | Increase the relevant `waitForTimeout` in `editComputers.js` / `manageSoftware.js` if SWC is consistently slower than expected in your environment |

---

## Safety notes

- **Always run `npm run dev` first** on any new or edited `ini.json` before
  running `npm run prod`. Dry-run exercises the full search/selection path
  with zero write actions.
- The browser runs **non-headless and visible** on purpose — watch it
  during unfamiliar batches so you can `Ctrl+C` if something looks wrong
  before a commit step fires.
- Credentials in `.env` are HTTP Basic Auth creds for a real SWC account —
  treat the file like any other secret (not committed, not shared in
  tickets/chat).
