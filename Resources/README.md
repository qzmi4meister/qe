# QE icon

`AppIcon-fullbleed.png` is the build source: the supplied white monogram on a black rounded tile with an opaque dark background, edited with built-in ImageGen to make its strokes approximately 1.5 times thicker. The PNG is 1254 × 1254 pixels.

`scripts/build.sh` generates sizes from 16 to 1024 pixels and packs them into `QE.app/Contents/Resources/AppIcon.icns`.

`AppIcon.png` is the previous blue icon with a transparent margin. It is retained as an earlier design and is not used by the build.

## Stroke-weight edit prompt

Use case: precise-object-edit. Asset type: production macOS app icon. Edit target: the attached existing icon. Change ONLY the stroke weight of the white monogram: increase all its strokes to 1.5 times their current thickness (50% thicker), including the curved bowl, horizontal middle bar, lower horizontal segment and descending rounded vertical tail. Current stroke is approximately 75 pixels on the 1254-pixel reference, target approximately 112 pixels at that same scale. Preserve the exact recognizable custom e/q-shaped monogram, path centerlines, overall composition, optical placement, rounded tail ending, white/off-white coloring, black rounded tile, corner radii, outer dark background and margins. Do not substitute a font, add letters or redesign the logo. Keep counters open while making the symbol substantially bolder and more legible at small app icon sizes. Preserve the opaque square background; no transparency. Return only the finished square icon image.
