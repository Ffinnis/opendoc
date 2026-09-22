# README media

These files accompany the root README and are included in Git. They do not depend on the ignored local video project or the website build.

| File | Source and purpose |
| --- | --- |
| `opendoc.png` | 128px export of this repository's application icon. |
| `appearance.png` | Unmodified native Appearance settings capture from an isolated `--ui-testing` session with seeded docks. |
| `widget-library.png` | Unmodified native Focus timer library capture from the same isolated session. |
| `opendoc-demo.gif` | Complete seven-second opening scene of the existing revision 6 demo, encoded at 960 × 540 and 12 fps for inline README playback. It ends after the folder interaction, before the next scene begins. |
| `opendoc-demo.mp4` | Original revision 6 demo: 39 seconds, 1920 × 1080, H.264 at 60 fps with AAC audio. |

The film combines native captures with staged animations based on Open Doc's implementation. Folder interactions, independent docks, timer controls, and the agent-created custom widget are illustrative demonstrations. The external agent conversation is staged; it is not a recorded execution or timing claim. The render frame rate does not measure the application's performance. All shown profiles and notes are sample data.

The source project was produced locally under `videos/opendoc-demo/` and remains ignored by Git. No source app-icon files, desktop wallpaper, music, or sound-effect tracks are redistributed separately here. The completed film depicts macOS application icons and desktop artwork belonging to their respective owners; the repository's MIT license does not grant rights to those assets.

## Audio credits

Music: **Tech House vibes** by **Alejandro Magaña (A. M.)**, Mixkit track 130, used under the [Mixkit Stock Music Free License](https://mixkit.co/license/#musicFree). The finished soundtrack uses source seconds 15.75–54.75 with gain and fade adjustments. Music is included only as part of the finished video.

Sound effects: soft click, key press, short whoosh, and chime from the HyperFrames bundled media library. Its upstream credits identify [Pixabay](https://pixabay.com/sound-effects/) and the [Pixabay Content License](https://pixabay.com/service/license-summary/). The bundle does not identify individual original asset URLs or creators. No stronger provenance claim is made.

## Reproduce the GIF

With FFmpeg installed, run from the repository root:

```sh
ffmpeg -i docs/assets/opendoc-demo.mp4 -t 7 \
  -filter_complex '[0:v]fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
  -loop 0 docs/assets/opendoc-demo.gif
```

The original film is preserved unchanged. Only the inline preview is shortened and resampled.
