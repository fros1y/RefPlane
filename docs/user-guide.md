# Underpaint — User Guide

## Overview

Underpaint helps painters and illustrators study reference photographs before they paint. Load any image from your photo library, apply one of the study modes, and use the results to plan your values, color palette, and paint mixtures.

Every step happens on your device. No internet connection is required.

---

## Getting Started

1. Open Underpaint.
2. Tap **Choose a reference image** (or the photo icon in the toolbar) to pick a photo from your library.
3. Once the image loads, tap a mode in the bar at the bottom of the canvas to start studying.

To replace the current image, tap the photo icon again.

---

## Study Modes

The mode bar below the canvas gives you four ways to look at your reference.

### Original

Shows your reference photo with no changes. Use this as your baseline while toggling between other modes.

### Tonal

Converts the image to grayscale using the Rec. 709 luminance formula — the same standard used in professional broadcast video. The result is a perceptually accurate black-and-white version of your scene.

Use Tonal to:
- study the light-and-shadow structure of a scene before committing to color
- check whether your composition reads clearly in value
- compare a target photo to a grayscale of your painting-in-progress

### Value

Reduces the image to a small number of discrete tonal bands. The number of bands is adjustable (typically 3–7). Each band is rendered as a flat tone, stripping away photographic gradation to leave only the major value structure.

Use Value to:
- plan a painting with a clear, simplified value pattern
- identify where tonal structure is weak or ambiguous
- simplify a complex scene into the shapes you actually need to paint

**Adjustments (Value mode)**
- *Number of values* — how many distinct tonal bands the image is divided into (drag the slider or tap + / –)
- *Thresholds* — the boundary points between each band; drag each handle to fine-tune where one value ends and the next begins

### Color

Clusters the image into its dominant color regions using perceptual k-means clustering in the Oklab color space. Each region is rendered as a flat, uniform color.

Use Color to:
- read the color composition of a scene at a glance
- find the dominant hues and their relative areas
- prepare a limited palette before mixing

**Adjustments (Color mode)**
- *Number of colors* — how many distinct color regions to extract
- *Paint recipes* — see [Paint Recipes](#paint-recipes) below

---

## Simplify

The **Simplify** toggle runs your reference through an on-device super-resolution model that smooths texture while preserving major shapes.

Use Simplify to strip away photographic noise and see underlying forms more clearly — before applying a study mode.

**Controls**
- *Simplify Image* toggle — enables or disables the simplification pass
- *Strength* slider — controls how aggressively texture is smoothed (0 = off, 1 = maximum)

Processing takes a moment, especially on older devices. The canvas shows a progress indicator while the model runs.

---

## Depth Effects

Enable **Depth Effects** to separate your scene into foreground and background using an on-device depth estimation model. Once enabled, you can selectively treat the background while leaving the foreground crisp — useful for isolating the subject you plan to paint.

### Controls

| Setting | Description |
|---------|-------------|
| *Depth Effects* toggle | Enables depth estimation and background processing |
| *Background* slider | Sets the depth cutoff — everything further than this point is treated as background |
| *Background* mode | How the background is treated (see modes below) |
| *Intensity* slider | How strongly the background effect is applied (0–100%) |

### Background Modes

| Mode | Effect |
|------|--------|
| **Depth Effects** | Applies a painterly de-emphasis: reduced contrast, muted color, and a warm-to-cool atmospheric shift that pushes the background visually into the distance |
| **Blur** | Gaussian blur that softens the background, simulating a shallow depth of field. The blur radius scales with intensity — at maximum, the background is heavily smoothed |
| **Remove** | Replaces the background with a solid neutral tone, isolating the foreground subject entirely |

### Surface Contours

When depth effects are active, you can overlay **surface contour lines** (isolines) on the image. These trace lines of equal depth across your scene, revealing the three-dimensional form of objects.

Use contours to:
- understand the spatial structure of your reference
- see how forms recede in space
- guide your brushwork along the surface of objects

**Contour controls**

| Setting | Description |
|---------|-------------|
| *Surface Contours* toggle | Shows or hides the contour overlay |
| *Levels* | Number of contour lines (2–64) |
| *Line Style* | Auto (contrasts against the image), Black, White, or Custom |
| *Color* | Custom line color (only visible when Line Style is Custom) |
| *Opacity* | How transparent the contour lines are |

---

## Paint Recipes

When **Color** mode is active, you can enable paint recipes in the inspector. Underpaint will suggest a physical paint mixture for each color region using **Golden Heavy Body Acrylic** paints.

The mixing model uses **Kubelka-Munk spectral theory** — a physical model of how pigments absorb and scatter light. This means the suggested mixtures reflect real pigment behavior rather than simple RGB blending.

### Palette Presets

Choose which paints are available for mixing:

| Preset | Contents |
|--------|----------|
| **All** | Full library of 78 Golden Heavy Body colors |
| **Zorn** | Ivory Black, Yellow Ochre, Cadmium Red Medium, Titanium White |
| **Primary** | A split-primary set of warm and cool primaries plus white and black |
| **Warm** | Warm-biased colors: yellows, oranges, reds, warm whites |
| **Cool** | Cool-biased colors: blues, greens, cool whites, violets |

### Reading a Recipe

Each color region shows:
- A color swatch for the region
- The contributing paint names
- The approximate mixing ratio for each paint (as a percentage)

The percentages describe the pigment concentrations in the predicted mixture. They are a guide, not a precise formula — use them as a starting point and adjust to taste.

### Adjustments

- *Max pigments per mix* — caps how many paints can appear in a single recipe (fewer = simpler mixes)
- *Minimum contribution* — hides paints that contribute less than this percentage (filters out trace amounts)

---

## Grid Overlay

Tap the grid icon in the toolbar to add a configurable reference grid.

### Settings

| Setting | Description |
|---------|-------------|
| *Divisions* | Number of grid cells across (and down) |
| *Cell shape* | **Square** cells or cells that fit the image proportions |
| *Diagonals* | Add diagonal lines across each cell |
| *Center lines* | Add a horizontal and vertical center line |
| *Line color* | **Auto** (contrasts against the image), black, white, or a custom color |
| *Opacity* | How transparent the grid lines are |

The grid helps you transfer proportions from your reference to your canvas by providing registration points in both images.

---

## Compare

Tap the **Compare** button in the toolbar to enter Compare mode.

A split-screen view appears with a draggable handle dividing the canvas. The left side shows the **original** image; the right side shows the **processed** image in whatever mode is currently active.

Drag the handle left or right to reveal more of either side.

Tap **Compare** again (or tap **Done**) to return to the normal view.

---

## Export

To save or share the processed image:

1. Tap the **Share** (export) icon in the toolbar.
2. The iOS share sheet appears.
3. Choose where to send the image — save to Photos, send to Files, copy, AirDrop, or open in another app.

The exported image is the current processed view: the mode result with any grid overlay applied.

---

## Privacy

Underpaint collects no personal data. The app uses no analytics, no tracking, and no accounts. Every image you choose is processed entirely on your device. Nothing is sent to any server.

The app requests access to your photo library only so you can choose reference images. If you prefer, you can share photos from another app directly into Underpaint without granting library access.

---

## Frequently Asked Questions

**Can I use Underpaint with my own photos?**
Yes. Tap the photo icon to pick any image from your library.

**Does Underpaint work without an internet connection?**
Yes. All processing — including the super-resolution simplification model and paint recipe calculations — runs entirely on your device.

**What paints does the recipe feature cover?**
The current database includes 78 Golden Heavy Body Acrylic colors with full spectral data. The Kubelka-Munk model uses measured absorption and scattering coefficients for each pigment, so the predictions are physically grounded.

**How accurate are the paint recipes?**
The recipes are physically meaningful approximations based on spectral pigment data, but paint behavior varies with medium, dilution, layering, and application technique. Treat the recipes as informed starting points, not exact formulas.

**Why does processing take a moment?**
The Value and Color modes run clustering algorithms across the full image. The Simplify pass and depth estimation both run on-device machine-learning models. These operations can take a few seconds depending on device and image size. The canvas shows a progress indicator while work is underway.

**The app asked for access to my photos. Why?**
Underpaint needs photo library access to let you pick a reference image with the standard image picker. If you choose not to grant access, you can still use the app by sharing an image into it from Photos or another app.

**Can I use Underpaint on iPad?**
Yes. On iPad (and on iPhone in landscape), the inspector panel appears alongside the canvas so you can adjust settings and view the image at the same time.

**What image formats are supported?**
Underpaint accepts any image format that iOS supports, including JPEG, PNG, HEIC, and RAW formats from the Photos library.

**Is there a limit on image size?**
Images larger than 1,600 pixels on the long edge are scaled down before processing. This keeps processing fast and memory use reasonable on all supported devices.

**Where can I report a bug or request a feature?**
The project is open source under the GNU AGPL v3. Visit the repository on GitHub to open an issue or contribute.
