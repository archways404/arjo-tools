// -------------------------------------------------------
// Shared / common actions
// -------------------------------------------------------

export function computerADdescription(pc_model, fullName) {
  return `${fullName} ${pc_model}`;
}

export async function navigateTo(page, url) {
  console.log(`[NAV] Going to ${url}`);
  await page.goto(url);
  await page.waitForLoadState("networkidle");
}

export async function clickRole(page, roleName) {
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
// Retry wrapper
// -------------------------------------------------------

/**
 * Retries an async function up to `retries` times with a delay between attempts.
 *
 * @param {string} label       - Name shown in logs, e.g. "searchPCEditADComputer"
 * @param {() => Promise} fn   - The async function to run (no args — use a closure)
 * @param {object} options
 * @param {number} options.retries - Max attempts (default: 3)
 * @param {number} options.delay   - Ms to wait between attempts (default: 2000)
 */
export async function withRetry(label, fn, { retries = 3, delay = 2000 } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      console.warn(
        `[RETRY] ${label} failed (attempt ${attempt}/${retries}): ${err.message}`,
      );
      if (attempt < retries) {
        console.log(`[RETRY] Waiting ${delay}ms before next attempt...`);
        await new Promise((r) => setTimeout(r, delay));
      }
    }
  }
  throw new Error(
    `[RETRY] ${label} gave up after ${retries} attempts: ${lastError.message}`,
  );
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
