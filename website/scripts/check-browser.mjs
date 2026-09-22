import { chromium } from "playwright";
import assert from "node:assert/strict";

const url = process.env.LANDING_TEST_URL || "http://127.0.0.1:4174/";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const context = await browser.newContext({
  permissions: ["clipboard-read", "clipboard-write"],
});
const page = await context.newPage();
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const selected = (name) => page.getByRole("tab", { name, exact: true });
async function settle() {
  await page.waitForTimeout(1100);
}
try {
  await page.goto(url);
  await page.waitForFunction(
    () => document.querySelector("main").dataset.motionReady === "true",
  );
  for (const [width, height] of [
    [320, 640],
    [390, 844],
    [768, 720],
    [1024, 768],
    [1280, 720],
    [1366, 768],
    [1440, 900],
  ]) {
    await page.setViewportSize({ width, height });
    await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
    await settle();
    const layout = await page.evaluate(() => {
      const box = (selector) => {
        const r = document.querySelector(selector).getBoundingClientRect();
        return { top: r.top, bottom: r.bottom, height: r.height };
      };
      return {
        overflow: document.documentElement.scrollWidth > innerWidth,
        title: box("h1"),
        line: box(".hero-title-line"),
        actions: box(".hero-actions"),
        dock: box(".hero-dock-wrap"),
        height: innerHeight,
      };
    });
    assert.equal(layout.overflow, false, `Page overflow at ${width}`);
    assert.ok(
      Math.abs(layout.title.height - layout.line.height * 2) < 2,
      `Hero is not two lines at ${width}`,
    );
    assert.ok(
      layout.title.bottom < layout.actions.top &&
        layout.actions.bottom < layout.dock.top,
      `Hero overlap at ${width}`,
    );
    assert.ok(layout.dock.bottom <= height, `Dock below fold at ${width}`);
  }
  console.log(
    "PASS: seven responsive viewports, two-line hero, visible CTAs and dock, no overflow",
  );

  await selected("Everyday").focus();
  await page.keyboard.press("ArrowRight");
  assert.equal(
    await selected("Development").getAttribute("aria-selected"),
    "true",
  );
  await page.keyboard.press("End");
  assert.equal(
    await selected("Creative").getAttribute("aria-selected"),
    "true",
  );
  assert.match(
    await page.locator("#group-description").innerText(),
    /creative tools/,
  );

  await page
    .getByRole("button", { name: "Start focus timer", exact: true })
    .click();
  await page.waitForTimeout(1200);
  assert.notEqual(
    await page.locator(".focus-widget .widget-value").innerText(),
    "25:00",
  );
  await page
    .getByRole("button", { name: "Pause focus timer", exact: true })
    .click();
  const frozen = await page.locator(".focus-widget .widget-value").innerText();
  await page.waitForTimeout(1200);
  assert.equal(
    await page.locator(".focus-widget .widget-value").innerText(),
    frozen,
  );
  await page
    .getByRole("button", { name: "Reset focus timer", exact: true })
    .click();
  assert.equal(
    await page.locator(".focus-widget .widget-value").innerText(),
    "25:00",
  );
  await page
    .getByLabel("Your sticky note", { exact: true })
    .fill("Finish the animation review.");
  await page.reload();
  assert.equal(
    await page.getByLabel("Your sticky note", { exact: true }).inputValue(),
    "Finish the animation review.",
  );
  await page
    .locator(".appearance-options summary")
    .filter({ hasText: "Glass & tint" })
    .click();
  assert.equal(
    await page.locator(".appearance-options details[open] summary").innerText(),
    "Glass & tint",
  );
  await page.getByRole("button", { name: "Copy command", exact: true }).click();
  assert.equal(
    await page.evaluate(() => navigator.clipboard.readText()),
    "opendoc schema",
  );
  console.log(
    "PASS: keyboard tabs, timer countdown/pause/reset, note persistence, accordion, clipboard",
  );

  await page.setViewportSize({ width: 390, height: 844 });
  await selected("Sticky note").click();
  await settle();
  assert.equal(
    await selected("Sticky note").getAttribute("aria-selected"),
    "true",
  );
  const noteBounds = await page.locator(".note-widget").boundingBox();
  assert.ok(
    noteBounds.x >= 0 && noteBounds.x + noteBounds.width <= 390,
    "Selected mobile widget is clipped",
  );
  await page.getByRole("button", { name: "Next widget", exact: true }).click();
  await settle();
  assert.equal(await selected("Clock").getAttribute("aria-selected"), "true");
  await page
    .getByRole("button", { name: "Previous widget", exact: true })
    .click();
  await settle();
  assert.equal(
    await selected("Sticky note").getAttribute("aria-selected"),
    "true",
  );
  console.log("PASS: mobile carousel and selected-card visibility");

  await page.setViewportSize({ width: 1440, height: 900 });
  await page.evaluate(() => {
    const y =
      document.querySelector(".widget-stage").getBoundingClientRect().top +
      scrollY;
    scrollTo({ top: y - innerHeight * 0.93, behavior: "instant" });
  });
  await settle();
  const stacked = await page
    .locator(".focus-widget")
    .evaluate((e) => getComputedStyle(e).transform);
  await page.evaluate(() => {
    const y =
      document.querySelector(".widget-stage").getBoundingClientRect().top +
      scrollY;
    scrollTo({ top: y - innerHeight * 0.5, behavior: "instant" });
  });
  await settle();
  const spread = await page
    .locator(".focus-widget")
    .evaluate((e) => getComputedStyle(e).transform);
  assert.notEqual(stacked, spread, "Scroll does not animate widget stacking");
  await page
    .getByRole("button", { name: "Pause animations", exact: true })
    .click();
  assert.equal(
    await page
      .locator(".focus-widget")
      .evaluate(
        (e) =>
          new DOMMatrix(
            getComputedStyle(e).transform === "none"
              ? undefined
              : getComputedStyle(e).transform,
          ).isIdentity,
      ),
    true,
  );
  assert.equal(
    await page
      .locator(".marquee-track")
      .evaluate((e) => getComputedStyle(e).animationPlayState),
    "paused",
  );
  await page.reload();
  assert.equal(
    await page.locator("main").getAttribute("data-motion"),
    "paused",
  );
  await page
    .getByRole("button", { name: "Enable animations", exact: true })
    .click();
  await page.emulateMedia({ reducedMotion: "reduce" });
  await settle();
  assert.equal(
    await page
      .locator(".focus-widget")
      .evaluate(
        (e) =>
          new DOMMatrix(
            getComputedStyle(e).transform === "none"
              ? undefined
              : getComputedStyle(e).transform,
          ).isIdentity,
      ),
    true,
  );
  assert.equal(
    await page
      .locator(".scrub-word")
      .first()
      .evaluate((e) => getComputedStyle(e).opacity),
    "1",
  );
  assert.equal(
    await page
      .locator(".marquee-track")
      .evaluate((e) => getComputedStyle(e).animationName),
    "none",
  );
  await page.emulateMedia({ reducedMotion: "no-preference" });
  for (const width of [390, 1440, 390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(200);
  }
  await page
    .getByRole("button", { name: "Pause animations", exact: true })
    .click();
  assert.equal(
    await page
      .locator(".focus-widget")
      .evaluate(
        (e) =>
          new DOMMatrix(
            getComputedStyle(e).transform === "none"
              ? undefined
              : getComputedStyle(e).transform,
          ).isIdentity,
      ),
    true,
  );
  console.log(
    "PASS: actual scroll motion, pause cleanup/persistence, live reduced-motion changes, repeated resizing",
  );

  await page
    .getByRole("button", { name: "Switch to dark theme", exact: true })
    .click();
  await page.reload();
  assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");
  await page.locator(".group-art img").scrollIntoViewIfNeeded();
  await page.locator(".group-art img").evaluate((e) => e.decode());
  assert.match(
    await page.locator(".group-art img").evaluate((e) => e.currentSrc),
    /app-groups-dark/,
  );
  const hashes = await page
    .locator('a[href^="#"]')
    .evaluateAll((links) => links.map((a) => a.hash));
  for (const hash of hashes)
    assert.equal(await page.locator(hash).count(), 1, `Broken anchor ${hash}`);
  assert.deepEqual(errors, []);

  const staticPage = await browser.newPage({
    javaScriptEnabled: false,
    colorScheme: "dark",
    viewport: { width: 1280, height: 720 },
  });
  await staticPage.goto(url);
  assert.equal(await staticPage.locator("h1").count(), 1);
  assert.match(
    await staticPage.locator("noscript").innerText(),
    /Enable JavaScript/,
  );
  assert.equal(
    await staticPage.locator(".hero .download").getAttribute("href"),
    "https://github.com/Ffinnis/opendoc/releases",
  );
  assert.equal(
    await staticPage
      .locator(".scrub-word")
      .first()
      .evaluate((e) => getComputedStyle(e).opacity),
    "1",
  );
  console.log(
    "PASS: saved dark theme/artwork, anchor links, no JavaScript errors, usable static HTML",
  );
} finally {
  await browser.close();
}
