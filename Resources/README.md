# QE icon

`AppIcon-fullbleed.png` is the build source: the supplied white monogram, edited with built-in ImageGen to make its strokes approximately 1.5 times thicker, remove the inset tile and outer margins, and enlarge the mark by approximately 20%. The opaque black background extends to every edge; no smaller rounded tile is drawn inside the canvas.

`scripts/build.sh` generates sizes from 16 to 1024 pixels and packs them into `QE.app/Contents/Resources/AppIcon.icns`.

`AppIcon.png` is the previous blue icon with a transparent margin. It is retained as an earlier design and is not used by the build.

## Stroke-weight edit prompt

Use case: precise-object-edit. Asset type: production macOS app icon. Edit target: the attached existing icon. Change ONLY the stroke weight of the white monogram: increase all its strokes to 1.5 times their current thickness (50% thicker), including the curved bowl, horizontal middle bar, lower horizontal segment and descending rounded vertical tail. Current stroke is approximately 75 pixels on the 1254-pixel reference, target approximately 112 pixels at that same scale. Preserve the exact recognizable custom e/q-shaped monogram, path centerlines, overall composition, optical placement, rounded tail ending, white/off-white coloring, black rounded tile, corner radii, outer dark background and margins. Do not substitute a font, add letters or redesign the logo. Keep counters open while making the symbol substantially bolder and more legible at small app icon sizes. Preserve the opaque square background; no transparency. Return only the finished square icon image.

## Padding correction prompt

Use case: precise-object-edit. Asset type: full-bleed macOS application icon source. Edit target: the attached bold white e/q monogram icon. Correct ONLY its padding and background geometry: remove the dark gray outer surround and the inset rounded-square tile silhouette entirely. The background must be uniform solid black edge-to-edge across the entire square canvas, including every corner: no gray outer frame, no inset tile, no pre-rounded outline, no shadow, no transparency. Preserve the exact existing bold white custom monogram, all strokes and their relative thickness, bowl, horizontal bars and rounded descending tail. Enlarge the whole monogram uniformly by approximately 20% about the canvas center, without stretching or changing its shape. Aim for the mark to occupy about 77% of canvas height and 60% of canvas width, optically centered, with comfortable clearance on all sides. Keep the same white/off-white mark color. Do not redraw it as a font or add any symbols. Flat front-facing square production asset only.
