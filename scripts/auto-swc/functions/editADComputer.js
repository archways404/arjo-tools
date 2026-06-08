// -------------------------------------------------------
// Edit AD Computer actions
// -------------------------------------------------------

export async function openEditADComputer(page) {
  console.log("[ACTION] Navigating to Edit AD Computer");
  await page.goto(`${process.env.SWC_BASE_URL}/AD-Computers`, {
    waitUntil: "domcontentloaded",
    timeout: 15000,
  });
  console.log("[ACTION] Edit AD Computer page loaded");
}

export async function searchPCEditADComputer(page, pcName) {
  console.log(`[ACTION] Searching for PC on Edit AD Computer: ${pcName}`);

  await page.waitForTimeout(2000);

  await page.focus(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAdComputers_Input",
  );
  await page.click(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAdComputers_Input",
  );

  await page.type(
    "#ctl00_ContentPlaceHolderMain_RadComboBoxAdComputers_Input",
    pcName,
    { delay: 100 },
  );

  const item = await page.waitForSelector("li.rcbHovered", { timeout: 15000 });
  const text = await item.textContent();
  if (!text.includes(pcName)) throw new Error(`Unexpected match: ${text}`);
  await item.click();

  // Wait for template dropdown to appear — confirms PC was selected and page updated
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadMultiPageADComputer",
    { timeout: 15000 },
  );

  console.log(`[ACTION] Selected PC: ${pcName}`);
}

export async function setDescription(page, description) {
  console.log(`[ACTION] Setting description: "${description}"`);
  const selector = "#ctl00_ContentPlaceHolderMain_RadTextBoxDescription";
  await page.waitForSelector(selector);
  await page.fill(selector, description);
  console.log("[ACTION] Description set");
  await page.waitForTimeout(2000);
}

export async function saveADComputer(page, { dryRun = false } = {}) {
  if (dryRun) {
    console.log("[DRY RUN] Skipping: Save AD Computer");
    return;
  }
  console.log("[ACTION] Saving AD Computer");
  await page.waitForSelector(
    "#ctl00_ContentPlaceHolderMain_RadButtonSave_input",
  );
  await page.click("#ctl00_ContentPlaceHolderMain_RadButtonSave_input");
  await page.waitForLoadState("networkidle");
  console.log("[ACTION] AD Computer saved");
}
