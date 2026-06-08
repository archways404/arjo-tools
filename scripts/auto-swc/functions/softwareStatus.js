// -------------------------------------------------------
// Software Status actions
// -------------------------------------------------------

export async function openSoftwareStatus(page) {
  console.log("[ACTION] Navigating to Software Status");
  await page.goto(`${process.env.SWC_BASE_URL}/SoftwareStatus`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Software Status page loaded");
}

export async function searchAndSelectPCGrid(page, pcName) {
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

export async function readGridPage(page) {
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

export async function getTotalPages(page) {
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

export async function readAllPages(page) {
  const allData = [];
  let currentPage = 1;
  const totalPages = await getTotalPages(page);
  console.log(`[READ] Total pages: ${totalPages}`);

  const NEXT_PAGE_BTN =
    "input[name='ctl00$ContentPlaceHolderMain$RadGridContent$ctl00$ctl03$ctl01$ctl10']";

  while (currentPage <= totalPages) {
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

export function parseGridData(rawData) {
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

export async function exportGridToJson(page) {
  console.log("[EXPORT] Starting grid export...");
  const raw = await readAllPages(page);
  const parsed = parseGridData(raw);
  const json = JSON.stringify(parsed, null, 2);
  console.log("[EXPORT] Done. Sample:");
  console.log(json.slice(0, 500));
  return parsed;
}
