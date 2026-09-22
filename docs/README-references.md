# README references

Reviewed on 2026-09-22. These are popular macOS projects chosen for relevant presentation patterns, not a ranking of app quality. Star counts are the rounded values displayed by GitHub on that date.

| Project | GitHub stars | What works in its README | Applied to Open Doc |
| --- | ---: | --- | --- |
| [Cap](https://github.com/CapSoftware/Cap) | 22.6k | Centered identity, short description, navigation links, large product preview before the detailed explanation. | App icon, one-line promise, download/docs links, immediate animated demo. |
| [Ice](https://github.com/jordanbaird/Ice) | 29.7k | Clear macOS requirements and a gallery that shows individual capabilities. Separates implemented features from plans. | Compatibility beside the download, actual settings/library screenshots, only shipped features in the feature list. |
| [Maccy](https://github.com/p0deje/Maccy) | 21.7k | A small, concrete feature set; direct installation and usage instructions; practical answers to user questions. | Three installation steps, a first-use explanation, and compact FAQs. |
| [Stats](https://github.com/exelban/stats) | 42.0k | Real product UI near the top and explicit instructions for the downloaded artifact. | Visible product media and the ZIP-to-Applications installation path. |
| [Rectangle](https://github.com/rxhanson/Rectangle) | 30.0k | Leads with the product, requirements, and installation, then explains behavior and limits. | Requirements before setup and a clear explanation of Apple's Dock restoration and current limits. |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | 14.7k | App identity, screenshot gallery, direct download, and visible project status. | Native screenshot gallery and an explicit in-development note. Its README currently says development is on hold; it is a presentation reference, not an active-maintenance recommendation. |

The Open Doc README keeps its existing English language. Copy is original and grounded in this repository's user guide, widget guide, CLI examples, and release documentation. No reference-project copy, screenshots, logos, or videos were imported.

Media is stored under `docs/assets/`, outside the ignored local video and website build directories. The GIF displays directly on GitHub; a relative link opens the complete MP4. This avoids a placeholder attachment URL, an unsupported inline `<video>` element, or a localhost dependency. The GitHub result can be verified remotely after these files are pushed.

Homebrew installation, support channels, usage figures, and unshipped features were not added because this repository does not establish them as available. The website link was added with the GitHub Pages deployment workflow.
