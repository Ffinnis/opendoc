# Image-to-code specification

This records the baseline reference translation. See [MOTION.md](MOTION.md) for the current Satoshi typography, GSAP motion, and functional widget demos.

The six horizontal section references are the visual source. Hero, organization, and widgets were regenerated after the user's populated-dock correction. The other three references retain the same type, color, and layout family.

## Shared system

Use Geist, a close available grotesk match, with medium weight, tight display tracking, and normal body tracking. Paper is #f0f3ef, forest text #153d33, secondary text #526c61, sage field #dce5dd. Desktop gutters are 5% capped by a 1280px content width. Body copy is 19–22px; links and tabs 16–18px. Native objects retain their own corners and shadows. Text and controls sit directly on the page.

## Hero

The 1280 × 800 reference has a 72px header, a centered two-line title, one sentence of support, a forest pill CTA, and the complete populated dock across the bottom. Title scale is about 96px with matching line height. The dock sits below the CTA with generous separation. Keep the title, CTA, and full dock within a 1280 × 720 laptop viewport. At mobile widths, preserve readable dock icons through local horizontal scrolling. The landscape fills the section; it is not an inset card.

## Organization

The left 58% is a row of three complete native app folders, followed by underlined tabs and a short description. The right column holds “A place for / every app.”, body copy, and an underlined guide link. Headline approximately 76px at 1440px, body 22px. No outer image card. Use a freshly generated folder asset, not the previous oversized crop of the full dock. Stack copy before the image on mobile. Tabs select the associated description, with arrow-key support.

## Widgets

“Small widgets. / Less switching.” is left aligned near the top, about 84px at 1440px. A single support sentence sits below it. A complete three-widget shelf is offset right below the copy, followed by left-aligned underlined selectors. Its clock, timer, and note must all be visible, including the shell's rounded ends. The generated full shelf is a new asset, not a crop of a page reference. Background is pale sage with coastal grass near the lower edge. On mobile show the whole shelf at the available width and retain descriptive text beneath it.

## Appearance

Open two-column layout with a two-line headline and fine accordion rules on the left, a real native settings capture on the right. Scale headline to approximately 58px within its column. The screenshot retains its original proportions. Controls use 23–25px labels and 17px body text. Mobile stacks the screenshot below the disclosure controls.

## Agents

Generous vertical whitespace. A small command icon precedes “Ask for it. / Add it to your dock.” on the left. The right column has a short example request, one outlined command field with a copy control, and support copy. Use one light rounded outline around the command, not terminal chrome or nested panels. Command text remains selectable. Keep copy feedback and install information functional.

## Download

Centered real app icon, “Make it your dock.” at roughly 88px, short support copy, and a larger version of the same forest download button. Pale sage gradually enters near the footer. Compatibility and the Dock-restoration disclosure remain readable. Footer separates brand from three source links with a fine rule.

## Verification

Inspect complete desktop sections, 1280 × 720 and 1366 × 768 first views, mobile widths from 320px, dark theme, and reduced motion. All generated visuals are illustrative. The actual settings capture and app icon remain unchanged. Page copy and controls are HTML, not text embedded in section screenshots.
