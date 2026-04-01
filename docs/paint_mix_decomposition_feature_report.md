# Report: Designing a Paint-Mix Decomposition Feature for Image-to-Painting Assistance

## Executive summary

This feature would take an input image and convert its colors into **discrete mixtures of real paints** from a known paint set, such as a standard line of artist oils or acrylics. The right framing is **not** generic palette extraction. It is a **constrained inverse mixing problem**:

- **Inputs**
  - an image
  - a known set of paints
  - a paint-mixing model
- **Outputs**
  - a recommended subset of paints to use
  - per-region or per-pixel paint-mixture coefficients
  - an explicit balance between **accuracy** and **sparsity**
  - optionally, painting-oriented simplifications such as region merging and value grouping

The key design choice is the **forward paint model**: given a set of paint proportions, what color should that mixture produce? Once that is chosen, the inverse problem becomes: given a target image color, find a **small** nonnegative combination of available paints whose predicted mixed color is as close as possible to the target.

The most practical initial architecture is:

1. use a **fixed dictionary** of known paints
2. represent those paints with a **spectral / Kubelka–Munk-based** model if possible
3. solve the inverse problem with **sparse nonnegative optimization**
4. do this primarily at the **region** level rather than purely per-pixel
5. add global regularization so the overall image uses a manageable number of paints

This is substantially more useful for painting than ordinary RGB clustering or unconstrained NMF.

---

## 1. Product goal

### 1.1 Core user-facing goal

Given a photograph or painting reference, the system should answer questions like:

- Which paints from my paint set best explain this image?
- What limited palette should I use for this image?
- For this region, what mixture of my paints is the closest approximation?
- Can the image be simplified into paintable regions with plausible paint recipes?
- Can the system favor **fewer paints** and **simpler recipes** even if the numeric color match is slightly worse?

### 1.2 Expected outputs

At minimum, the feature should produce:

- **Global recommended palette subset**
  - e.g. 6 out of 18 available tube colors
- **Region-level paint recipes**
  - e.g. “face shadow: Ultramarine Blue 0.18, Burnt Sienna 0.12, Titanium White 0.70”
- **Confidence / error diagnostics**
  - e.g. ΔE00 or reconstruction residual
- **Complexity diagnostics**
  - paints used globally, average paints per region, recipe entropy
- **Optional painting assist layers**
  - region map
  - value map
  - edge map
  - paint-overlay legend

---

## 2. Why this is not ordinary palette extraction

Normal palette extraction methods such as k-means, median cut, or histogram peaks try to summarize image colors with a small set of representative colors. They are good for compression and rough color summaries, but they do **not** respect:

- actual tube paints
- physical paint mixing behavior
- sparse practical mixtures
- painting workflow constraints

For this feature, the problem is better described as:

> Approximate image colors using a small set of physically meaningful basis paints and sparse nonnegative mixtures.

That makes the relevant algorithm families:

- **fixed-dictionary nonnegative decomposition**
- **sparse nonnegative least squares**
- **group-sparse optimization**
- **mixed-integer formulations for hard paint-count limits**
- **region-aware regularized optimization**
- optionally **constrained NMF** if some parameters remain learnable

---

## 3. Data requirements

## 3.1 Paint dictionary

You need a catalog of available paints. For each paint, ideally you want:

- manufacturer / line
- paint name
- pigment index codes
- measured reflectance spectrum
- or, at minimum, measured color under standard conditions
- opacity / transparency metadata if available
- optional tint strength metadata
- optional drying / handling metadata if product workflow matters

### Good forms of data, in descending order of usefulness

1. **Spectral reflectance plus Kubelka–Munk-related data**
2. **Spectral reflectance only**
3. **CIELAB / XYZ under standard illuminant**
4. **sRGB swatches only**

The further down this list you go, the weaker the physical plausibility of the mixtures.

## 3.2 Candidate open or semi-open data sources

The most relevant currently visible sources include:

- **Golden Paint Spectra**, which states that Golden provided a spreadsheet for 78 acrylic paints and that each row includes CIE Lab values, reflectance samples from 400–700 nm, and K/S values for Kubelka–Munk mixing.
- **Artist Acrylic Paint Spectral, Colorimetric, and Image Dataset** by Roy S. Berns, which reports spectral data for 58 Golden Heavy Body Acrylics and computed spectra for 831 tints, tones, and masstones based on the two-constant opaque Kubelka–Munk model.
- **Artist Paint Spectral Database** by Roy S. Berns, which describes a spectral database developed from 19 Golden Heavy Body acrylic paints, with Kubelka–Munk optical data used to generate a larger dataset of spectra.

These are strong starting points for a prototype, especially on the acrylic side.

## 3.3 Oil paint data

Oil paint data appears less standardized and less plentiful in openly packaged form than acrylic data. However:

- manufacturer pigment listings and paint metadata are available from major paint makers
- at least some Kubelka–Munk oil mixing work has been published using a limited set of real oil paints
- a prototype could begin with acrylic spectral data while the product architecture remains medium-agnostic

If the goal is specifically oils, the likely long-term solution is to build or license a measured oil-paint dataset rather than depend entirely on public swatches.

---

## 4. Choosing the paint mixing model

This is the most important technical decision.

### 4.1 Option A: Linear mixing in RGB

Model:
- each paint has an RGB vector
- mixtures are weighted sums in RGB

Advantages:
- extremely simple
- fast
- easy to implement and optimize

Disadvantages:
- physically wrong for paint
- produces familiar failures such as poor blue-yellow greens and weak handling of opacity
- not appropriate for serious artist-facing results

Conclusion:
- useful only as a crude baseline or early UI prototype

### 4.2 Option B: Linear mixing in Lab / OKLab

Model:
- convert paint colors into a perceptual space
- blend linearly there

Advantages:
- better perceptual fit than RGB
- still simple

Disadvantages:
- still not a physical paint model
- blending in perceptual spaces is still not how pigments mix

Conclusion:
- a somewhat better baseline than RGB, but still not ideal

### 4.3 Option C: Kubelka–Munk (KM)

Model:
- each paint is characterized by wavelength-dependent absorption and scattering behavior
- mixtures combine those optical properties
- the resulting reflectance spectrum is converted to perceived color

Advantages:
- standard physically inspired model for opaque paint mixing
- much closer to real paint behavior
- supports actual concentration-based mixing and spectral prediction
- the right conceptual foundation for “real paint” decomposition

Disadvantages:
- more data-hungry
- requires per-paint optical characterization, or at least approximations
- inverse fitting is nonlinear
- can still be imperfect for layered, translucent, glazing-heavy, or texture-heavy situations

Conclusion:
- the best primary choice for a serious first-generation system

### 4.4 Option D: Latent RGB approximation to KM

There are more recent practical graphics approaches that emulate Kubelka–Munk-like behavior while staying in an RGB workflow. These are attractive if the goal is interactive painting or simple deployment, but for this feature they are best treated as an engineering shortcut, not the ground truth model.

Conclusion:
- good for UI interactivity or fallback approximations
- not the ideal internal truth model if the product claims real paint recipes

### 4.5 Recommendation

Use a **Kubelka–Munk-based spectral forward model** as the primary formulation, with a simpler fallback mode for lower-fidelity environments.

---

## 5. Mathematical formulation of the inverse problem

Let:

- \( p_1, \dots, p_M \) be the available paints
- \( x \) be the target color for a pixel or region
- \( h \in \mathbb{R}_{\ge 0}^M \) be nonnegative paint weights
- \( f(h) \) be the forward mixing model that predicts the resulting color from those paint weights

Then the inverse problem is:

\[
\min_{h \ge 0} \; \mathcal{L}(f(h), x) + \lambda \cdot \Omega(h)
\]

where:

- \( \mathcal{L} \) is reconstruction error
- \( \Omega(h) \) is a sparsity or complexity penalty
- \( \lambda \) controls the tradeoff

### Reconstruction term choices

Possible choices for \( \mathcal{L} \):

- squared error in reflectance space
- squared error in XYZ / Lab
- ΔE76 or ΔE00-based approximate objective
- weighted combinations of spectral and perceptual error

Recommended:
- fit in spectral or model-native space where possible
- evaluate and report error in **ΔE00**

### Sparsity / complexity penalty choices

Possible choices for \( \Omega(h) \):

- **L1 penalty**
- **hard cardinality constraint** (“use at most 3 paints”)
- **entropy penalty**
- **group sparsity**
- **global paint-usage penalty across the whole image**

Recommended:
- start with **L1-like sparsity**
- add optional hard caps on number of paints per region
- add a separate global penalty to favor reuse of the same small palette across the image

---

## 6. Which algorithms make sense

## 6.1 Fixed-dictionary sparse nonnegative least squares

This is the most natural baseline if the paint dictionary is known.

### Form
For each target region color:

\[
\min_{h \ge 0} \|f(h) - x\|^2 + \lambda \|h\|_1
\]

If \( f \) were linear, this would be sparse NNLS. With KM it becomes a constrained nonlinear sparse optimization problem.

### Strengths
- directly aligned with fixed paint sets
- naturally enforces nonnegative paint amounts
- easy to interpret
- straightforward to tune sparsity vs accuracy

### Weaknesses
- with nonlinear forward models, optimization is harder
- may need good initialization

### Recommendation
- **Primary algorithm family for version 1**

---

## 6.2 Nonnegative Orthogonal Matching Pursuit or greedy active-set search

Instead of optimizing all paints at once, greedily build a mixture:

1. start with white or the single best paint
2. add the paint that most improves the fit
3. re-optimize nonnegative coefficients over the active set
4. stop at 2–4 paints

### Strengths
- naturally sparse
- interpretable
- fast enough for interactive region fitting
- good when user-facing mixtures should stay small

### Weaknesses
- greedy, so not globally optimal
- may miss better combinations

### Recommendation
- **Excellent practical algorithm for region-level fitting**
- especially useful when the product needs explicit caps like “at most 3 paints per region”

---

## 6.3 Mixed-integer optimization

Formulate the problem with binary variables indicating whether a paint is active:

- \( z_i \in \{0,1\} \)
- \( h_i \le M z_i \)
- \( \sum_i z_i \le K \)

Then optimize reconstruction subject to a hard maximum number of paints.

### Strengths
- exact control of recipe complexity
- clean product behavior

### Weaknesses
- expensive
- not ideal for dense per-pixel solves
- better for small regions or offline optimization

### Recommendation
- useful for offline refinement or premium-quality mode
- probably too heavy for the first interactive implementation

---

## 6.4 Group-sparse and hierarchical sparse models

You usually do not want every region to use a totally different set of paints. You want:

- a small global palette
- sparse local mixtures from that palette

This suggests hierarchical regularization.

### Example objective
For region \( r \), with coefficients \( h^{(r)} \):

\[
\sum_r \mathcal{L}(f(h^{(r)}), x^{(r)}) \;+\;
\lambda_1 \sum_r \|h^{(r)}\|_1 \;+\;
\lambda_2 \sum_i \|[h_i^{(1)}, h_i^{(2)}, \dots]\|_2
\]

Interpretation:
- \( \lambda_1 \): few paints per region
- \( \lambda_2 \): few paints used globally

### Strengths
- very aligned with painting practice
- creates coherent limited palettes
- can dramatically improve usability

### Weaknesses
- more complex to implement and tune

### Recommendation
- **Very strong choice for version 2**
- possibly the single most product-relevant extension beyond plain sparse fitting

---

## 6.5 Constrained NMF

NMF is appropriate when some components are unknown and need to be learned. In this product, the paint dictionary is known, so pure NMF is usually not the best framing.

However, constrained NMF becomes useful if:

- part of the dictionary is known, but not all
- you want to learn a small number of “virtual paint” residual basis colors
- you want to estimate hidden basis behavior from data

### Recommendation
- not the mainline method for the core feature
- useful only in a hybrid or research mode

---

## 6.6 Bayesian / probabilistic inference

One can treat paint mixtures as latent variables and impose priors favoring:

- sparse recipes
- common artist mixtures
- specific paint families
- white-heavy tinting behavior

### Strengths
- flexible
- can encode prior knowledge
- can produce uncertainty estimates

### Weaknesses
- more complex
- harder to make fast and deterministic

### Recommendation
- attractive long-term research direction, not a first implementation

---

## 7. Region-based versus per-pixel decomposition

For a painting-assistance product, region-based decomposition is usually superior.

### Why per-pixel is weak

Per-pixel fitting:
- is expensive
- tends to create unstable, noisy recipe maps
- can vary too much across neighboring pixels
- is less useful to a painter

### Why region-based is better

Region-based fitting:
- encourages coherent paint areas
- reduces noise
- is more aligned with the act of painting planes and masses
- enables recipe labels a human can use

### Recommended structure

1. segment image into superpixels or coarse regions
2. compute region representatives
   - average spectrum
   - average Lab
   - median robust color
3. fit paint mixtures per region
4. optionally smooth neighboring regions toward shared active paints
5. merge regions when their recipes are similar

### Candidate segmentation methods

- SLIC superpixels
- graph-based segmentation
- watershed on edge/value maps
- your own shape/value-plane extraction system

Given your broader use case, the strongest version is likely:
- segment first by **major tonal / structural planes**
- then solve paint mixtures per plane

---

## 8. Recommended optimization pipeline

## 8.1 Prototype pipeline

### Stage 0: user chooses paint set
Examples:
- “Limited portrait palette”
- “My 12 paints”
- “Winsor & Newton set”
- “Golden heavy body starter set”

### Stage 1: image preprocessing
- downsample moderately
- optionally white-balance / normalize
- optionally denoise slightly
- convert to model-native representation
  - ideally spectral-compatible target representation, otherwise Lab/XYZ proxy

### Stage 2: structural simplification
- segment into regions
- compute region area
- compute optional saliency / edge weight
- compute mean / robust representative color per region

### Stage 3: candidate-paint pruning
Before expensive optimization, reduce the dictionary:
- discard paints clearly too far from the region hue/value neighborhood
- keep neutral paints like white and black always eligible
- optionally keep a small overcomplete candidate subset

This dramatically improves speed.

### Stage 4: local sparse fitting
For each region:
- initialize with white or nearest single paint
- use greedy sparse active-set search or sparse NNLS-style optimization
- fit 1-paint, 2-paint, 3-paint, ... solutions
- choose the smallest recipe within an error tolerance

This is a very product-friendly rule:
- “Prefer the simplest recipe that is good enough.”

### Stage 5: global palette consolidation
Across all regions:
- identify paints used weakly and infrequently
- try replacing them with neighboring paints
- re-optimize
- minimize total paints used globally subject to acceptable error increase

### Stage 6: spatial cleanup
- enforce local smoothness
- merge adjacent regions with similar mixtures
- remove tiny isolated recipe islands

### Stage 7: output generation
Produce:
- global paint list
- recipe per region
- complexity/error controls
- optional alternate modes:
  - maximum realism
  - limited palette
  - beginner-friendly
  - painterly masses

---

## 9. Practical objective functions

## 9.1 Local objective

For region \(r\):

\[
\min_{h^{(r)} \ge 0}
\; \underbrace{\mathcal{L}(f(h^{(r)}), x^{(r)})}_{\text{color mismatch}}
+ \lambda_1 \|h^{(r)}\|_1
+ \lambda_2 \, \mathrm{TV/local\ smoothness}
\]

If hard sparsity is preferred:

\[
\min_{h^{(r)} \ge 0}
\; \mathcal{L}(f(h^{(r)}), x^{(r)})
\quad \text{s.t.} \quad \|h^{(r)}\|_0 \le K
\]

where \(K\) might be 2 or 3.

## 9.2 Global objective

For all regions together:

\[
\min_{H \ge 0}
\sum_r \mathcal{L}(f(h^{(r)}), x^{(r)})
+ \lambda_{\text{local}} \sum_r \|h^{(r)}\|_1
+ \lambda_{\text{global}} \sum_i \phi(H_i)
+ \lambda_{\text{spatial}} \Psi(H)
\]

where:
- \(H_i\) is paint \(i\)'s usage across all regions
- \(\phi\) penalizes too many paints globally
- \(\Psi\) enforces spatial coherence

---

## 10. How to balance sparsity with accuracy

This is not just a mathematical tuning issue. It is a product choice.

### Useful modes

#### Mode A: “Closest match”
- prioritize color fidelity
- allow more paints per region
- likely better for advanced painters

#### Mode B: “Limited palette”
- strong global sparsity
- moderate local sparsity
- excellent for teaching and practical painting

#### Mode C: “Simple recipes”
- hard cap of 2–3 paints per region
- tolerate higher error
- best for usability

#### Mode D: “Beginner portrait / landscape”
- domain-specific priors
- favor standard artist mixing patterns

### Best selection rule

Instead of one fixed penalty coefficient, fit several solutions on the Pareto frontier:
- 1-paint
- 2-paint
- 3-paint
- 4-paint

Then select the smallest mixture whose error is below a threshold.

This produces outputs that are much easier to explain.

---

## 11. Role of white, black, and earth colors

In a painting workflow, white and certain neutrals matter disproportionately.

### White
- should almost always be available
- often dominates tints
- can reduce the need for many chromatic paints

### Black
- use with caution depending on the intended pedagogy
- some painters prefer chromatic darkening rather than black

### Earths
- Burnt Sienna, Raw Umber, Yellow Ochre, etc. may improve practical recipes dramatically
- even if high-chroma synthetics fit numerically better, earths may produce more natural and painter-friendly recipes

This suggests optional **paint priors**:
- favor common teaching palettes
- penalize obscure paints unless clearly useful
- optionally weight by artist preference

---

## 12. What “discrete paint mixes” should mean in the UI

There are several possible interpretations.

### 12.1 Continuous proportions
Example:
- Titanium White 0.62
- Ultramarine Blue 0.23
- Burnt Sienna 0.15

This is the easiest computationally.

### 12.2 Quantized recipe steps
Example:
- 4 parts white
- 1.5 parts ultramarine
- 1 part burnt sienna

This is more practical for people painting.

### 12.3 Named recipe suggestions
Example:
- “cool gray-blue built from white + ultramarine + burnt sienna”

This is best for instruction.

### Recommendation
Internally use continuous coefficients, then quantize for presentation.

---

## 13. Architecture recommendation

## 13.1 Best first implementation

### Forward model
- Kubelka–Munk-based spectral model

### Data
- start with an acrylic dataset that already includes spectral data / K/S values
- later extend to user-defined paint libraries and oil datasets

### Spatial unit
- region-level, not per-pixel

### Local optimization
- greedy nonnegative active-set search with re-optimization
- maximum 3 paints per region by default

### Global optimization
- post-pass to reduce total paints used across the image

### User controls
- maximum paints globally
- maximum paints per region
- fidelity vs simplicity slider
- optional include/exclude white/black
- optional preferred paint line

This is realistic and product-relevant.

## 13.2 Stronger second-generation implementation

- hierarchical group sparsity
- learned priors from actual artist mixtures
- domain presets for portraits, landscapes, still life
- better handling of glazing / transparency
- optional brushstroke-aware region merging
- uncertainty display where recipes are unstable

---

## 14. Evaluation plan

You need both **numerical** and **workflow** evaluation.

## 14.1 Numerical metrics
- ΔE00 mean / median / 95th percentile
- spectral residual if spectral truth is used
- number of paints used globally
- mean paints per region
- fraction of regions under target error threshold

## 14.2 Practical usability metrics
- can a painter plausibly mix these recipes?
- are recipes stable across neighboring regions?
- do recipes align with intuitive painting choices?
- does the system overuse exotic paints?
- does it generate too many near-duplicate mixtures?

## 14.3 Human studies
For the actual product, the best test is:
- give painters a reference and generated recipes
- compare against their own chosen limited palettes and mixes
- evaluate usefulness, not just numerical fidelity

---

## 15. Risks and failure modes

### 15.1 Data mismatch
Manufacturer swatches, measured drawdowns, and actual on-canvas behavior can differ.

### 15.2 Medium mismatch
Acrylic KM data may not transfer well to oils.

### 15.3 Support mismatch
Measured data may assume opaque drawdowns over white, while the user paints thinly or on toned grounds.

### 15.4 Metamerism
Different spectra can map to similar RGB/Lab values. Limited image data may not uniquely determine pigment mixtures.

### 15.5 Overfitting with too many paints
Without sufficient sparsity, the system will find mathematically good but practically absurd mixtures.

### 15.6 Underfitting with too much sparsity
If constraints are too strong, colors collapse into dull or incorrect recipes.

### 15.7 Non-uniqueness
Multiple recipes may produce similar perceptual matches. The product should recognize that “the” solution may not be unique.

---

## 16. Recommended development roadmap

## Phase 1: proof of concept
- use an existing acrylic spectral dataset
- implement region segmentation
- fit sparse recipes with 2–3 paints max
- evaluate on selected images

## Phase 2: product-quality solver
- add global palette consolidation
- improve heuristics for candidate-paint pruning
- add fidelity/simplicity controls
- refine region merging and stability

## Phase 3: richer paint semantics
- user-defined paint libraries
- preferred paint lines
- portrait / landscape presets
- recipe quantization into “parts”

## Phase 4: advanced paint realism
- richer KM calibration
- better treatment of translucency / glazing
- more robust oil-specific data

---

## 17. Final recommendation

For this feature, the best core formulation is:

> **Region-based sparse nonnegative inversion of a fixed paint dictionary under a Kubelka–Munk-style forward paint-mixing model, with both local and global sparsity controls.**

In practical product terms, that means:

- do **not** start from vanilla NMF
- do **not** treat this as ordinary color clustering
- do use a **known paint set**
- do use a **physically inspired forward model**
- do solve for **sparse mixtures**
- do prefer **region-level** recipes
- do add a **global limited-palette** regularizer

If implementation complexity must be staged, the best sequence is:

1. region-based sparse fitting with a fixed paint set
2. global palette reduction
3. stronger physical realism
4. richer artistic priors

That gives a path from prototype to a genuinely useful painter-facing tool.

---

## 18. Concrete recommended v1 algorithm stack

If this were being built now, the most sensible v1 would be:

### Data
- measured spectral or K/S data for a fixed paint line

### Forward model
- opaque Kubelka–Munk spectral mixing

### Image representation
- region segmentation into paintable masses / superpixels

### Solver
- greedy nonnegative active-set search
- re-optimization of coefficients after each selected paint
- stop at 3 paints by default
- select simplest recipe under an error threshold

### Global pass
- reduce the total number of paints used across the image
- re-fit regions under the reduced global palette

### Output
- limited palette recommendation
- region paint map
- quantized “parts” recipes
- error overlay

This is the strongest balance of realism, sparsity, interpretability, and implementation feasibility.

---

## Sources consulted

1. Golden Paint Spectra, realtimerendering.com  
   Notes: states that Golden shared spectral data for 78 acrylic paints, including Lab, reflectance samples from 400–700 nm, and Kubelka–Munk K/S values.

2. Roy S. Berns, *Artist Acrylic Paint Spectral, Colorimetric, and Image Dataset* (Archiving Conference, 2022)  
   Notes: describes spectral data for 58 Golden Heavy Body Acrylics and computed spectra for 831 tints, tones, and masstones using the two-constant opaque Kubelka–Munk model.

3. Roy S. Berns, *Artist Paint Spectral Database*  
   Notes: describes a database developed from 19 Golden Heavy Body acrylic paints, with spectra, colorimetry, eigenvectors, and Kubelka–Munk-related optical data.

4. Daniel W. Dichter, *Kubelka-Munk model of full-gamut oil colour mixing* (Journal of the International Colour Association, 2023)  
   Notes: reports an average error of 1.49 ΔE00 across 33 mixes for a limited palette of Winsor & Newton oils in an opaque / alla prima setting.

5. Jianchao Tan, Stephen DiVerdi, Jingwan Lu, Yotam Gingold, *Pigmento: Pigment-Based Image Analysis and Editing*  
   Notes: an important graphics reference for pigment-based decomposition and editing using a physically inspired mixing model.

6. Sochorová and Jamriška et al., *Practical Pigment Mixing for Digital Painting*  
   Notes: relevant as a practical engineering reference for RGB-friendly pigment mixing approximations.

