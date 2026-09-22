# Open Doc landing page

A six-section landing page for the native macOS app. Built with React, Vite, Tailwind v4, GSAP, Phosphor icons, and Satoshi. It does not edit the native app or the user's dock.

## Development

```sh
cd website
npm ci
npm run dev
```

The predev and prebuild scripts fetch original Satoshi webfonts from Fontshare if missing. They are served locally by the site. Font binaries are ignored by Git; the original license and source notice are in `public/fonts/`.

## Production

```sh
npm run build
npm run preview -- --port 4174
```

The build pre-renders HTML and hydrates its interactive controls. Downloads link to GitHub Releases. Fonts and required images are served locally.

The public site is [ffinnis.github.io/opendoc](https://ffinnis.github.io/opendoc/). The `Deploy website` GitHub Actions workflow builds and publishes changes to `website/` on `main`. It can also be started manually. Pages uses the `github-pages` environment and uploads only `website/dist/`.

To reproduce the Pages build and preview its repository subpath:

```sh
SITE_BASE_PATH=/opendoc/ npm run build
SITE_BASE_PATH=/opendoc/ npm run preview -- --port 4175
LANDING_TEST_URL=http://127.0.0.1:4175/opendoc/ npm test
```

`SITE_BASE_PATH` is shared by Vite and the HTML pre-renderer. It defaults to `/` for local development or hosting at a domain root.

## Browser checks

With the production preview running:

```sh
npm test
```

Checks use installed Google Chrome through Playwright. Set `LANDING_TEST_URL` to test another preview URL. They cover responsive layout, keyboard navigation, working widgets, theme persistence, real scroll transforms, pause cleanup, live reduced-motion changes, and static HTML without JavaScript.

## Design and interaction

Six horizontal references in `design/` establish the coastal imagery, forest palette, populated dock, and native settings screenshot. [design/MOTION.md](design/MOTION.md) records the current motion and interaction decisions. [ASSETS.md](ASSETS.md) records provenance.

The hero has a short entrance sequence and a subtle background scroll effect. Widget cards separate from a stack on desktop; mobile uses a swipeable carousel. The focus timer supports start, pause, resume, and reset. The sticky note saves in browser local storage. The clock shows local time. These are page demos, not changes to an installed dock.

The animation toggle pauses GSAP and the widget-name marquee and remembers the choice. System reduced motion disables both. Scroll reveals preserve readable text contrast throughout. Appearance disclosures expand smoothly where supported. The app-group tabs, widget tabs, and copy control work with the keyboard. Theme selection applies before paint, and the app-folder artwork follows it.

[QA.md](QA.md) records builds, executed checks, and measured limitations. No analytics, backend, or externally hosted runtime assets are included.
