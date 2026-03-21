import path from 'node:path';
import { expect, test } from '@playwright/test';

const studioFixture = path.resolve('tests/fixtures/studio-scene.svg');
const lineFixture = path.resolve('tests/fixtures/line-study.svg');

test.describe('desktop workflows', () => {
  test('uploads an image and exercises study controls', async ({ page }) => {
    await page.goto('/');
    await page.locator('input[type="file"]').setInputFiles(studioFixture);

    await expect(page.getByRole('button', { name: 'Export' })).toBeEnabled();
    await expect(page.locator('canvas')).toHaveCount(1);

    await page.getByRole('button', { name: 'Value Study' }).click();
    await page.getByRole('button', { name: 'Color Regions' }).click();
    await page.getByRole('button', { name: 'Temp', exact: true }).click();
    await page.getByRole('button', { name: 'Edges' }).click();

    await expect(page.getByRole('button', { name: 'Temp', exact: true })).toHaveClass(/active/);
    await expect(page.getByRole('button', { name: 'Edges' })).toHaveClass(/active/);
  });

  test('supports compare, crop, and export flows', async ({ page }) => {
    await page.goto('/');
    await page.locator('input[type="file"]').setInputFiles(lineFixture);

    await page.getByRole('button', { name: 'Compare' }).click();
    await expect(page.getByText('Before')).toBeVisible();
    await expect(page.getByText('After')).toBeVisible();
    await page.getByRole('button', { name: '×' }).click();

    await page.getByRole('button', { name: 'Crop' }).click();
    await expect(page.getByRole('button', { name: 'Apply Crop' })).toBeVisible();
    await page.getByRole('button', { name: 'Cancel' }).click();

    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Export' }).click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toMatch(/^refplane_/);
  });
});

test.describe('mobile workflows', () => {
  test.use({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true });

  test('keeps core controls usable on narrow screens', async ({ page }) => {
    await page.goto('/');
    await page.locator('input[type="file"]').setInputFiles(studioFixture);

    await page.getByRole('button', { name: 'Color Regions' }).click();
    await page.getByRole('button', { name: 'Edges' }).click();

    await expect(page.getByText('Adjustments')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Export' })).toBeEnabled();
  });
});
