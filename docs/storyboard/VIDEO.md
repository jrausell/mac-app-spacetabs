# Presentation video

The current presentation demonstrates SpaceTabs on an illustrated macOS desktop inside a 27-inch 16:9 monitor silhouette. The opening shows the transparent app icon and name immediately. The desktop includes a macOS menu bar, Dock, native app-window chrome, and colored zone borders. Dark gray tab panels remain visibly separate from the external app windows.

## Render locally

Requirements: Python 3 with Pillow, FFmpeg with H.264 support, and the macOS system fonts used by the drawing source. Audio synthesis uses the Python standard library.

```sh
python3 docs/storyboard/render_desktop_video.py
```

Use `--preview-only` to export review frames without encoding.

Outputs in the ignored `.local/presentation-desktop/` directory:

- `SpaceTabs-Desktop-QHD.mp4`: 2560 × 1440, 30 fps, 70 seconds, H.264 video and stereo AAC audio.
- `index.html`: local player with chapter buttons and a download link.
- `manifest.json`: dimensions, timing, monitor reference, audio description, and chapters.
- `preview-01.png` through `preview-12.png`: lossless QHD review frames.
- `upbeat-soundtrack.wav`: original 112 BPM plucked melody, bass, and light percussion.

The monitor's screen has a true 16:9 aspect ratio. The physical diagonal is a composition reference, not metadata that a video file can encode. Desktop artwork is drawn at 3840 × 2160 before compositing into the QHD video, preserving readable type and window controls.

`render_concept.py` supplies the approved window treatment and typography. `desktop_art.py` supplies the macOS desktop, independent tab panels, colored zone outlines, app sprites, cursor, and keycaps. `render_desktop_video.py` supplies the action-led sequence, monitor silhouette, encoding, original rhythmic soundtrack, and chapter player.

## Demonstration sequence

1. Brand introduction, followed by overlapping windows.
2. Empty desktop with two zone outlines and independent tab bars.
3. Two columns changing into A/C on the left, with an animated split handle.
4. Browser assignment into B using Control + right-drag.
5. Notes assignment into A, keeping Browser in B.
6. More apps joining each zone and tabs accumulating.
7. Browser/Editor tab changes in B, with Notes and Terminal staying selected in A/C.
8. A visible Command-Tab switcher, an ordinary Finder window, and choosing SpaceTabs to restore the workspace.
9. Auto-hidden bars with expanded app frames; the current Control + Option + Command tap reveals floating bars without moving those frames again.
10. Preview moving from B to C: only an outline follows the drag; the app moves after release.
11. Focus B, next tab in B, and focused-window zoom/restore with visible key combinations.
12. Branded close over the organized desktop, without a black ending.

The artwork is an explanatory illustration, not a recording or evidence of real macOS Accessibility, focus, or gesture behavior. Rendering does not change running windows, app settings, or Accessibility permissions. No third-party screenshots, music, or video footage are reused.

## README media

The README links `docs/assets/spacetabs-presentation.mp4` and displays its looping GIF companion. The QHD MP4 is the quality reference; the GIF is a smaller preview for GitHub. Branding uses `Resources/icon-main-transparent.png`, preserving the original opaque icon separately.
