# Landing page verification

Checked on 2026-09-22 against the production preview at http://127.0.0.1:4174.

## Build

`npm run build` passed, including font preparation, Vite production compilation, and static HTML pre-rendering. Initial JavaScript is 281.21 kB, 85.08 kB gzipped. The separate GSAP module is 115.31 kB, 45.32 kB gzipped, loaded after the initial font and backdrop. The font-preparation script was also executed with a missing file and reproduced the original font bytes.

No native macOS build ran because this change is limited to the website.

## Executed browser checks

`npm test` uses Playwright and installed Chrome. It checked 320 × 640, 390 × 844, 768 × 720, 1024 × 768, 1280 × 720, 1366 × 768, and 1440 × 900 viewports. The hero remained two lines, both actions and dock fit, and there was no page-level horizontal overflow.

The checks executed keyboard tab navigation, focus timer countdown/pause/reset, note persistence across reload, mobile carousel selection and card visibility, appearance disclosures, clipboard copy, saved dark theme, dark artwork selection, and internal anchor targets.

Motion checks measured changing card transforms across scroll positions. They also verified pause/reset geometry, persisted animation preferences, live changes to system reduced motion, and repeated desktop/mobile resizing. Static HTML checks disabled JavaScript and verified readable content and working download links. No page errors were reported.

## Visual review

After the reported Apple-icon defect, reviewed 24 individual section captures: all six sections at 1440px and 390px, in light and dark themes. The original Phosphor glyph had a flat lower contour that looked cropped. Replaced it with the Simple Icons silhouette, preserved padding around its path, and prevented flex shrinking in both download links. Also corrected the pressed transform that the hover rule previously overrode. No additional icon cropping or text collisions were found in those captures. Screenshots are under `.qa/screen-audit/`. The user's existing preview tab was refreshed and the closing button was visually verified there.

The full `npm test` browser suite passed again after this fix. Lighthouse results below are from the preceding motion pass and were not rerun for this icon correction.

Reviewed desktop, mobile, and dark full-page captures, the small laptop first view, and individual widget sections. Fixed an image-margin overlap at the organization heading, small-screen link naming, and insufficient contrast during word reveals. Both active and paused states were inspected. The generated product art and real native settings capture retain their documented provenance.

## Performance and accessibility

Latest mobile Lighthouse lab run:

| Category | Score |
| --- | --- |
| Performance | 92 |
| Accessibility | 100 |
| Best practices | 100 |
| SEO | 100 |

LCP: 3.3 seconds. CLS: 0.005. Total blocking time: 0 ms. LCP remains above the 2.5-second target in this simulated mobile run. These are local lab measurements, not real-user Core Web Vitals or a native frame-rate measurement. Earlier iterations measured 92–96 performance. The optional experimental agentic-browsing category scores 50 because no AI discovery manifests are provided.

The report is `.qa/lighthouse-polish-delivery.json`. Final visual captures use the `polished-` filename prefix under ignored `.qa/`. Browser checks live in `scripts/check-browser.mjs` and are tracked with the website.

No native app unit tests or UI tests ran. No live dock or user workspace was modified. The result is a local preview and deployable static build.
