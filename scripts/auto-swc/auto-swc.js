import { chromium } from "playwright";
import { readFileSync } from "fs";
import "dotenv/config";

import {
  navigateTo,
  clickRole,
  withRetry,
  computerADdescription,
} from "./functions/sharedFunctions.js";
import {
  openManageSoftware,
  searchPC,
  addSoftware,
  installSoftware,
} from "./functions/manageSoftware.js";
import {
  openEditComputer,
  searchPCEditComputer,
  selectTemplate,
  applyChanges,
} from "./functions/editComputers.js";
import {
  openSoftwareStatus,
  searchAndSelectPCGrid,
  exportGridToJson,
} from "./functions/softwareStatus.js";
import {
  openEditADComputer,
  searchPCEditADComputer,
  setDescription,
  saveADComputer,
} from "./functions/editADComputer.js";

import { resolvePcType } from "./maps/pcTypeMap.js";
import { resolveSoftware } from "./maps/softwareMap.js";

// -------------------------------------------------------
// Config
// -------------------------------------------------------

const DRY_RUN = process.argv.includes("--dry-run");
const ini = JSON.parse(readFileSync("./ini.json", "utf-8"));

if (DRY_RUN) {
  console.log("[CONFIG] Dry run enabled — destructive actions will be skipped");
}
console.log(
  `[CONFIG] Loaded ${ini.length} entr${ini.length === 1 ? "y" : "ies"} from ini.json`,
);

// -------------------------------------------------------
// Per-PC pipeline
// -------------------------------------------------------

async function run(page, entry) {
  const {
    pc,
    "pc-type": pc_type,
    firstName,
    lastName,
    software: softwareFlags,
  } = entry;
  const fullName = `${firstName} ${lastName}`;
  const softwareList = resolveSoftware(softwareFlags);
  const pcType = resolvePcType(pc_type);
  const adDescription = computerADdescription(pcType, fullName);

  console.log(`\n${"=".repeat(60)}`);
  console.log(`[RUN] PC: ${pc} | User: ${fullName}`);
  console.log(`[RUN] Software: ${softwareFlags.join(", ")}`);
  console.log(`[RUN] AD description: ${adDescription}`);
  console.log(`${"=".repeat(60)}`);

  await withRetry("navigateTo", () => navigateTo(page, process.env.SWC_URL));
  await withRetry("clickRole", () => clickRole(page, "NLTIE"));

  // EDIT COMPUTER
  // await withRetry("openEditComputer",      () => openEditComputer(page));
  // await withRetry("searchPCEditComputer",  () => searchPCEditComputer(page, pc));
  // await withRetry("selectTemplate",        () => selectTemplate(page, "NLTIE (NL)"));
  // await withRetry("applyChanges",          () => applyChanges(page, { dryRun: DRY_RUN }));

  // EDIT AD COMPUTER
  await withRetry("openEditADComputer", () => openEditADComputer(page));
  await withRetry("searchPCEditADComputer", () =>
    searchPCEditADComputer(page, pc),
  );
  await withRetry("setDescription", () => setDescription(page, adDescription));
  await withRetry("saveADComputer", () =>
    saveADComputer(page, { dryRun: DRY_RUN }),
  );

  // MANAGE SOFTWARE
  // await withRetry("openManageSoftware", () => openManageSoftware(page));
  // await withRetry("searchPC",           () => searchPC(page, pc));
  // await withRetry("addSoftware",        () => addSoftware(page, softwareList));
  // await withRetry("installSoftware",    () => installSoftware(page, { dryRun: DRY_RUN }));

  // SOFTWARE STATUS
  // await withRetry("openSoftwareStatus",      () => openSoftwareStatus(page));
  // await withRetry("searchAndSelectPCGrid",   () => searchAndSelectPCGrid(page, pc));
  // const data = await withRetry("exportGridToJson", () => exportGridToJson(page));
  // console.log(`[RUN] Status data for ${pc}:`, data);
}

// -------------------------------------------------------
// Entry point
// -------------------------------------------------------

const browser = await chromium.launch({
  headless: false,
  ignoreHTTPSErrors: true,
});

const context = await browser.newContext({
  httpCredentials: {
    username: process.env.SWC_USERNAME,
    password: process.env.SWC_PASSWORD,
  },
  ignoreHTTPSErrors: true,
});

const page = await context.newPage();

const failed = [];

try {
  for (const entry of ini) {
    try {
      await run(page, entry);
    } catch (err) {
      console.error(`[SKIP] ${entry.pc} failed: ${err.message}`);
      failed.push({ pc: entry.pc, error: err.message });
    }
  }
} finally {
  await browser.close();
}

console.log("\n[DONE] All entries processed");

if (failed.length > 0) {
  console.log(`\n[SUMMARY] ${failed.length} PC(s) failed:`);
  for (const { pc, error } of failed) {
    console.log(`  - ${pc}: ${error}`);
  }
} else {
  console.log("[SUMMARY] All PCs completed successfully");
}
