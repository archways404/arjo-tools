// -------------------------------------------------------
// Manage Software actions
// -------------------------------------------------------

export async function openManageSoftware(page) {
  console.log("[ACTION] Navigating to Manage Software");
  await page.goto(`${process.env.SWC_BASE_URL}/ManageSoftwareSingle`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Manage Software page loaded");
}

export async function searchPC(page, pcName) {
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

export async function searchAndSelectSoftware(page, softwareName) {
  console.log(`[ACTION] Searching for software: ${softwareName}`);
  const INPUT =
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAvailableSoftware_Input";

  // Clear any previous value first
  await page.click(INPUT);
  await page.keyboard.press("Control+a");
  await page.keyboard.press("Delete");
  await page.waitForTimeout(500);
  await page.type(INPUT, softwareName, { delay: 100 });

  // Wait for dropdown to appear
  try {
    await page.waitForSelector(".divTableCell label", { timeout: 3000 });
  } catch {
    console.warn(
      `[SKIP] No results for "${softwareName}" — already installed or not found, skipping`,
    );
    await page.click(INPUT);
    await page.keyboard.press("Control+a");
    await page.keyboard.press("Delete");
    return;
  }

  const label = page.locator("label").filter({ hasText: softwareName }).first();
  const count = await label.count();
  if (count === 0) {
    console.warn(
      `[SKIP] "${softwareName}" not found in results — already installed or unavailable, skipping`,
    );
    await page.click(INPUT);
    await page.keyboard.press("Control+a");
    await page.keyboard.press("Delete");
    return;
  }

  const labelText = await label.textContent();
  console.log(`[ACTION] Found match: ${labelText.trim()}`);
  await label.locator("input[type='checkbox']").click();

  // Clear after selecting
  await page.click(INPUT);
  await page.keyboard.press("Control+a");
  await page.keyboard.press("Delete");

  console.log(`[ACTION] Selected software: ${labelText.trim()}`);
}
export async function addSoftware(page, software) {
  const list = Array.isArray(software) ? software : [software];
  for (const name of list) {
    await searchAndSelectSoftware(page, name);
  }
}

export async function installSoftware(page, { dryRun = false } = {}) {
  if (dryRun) {
    console.log("[DRY RUN] Skipping: Add or Remove Software (install)");
    return;
  }
  console.log("[ACTION] Clicking Add or Remove Software");
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadButtonCommit_input",
  );
  await page.click("#ctl00_ContentPlaceHolderMain_RadButtonCommit_input");
  await page.waitForLoadState("networkidle");
  console.log("[ACTION] Install triggered");
}
