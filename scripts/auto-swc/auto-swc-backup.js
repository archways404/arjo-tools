import { chromium } from "playwright";
import "dotenv/config";

// -------------------------------------------------------
// Actions
// -------------------------------------------------------

async function navigateTo(page, url) {
  console.log(`[NAV] Going to ${url}`);
  await page.goto(url);
  await page.waitForLoadState("networkidle");
}

async function clickRole(page, roleName) {
  console.log(`[ACTION] Clicking role: ${roleName}`);
  const selector = `input.rbDecorated[value="${roleName}"]`;
  await page.waitForSelector(selector);
  await page.click(selector);

  // Wait for the top menu to appear — confirms we're past the role screen
  await page.waitForSelector("#ctl00_RadMenuTop_i7_RadButtonImage18", {
    timeout: 15000,
  });
  console.log(`[ACTION] Role ${roleName} selected, main page loaded`);
}

// -------------------------------------------------------
// Available roles (for reference)
// -------------------------------------------------------
// "A1"               id: 119
// "DKLY2"            id: 34
// "NLTIE"            id: 15
// "NOOS2"            id: 30
// "Partners-Devoteam" id: 169
// "SEMA3"            id: 33
// "SESTO"            id: 35

async function openManageSoftware(page) {
  console.log("[ACTION] Navigating to Manage Software");
  await page.goto(`${process.env.SWC_BASE_URL}/ManageSoftwareSingle`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Manage Software page loaded");
}

async function searchPC(page, pcName) {
  console.log(`[ACTION] Searching for PC: ${pcName}`);

  await page.waitForTimeout(2000);

  await page.focus("#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input");
  await page.click("#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input");

  await page.type(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input",
    pcName,
    { delay: 100 },
  );

  const item = await page.waitForSelector("li.rcbHovered", { timeout: 15000 });
  const text = await item.textContent();
  if (!text.includes(pcName)) throw new Error(`Unexpected match: ${text}`);
  await item.click();

  // Wait for the next section to render (software search box appearing confirms it)
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input",
    { timeout: 15000 },
  );

  console.log(`[ACTION] Selected PC: ${pcName}`);
}

async function searchAndSelectSoftware(page, softwareName) {
  console.log(`[ACTION] Searching for software: ${softwareName}`);

  await page.waitForTimeout(2000);

  // Focus and type into the software search box
  await page.focus(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input",
  );
  await page.click(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input",
  );

  await page.type(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input",
    softwareName,
    { delay: 100 },
  );

  // Wait for dropdown results to appear
  await page.waitForSelector(".divTableCell label", { timeout: 15000 });

  // Find the checkbox whose label matches the software name
  const label = await page
    .locator("label")
    .filter({ hasText: softwareName })
    .first();
  const labelText = await label.textContent();

  if (!labelText.includes(softwareName)) {
    throw new Error(`Unexpected match: ${labelText}`);
  }

  console.log(`[ACTION] Found match: ${labelText.trim()}`);

  // Click the checkbox inside the matching label
  await label.locator("input[type='checkbox']").click();

  // Clear the search box after selecting
  await page.click(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input",
  );
  await page.keyboard.press("Control+a");
  await page.keyboard.press("Delete");

  console.log(`[ACTION] Selected software: ${labelText.trim()}`);
}

async function addSoftware(page, software) {
  const list = Array.isArray(software) ? software : [software];
  for (const name of list) {
    await searchAndSelectSoftware(page, name);
  }
}

async function installSoftware(page) {
  console.log("[ACTION] Clicking Add or Remove Software");
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadButtonCommit_input",
  );
  await page.click("#ctl00_ContentPlaceHolderMain_RadButtonCommit_input");
  await page.waitForLoadState("networkidle");
  console.log("[ACTION] Install triggered");
}

async function openEditComputer(page) {
  console.log("[ACTION] Navigating to Edit Computer");
  await page.goto(`${process.env.SWC_BASE_URL}/EditComputer`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Edit Computer page loaded");
}

async function searchPCEditComputer(page, pcName) {
  console.log(`[ACTION] Searching for PC on Edit Computer: ${pcName}`);

  await page.waitForTimeout(2000);

  await page.focus("#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input");
  await page.click("#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input");

  await page.type(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxComputer_Input",
    pcName,
    { delay: 100 },
  );

  const item = await page.waitForSelector("li.rcbHovered", { timeout: 15000 });
  const text = await item.textContent();
  if (!text.includes(pcName)) throw new Error(`Unexpected match: ${text}`);
  await item.click();

  // Wait for template dropdown to appear — confirms PC was selected and page updated
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxTemplate_Input",
    { timeout: 15000 },
  );

  console.log(`[ACTION] Selected PC: ${pcName}`);
}

async function selectTemplate(page, templateName) {
  console.log(`[ACTION] Selecting template: ${templateName}`);

  // Click the input to open the dropdown
  await page.click("#ctl00_ContentPlaceHolderMain_RadComboBoxTemplate_Input");

  // Wait for the list and click the item matching the name
  await page.waitForSelector("ul.rcbList", { timeout: 15000 });
  await page.locator("ul.rcbList li").filter({ hasText: templateName }).click();

  console.log(`[ACTION] Selected template: ${templateName}`);
}

async function applyChanges(page) {
  console.log("[ACTION] Applying changes");
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadButtonApply_input",
  );
  await page.click("#ctl00_ContentPlaceHolderMain_RadButtonApply_input");
  await page.waitForLoadState("networkidle");
  console.log("[ACTION] Changes applied");
}

async function openSoftwareStatus(page) {
  console.log("[ACTION] Navigating to Software Status");
  await page.goto(`${process.env.SWC_BASE_URL}/SoftwareStatus`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Software Status page loaded");
}

async function searchAndSelectPCGrid(page, pcName) {
  console.log(`[ACTION] Searching for PC in grid: ${pcName}`);

  await page.click(
    "#ctl00_ContentPlaceHolderMain_RadAutoCompleteBoxSearch_Input",
  );
  await page.type(
    "#ctl00_ContentPlaceHolderMain_RadAutoCompleteBoxSearch_Input",
    pcName,
    { delay: 100 },
  );

  await page.keyboard.press("Tab");
  await page.waitForTimeout(3000);

  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadGridComputers_ctl00 tbody tr",
    { timeout: 15000 },
  );

  const rows = page.locator(
    "#ctl00_ContentPlaceHolderMain_RadGridComputers_ctl00 tbody tr",
  );
  const count = await rows.count();

  let clicked = false;
  for (let i = 0; i < count; i++) {
    const row = rows.nth(i);
    const text = await row.textContent();
    if (text.includes(pcName)) {
      await row.locator("span.rbToggleCheckbox").click();
      console.log(`[ACTION] Clicked checkbox for: ${pcName}`);
      clicked = true;
      break;
    }
  }

  if (!clicked) throw new Error(`PC ${pcName} not found in grid`);

  // Give the Ajax call time to complete
  await page.waitForTimeout(5000);

  // Debug — check pagination text right after click
  const infoEl = page.locator(
    "#ctl00_ContentPlaceHolderMain_RadGridContent .rgInfoPart",
  );
  const infoText = await infoEl.textContent();
  console.log(`[DEBUG] Content grid info after click: "${infoText.trim()}"`);

  console.log(`[ACTION] Selected PC in grid: ${pcName}`);
}

async function readGridPage(page) {
  // Wait for the content grid to have rows first
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadGridContent_ctl00 tbody tr",
    { timeout: 15000 },
  );

  const rows = page.locator(
    "#ctl00_ContentPlaceHolderMain_RadGridContent_ctl00 tbody tr",
  );
  const count = await rows.count();
  const data = [];

  for (let i = 0; i < count; i++) {
    const row = rows.nth(i);
    const cells = row.locator("td");
    const cellCount = await cells.count();
    if (cellCount < 7) continue;

    const computer = (await cells.nth(2).textContent()).trim();
    const name = (await cells.nth(3).textContent()).trim();
    const type = (await cells.nth(4).textContent()).trim();
    const action = (await cells.nth(5).textContent()).trim();
    const status = (await cells.nth(6).textContent()).trim();

    if (!computer || !name) continue;
    data.push({ computer, name, type, action, status });
  }

  return data;
}

async function getTotalPages(page) {
  const infoEl = page.locator(
    "#ctl00_ContentPlaceHolderMain_RadGridContent .rgInfoPart",
  );
  const text = await infoEl.textContent();
  console.log(`[READ] Raw pagination text: "${text.trim()}"`);

  const match = text.match(/in\s+(\d+)\s+page/);
  if (!match) {
    console.log("[READ] Could not parse page count, defaulting to 1");
    return 1;
  }
  return parseInt(match[1], 10);
}

async function readAllPages(page) {
  const allData = [];
  let currentPage = 1;
  const totalPages = await getTotalPages(page);
  console.log(`[READ] Total pages: ${totalPages}`);

  while (currentPage <= totalPages) {
    const NEXT_PAGE_BTN =
      "input[name='ctl00$ContentPlaceHolderMain$RadGridContent$ctl00$ctl03$ctl01$ctl10']";
    console.log(`[READ] Reading page ${currentPage} of ${totalPages}...`);
    const pageData = await readGridPage(page);
    allData.push(...pageData);
    console.log(
      `[READ] Got ${pageData.length} rows, total so far: ${allData.length}`,
    );

    if (currentPage === totalPages) break;

    console.log("[READ] Going to next page...");
    await page.click(NEXT_PAGE_BTN);
    await page.waitForTimeout(2000);
    currentPage++;
  }

  return allData;
}

function parseGridData(rawData) {
  return rawData.map((row) => {
    const statusLower = row.status.toLowerCase();

    let installed = "unknown";
    if (row.action === "install") {
      if (statusLower.includes("success")) installed = "TRUE";
      else if (statusLower.includes("error") || statusLower.includes("failed"))
        installed = "FALSE";
      else if (statusLower.includes("progress")) installed = "in_progress";
      else if (statusLower.includes("not met"))
        installed = "requirements_not_met";
    } else if (row.action === "uninstall") {
      installed = statusLower.includes("success")
        ? "uninstalled"
        : "uninstall_failed";
    }

    return {
      computer: row.computer,
      name: row.name,
      type: row.type,
      action: row.action,
      installed,
      message: row.status,
    };
  });
}

async function exportGridToJson(page) {
  console.log("[EXPORT] Starting grid export...");
  const raw = await readAllPages(page);
  const parsed = parseGridData(raw);
  const json = JSON.stringify(parsed, null, 2);
  console.log("[EXPORT] Done. Sample:");
  console.log(json.slice(0, 500));
  return parsed;
}

// -------------------------------------------------------
// Pipeline
// -------------------------------------------------------

async function run(page) {
  await navigateTo(page, process.env.SWC_URL);

  // SELECT ROLE
  await clickRole(page, "NLTIE");

  // OPEN MANAGE SOFTWARE FLOW
  await openManageSoftware(page);
  await searchPC(page, "PC025293");
  // Add single software
  //await addSoftware(page, "AdobeAcrobatDC_21_SSP_EN_01_(x64)");

  // Add a list of software
  await addSoftware(page, [
    "AdobeAcrobatDC_21_SSP_EN_01_(x64)",
    "AdobeCreativeCloudDesktop_SSP_EN_02_(x64)",
  ]);
  // EXECUTE INSTALLATION (disabled for testing)
  //await installSoftware(page);

  // OPEN EDIT COMPUTER
  //await openEditComputer(page);
  //await searchPCEditComputer(page, "PC025293");
  //await selectTemplate(page, "NLTIE (NL)");
  // APPLY CHANGES (disabled for testing)
  //await applyChanges(page);

  // OPEN SOFTWARE STATUS
  await openSoftwareStatus(page);
  await searchAndSelectPCGrid(page, "PC025293");
  const data = await exportGridToJson(page);
  // print data to console (debug)
  console.log("DATA: ", data);
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

try {
  await run(page);
  console.log("[DONE] Pipeline completed");
} catch (err) {
  console.error("[ERROR]", err.message);
} finally {
  await browser.close();
}
