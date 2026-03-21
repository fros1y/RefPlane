import path from 'node:path';
import { expect, test } from '@playwright/test';

const studioFixture = path.resolve('tests/fixtures/studio-scene.svg');

async function waitForStudioReady(page: import('@playwright/test').Page) {
  await expect(page.getByRole('button', { name: 'Export' })).toBeEnabled();
  await waitForProcessingSettled(page);
}

async function waitForProcessingSettled(page: import('@playwright/test').Page) {
  const overlay = page.locator('.processing-overlay');
  // Processing may start on a debounce after UI interactions.
  await page.waitForTimeout(250);
  if (await overlay.isVisible()) {
    await expect(overlay).toBeHidden({ timeout: 20000 });
  }
  // Ensure no late re-show before screenshot capture.
  await page.waitForTimeout(150);
  await expect(overlay).toBeHidden();
}

test('desktop visual baseline for loaded studio workspace', async ({ page }) => {
  await page.goto('/');
  await page.locator('input[type="file"]').setInputFiles(studioFixture);
  await waitForStudioReady(page);
  await expect(page).toHaveScreenshot('studio-workspace-desktop.png', { fullPage: true });
});

test('mobile visual baseline for loaded studio workspace', async ({ page, browserName }) => {
  test.skip(browserName !== 'chromium', 'Visual baselines are recorded against Chromium');
  await page.setViewportSize({ width: 412, height: 915 });
  await page.goto('/');
  await page.locator('input[type="file"]').setInputFiles(studioFixture);
  await waitForStudioReady(page);
  await expect(page).toHaveScreenshot('studio-workspace-mobile.png', { fullPage: true });
});
