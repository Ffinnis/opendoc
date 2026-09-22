# Asset provenance

## Populated dock

`public/assets/populated-dock.webp` is a composed marketing illustration generated with the built-in image_gen tool on 2026-09-22. It uses the bottom dock in the user's supplied screenshot as its reference, preserving the visual arrangement of colorful app icons and grouped folders while adding a local clock, focus timer, and yellow note. It is not an unmodified screenshot or an executed change to the user's dock.

The reference was `Screenshot 2026-09-22 at 16.14.48.png`, supplied in this task. The surrounding application and personal content are not bundled. App artwork belongs to its respective owners. The generated clock reads 16:14, the timer reads 25:00, and the note reads "Ship something good." These are illustrative values.

The generation prompt requested the user's populated dock, its actual app groups, native proportions and frontal orientation, plus those three sample widgets. It explicitly excluded the rejected gray browser/mail/code glyphs and all surrounding desktop content. The tool baked a checkerboard outside the dock even after a background-removal edit. The page uses a precise CSS image viewport to show only the rounded shelf, with no checkerboard visible. The first generation was retained because the attempted removal did not improve it.

## Native appearance settings

`public/assets/settings-appearance.png` is copied unchanged from the local demo's native asset directory. Its source ASSETS.md records direct capture from a locally built application launched with a fresh `--ui-testing` UUID and seeded profiles. No live workspace was used.

`public/assets/opendoc.png` is a 128px export of the repository's existing AppIcon.png. The current app icon is preserved.

## Coastal backdrop

`public/assets/coast.webp` was generated with the built-in image_gen tool, derived from the first section reference. It is fictional coastal landscape artwork, not a photograph of an identified location. Its prompt requested removal of all website text, controls, and dock from the section reference, preserving only the softly focused green coastal dunes, pale silver sky, ocean glimpse, forest/fern tones, and horizontal composition. It was encoded as WebP.

## Section references

The six separately generated horizontal design references are in `design/`, one each for hero, app organization, widgets, appearance, agents, and download. Each used the same forest-green and cool-neutral palette with refined grotesk typography. The hero, organization, and widget references were regenerated after the user's populated-dock correction. Their scale, spacing, copy, and responsive interpretation are documented in `design/IMPLEMENTATION.md`. The generated references are not shipped in `dist/`.

The original generated files remain in the image tool's output directory. All consuming assets have copies in the website. No Apple wallpaper or extracted third-party icon files are bundled separately.

## Fonts and icons

The Apple silhouette in both download links is the [Simple Icons Apple SVG](https://github.com/simple-icons/simple-icons/blob/develop/icons/apple.svg), distributed under CC0. Apple retains its trademark. The path is unchanged; the SVG viewBox adds breathing room around the leaf and lower contour. Other interface icons use Phosphor.

Interface icons come from `@phosphor-icons/react`; Satoshi is obtained from the official Fontshare API and self-hosted. The original FFL license and notice are in `public/fonts/`; font binaries are excluded from Git and prepared per checkout by `scripts/prepare-fonts.mjs`. License files remain in those packages. Copy is grounded in the repository README, widget docs, and CLI guide. Published releases were verified against the project's GitHub Releases page on 2026-09-22.

## Dedicated folder and widget artwork

`public/assets/app-groups.webp` and `widget-shelf.webp` were freshly generated from their individual section references on 2026-09-22. They show complete product objects rather than excerpts of the full hero dock. The folders contain illustrative messaging, development, and creative app groups. The widget shelf contains the clock, timer, and yellow note only. They are generated marketing illustrations, not untouched native captures. All surrounding site copy and controls are HTML.

The corresponding `-dark.webp` files were generated as background edits to those standalone assets, matching the dark page fields. Theme state selects the appropriate asset. CSS fades outer background margins without clipping the product objects. Sources remain in the image tool's output directory as `exec-82274ab2-9e5b-4c28-9bf3-04beb47fe27f.png`, `exec-96375af7-cead-4008-913d-eca24e99f5ed.png`, `exec-abbe1d13-8608-44c5-be59-3ed143021f57.png`, and `exec-0dde5001-e2f7-4c58-b6ba-a5a0c75e8140.png`. WebP exports use quality 88.

`populated-dock-1680.webp` is a proportional 1680px WebP export of the original standalone dock illustration, quality 82. Responsive image selection uses it on smaller screens while retaining the larger version for high-resolution displays.

## Motion and interactive widget pass

The live widget section now uses functional HTML controls styled after the generated shelf reference. It contains a real page timer, a browser-local note, and a local clock. The earlier `widget-shelf` images remain reference assets and are no longer requested by the page. No new raster imagery was generated for this motion pass. The populated hero dock, app folders, coastal background, and native appearance screenshot retain their documented sources.

Satoshi 400, 500, and 700 are original WOFF2 files downloaded from the official Fontshare CSS API. They are not subsetted or modified. The font-preparation script was tested with a missing font and reproduced the original bytes. GSAP and `@gsap/react` replace the previous Motion dependency.
