// -------------------------------------------------------
// Edit Computer actions
// -------------------------------------------------------

export async function openEditComputer(page) {
  console.log("[ACTION] Navigating to Edit Computer");
  await page.goto(`${process.env.SWC_BASE_URL}/EditComputer`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Edit Computer page loaded");
}

export async function searchPCEditComputer(page, pcName) {
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

export async function selectTemplate(page, templateName) {
  console.log(`[ACTION] Selecting template: ${templateName}`);

  await page.click("#ctl00_ContentPlaceHolderMain_RadComboBoxTemplate_Input");

  await page.waitForSelector("ul.rcbList", { timeout: 15000 });
  await page.locator("ul.rcbList li").filter({ hasText: templateName }).click();

  console.log(`[ACTION] Selected template: ${templateName}`);
}

export async function applyChanges(page, { dryRun = false } = {}) {
  if (dryRun) {
    console.log("[DRY RUN] Skipping: Apply Changes");
    return;
  }
  console.log("[ACTION] Applying changes");
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadButtonApply_input",
  );
  await page.click("#ctl00_ContentPlaceHolderMain_RadButtonApply_input");
  await page.waitForLoadState("networkidle");
  console.log("[ACTION] Changes applied");
}
