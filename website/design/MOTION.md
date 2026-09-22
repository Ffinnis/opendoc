# Motion and interaction specification

This pass extends the image-to-code baseline in IMPLEMENTATION.md. The gpt-taste deterministic selection used seed 59: cinematic center, Satoshi, carousel, inline typography image, marquee, scrubbed text, and card stacking. The carousel shows product examples and the marquee names supported widgets; neither implies customer endorsements.

## Page motion

The hero retains a 1152px maximum text width, two explicit lines, and two distinct actions. GSAP adds a short staggered entrance and a subtle desktop background scroll offset. The animation module loads after the initial font and backdrop are ready.

The widget shelf has three occupied columns with dense grid flow. As it enters on desktop, three overlapping widgets spread into their final row. Small screens use native horizontal scrolling and snap points, with tabs and previous/next controls. Timer, note, and clock remain usable while motion is paused.

The app-organization paragraph transitions word color from the accessible muted token to the stronger ink token. It never reduces the readability of the underlying text. The appearance screenshot gains a modest scroll-driven scale and rotation; its container entrance and image animation use separate elements to avoid transform conflicts.

The closing heading includes the actual app icon inline. Link arrows, icon buttons, underline indicators, disclosures, and focus states provide local feedback. The widget-name marquee pauses on hover and through the global animation control. It does not run without JavaScript.

## Accessibility and cleanup

A persistent control in the header pauses decorative motion. GSAP matchMedia owns and reverts its scroll triggers when the viewport or reduced-motion preference changes. The useGSAP scope is reverted on unmount. Reduced motion removes transforms and continuous loops. Content and download links render without JavaScript.

Product demos are labeled as examples. The note writes only the `opendoc-demo-note` browser-local key. Timer ticks use a deadline, so delayed callbacks do not accumulate interval drift. No timer notification or sound is promised. The native app and real dock data are untouched.
