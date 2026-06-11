# Making Underpaint a More Compelling Commercial Offering

**Date:** 2026-06-11
**Status:** Proposed
**Scope:** Improve existing functionality to strengthen conversion, retention, and revenue. No repositioning, no new study modes.

## Where the offering stands

The product mechanics are sound and honest: the free tier runs every feature — modes, recipes, depth, prep sheets — on bundled samples; a single $9.99 non-consumable unlocks the user's own photos. The differentiators are real (Kubelka–Munk recipes, Spatial depth, composed Prep Sheet, full on-device privacy), and the Clarity/Kit/Native plan fixed the vocabulary, the paywall narrative, and the export artifact.

But three commercially load-bearing pieces of that plan never landed, and the revenue model itself has a ceiling. This proposal diagnoses the gaps and lays out three approaches, with a recommended sequencing.

## Diagnosis — what limits the commercial offering today

**1. The sales floor is understocked.** Conversion is the product of three surfaces: the sample library, the paywall, and the App Store page. Today the sample library has 4 images (workstream 3.3 called for 10–12 in categories; not built), the paywall's three content rows use SF Symbols where the plan called for screenshot-grade imagery ("we need captures" — still true), and no App Store screenshots/preview video exist in the repo. The free experience *is* the demo, and it is thin. A painter who isn't sold by the third sample has nowhere else to be sold.

**2. The strongest differentiator speaks one dialect.** Recipes are Golden Heavy Body Acrylics only. Persona A (oil painter) and Persona C (watercolorist) — arguably the two most recipe-motivated personas — get mixtures for a medium they don't use. For them the flagship feature reads as a clever demo, not "my palette." This is simultaneously the biggest conversion leak and the most natural expansion-revenue axis.

**3. No reason to return → no ratings flywheel.** Session history (workstream 3.1) was never built; the app forgets everything between launches except the last settings snapshot. With no analytics and no ad budget, App Store ratings and word of mouth are the *entire* growth channel — and both are functions of repeat use. A stateless app gets used once per painting; a remembering app becomes part of the studio ritual.

**4. One SKU, no price architecture.** $9.99 once, Family Sharing included, is the whole revenue model. There is no anchor making $9.99 look reasonable, no expansion path for the happiest customers, and no mechanism to capture more value from a professional than from a curious student. Lifetime revenue per customer is capped at the first impression.

**5. The artifact isn't doing marketing work.** The Prep Sheet already carries a "Made with Underpaint" footer — good — but sheets exported from samples (the only thing free users can export) are indistinguishable from paid output, and the footer is plain text with no path back to the app. Every sheet shared in a class, workshop, or critique group is a referral opportunity carrying no link.

## Three approaches

### Approach A — Funnel-first: sell the existing app better

Finish the conversion surfaces. No pricing changes, no new processing code.

- **A.1 Expanded sample library (workstream 3.3, revived).** 10–12 curated references in categories (Portraits / Landscapes / Still life / Spatial), each dropping into its most flattering mode — the existing "samples are the tutorial" mechanism scales with zero new code. Licensing: own photographs or CC-BY with attribution in About.
- **A.2 Paywall captures.** Replace the three SF Symbol rows with real mini-renders: a value study, a recipe card with pigment names, a depth-isolated portrait. These can be generated from the sample images at build time — the app *is* the screenshot factory.
- **A.3 App Store asset pass.** Screenshots and a 30-second preview following the existing script in `docs/marketing.md`. The listing copy is already strong; it has no imagery behind it.
- **A.4 Prep Sheet as referral.** On sample-sourced (free-tier) exports, the footer gains one line: "Underpaint on the App Store — try it on your own reference" (link target: the App Store page; the existing GitHub Pages site can redirect until a custom domain exists). Unlocked exports keep the current discreet footer. One conditional in `PrepSheetLayoutView`.
- **A.5 Ratings prompt.** `SKStoreReviewController` request after the second prep-sheet export or fifth image load — the moments the user has just received value. Respect the existing no-tracking promise: a local counter, nothing recorded beyond it.

**Effort: ~5–7 days** (most of it sample curation and capture work, not code).
**Risk:** low. **Revenue effect:** multiplies conversion on existing traffic.

### Approach B — Depth-first: make the $9.99 unmistakably worth it

Turn the app from a per-painting utility into studio equipment. This is retention work, and retention is what generates the ratings Approach A's funnel needs.

- **B.1 Session history (workstream 3.1, revived).** Last 10 references with full state restore, "Recent" section beside Samples, 500MB cap, evict-oldest, clear-history in Privacy. Already designed in the 2026-04-17 plan; the design holds.
- **B.2 Prep Sheet options.** Page size (Letter/A4 — plumbing exists), panel selection (e.g., omit Color for a watercolor value-study workflow), and an optional notes line ("for Tuesday's class"). Makes the flagship artifact fit more workflows without changing its layout system.
- **B.3 Pigment shopping list.** A "Pigments used" summary across all recipe cards — copyable text, one tap. Persona Pattern 3 (palette planning) currently requires manually transcribing tube names from recipe cards. Trivial code; outsized perceived value; deepens the recipe moat.
- **B.4 Mac as a first-class purchase reason.** Universal purchase already works via Catalyst; say so. "One purchase: iPhone, iPad, and Mac" on the paywall and listing. Painters prop iPads at easels but plan at desks.

**Effort: ~6–8 days.**
**Risk:** low-moderate (session storage was already de-risked in the prior design). **Revenue effect:** justifies the ask, drives ratings, reduces refunds.

### Approach C — Expansion revenue: monetize the recipe engine

Keep the $9.99 base unlock exactly as promised, and add optional **paint line packs** as non-consumable IAPs (~$3.99–4.99): *Watercolor* (e.g., a 24-color professional line) and *Oils* first, because those are the personas currently locked out of the recipe feature entirely. The pipeline — `SpectralDataStore`, `KubelkaMunkMixer`, `PigmentDecomposer` — is brand-agnostic; a pack is data plus a picker entry.

- Messaging must protect the existing promise: *the app* is one purchase, yours forever; packs are optional paint libraries, like buying more tubes.
- An "Everything" bundle anchors the base price and lifts ARPU from the happiest customers.
- **The gate is data, not code.** The repo's own paint-mix report documents how hard sourced spectral data is. C must start with a 2–3 day sourcing spike (candidate lines, measurement vs. published data, licensing) before any commitment. Watercolor K–M behavior (thin washes vs. masstone) also needs a modeling sanity check.

**Effort: spike 2–3d; per-pack 5–10d once data exists.**
**Risk:** moderate-high (data sourcing, watercolor model validity, messaging). **Revenue effect:** the only approach that raises the per-customer ceiling.

## Recommendation

**Sequence A → B → C-spike.** A and B are launch-critical and low-risk; they finish what the previous plan already validated. C is the long-term revenue story but is gated on a data-sourcing question that a short spike can answer cheaply — run the spike during A/B development so the decision is ready when 1.1 planning starts.

**Pricing: hold $9.99 at launch.** Early ratings velocity matters more than margin; revisit toward $12.99–14.99 only after the review base exists and B has landed (the price rise then has a story: sessions + prep sheet + Mac). If C ships, the bundle becomes the premium tier instead of a base-price increase.

| Phase | Contents | Effort | When |
|-------|----------|--------|------|
| 1 | A.1–A.5 funnel | 5–7d | pre-launch |
| 2 | B.1–B.4 depth | 6–8d | pre-launch if schedule allows; else 1.1 |
| 3 | C spike (data sourcing + watercolor K–M check) | 2–3d | parallel with 1–2 |
| 4 | First paint pack + bundle | 5–10d | 1.2, only if spike passes |

## Out of scope

- Subscriptions — wrong fit for a tool with no recurring costs, and corrosive to the privacy/ownership positioning.
- Cloud sync, accounts, telemetry — break the "nothing leaves your phone" promise that is itself a selling point.
- New study modes (line art, Notan, edges) — scope creep; the existing four modes are not the constraint on revenue.
- Repositioning toward drawing/Pencil tools.

## Open questions

1. **Sample photography** — do we shoot our own 10–12 references, or curate CC-BY? Own photos avoid attribution clutter and licensing review; needs a camera day.
2. **Free-tier export footer** — is the referral line acceptable on sample exports, or does any "watermark-like" element feel off-brand? (It is removable by purchasing, which is the point — but tone matters.)
3. **Which paint line first** — watercolor reaches the most underserved persona; oils may have better published spectral data. The C spike should answer this empirically.
4. **AGPL and paid packs** — pack *code* is AGPL like everything else; pack *spectral data* can be licensed separately as data. Confirm we're comfortable that the moat is data + curation + distribution, not code secrecy.
