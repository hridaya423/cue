# Cue design system

## Status and authority

This is the target design system for the approved onboarding redesign, authored on 2026-09-22. It is not a description of the current shipped UI. The approved image references establish composition, softness, typography hierarchy and the fold-out relationship. Numeric values below are implementation decisions calibrated to those images, not measured Figma tokens. Dark-mode values are proposed counterparts and require rendered verification.

Read [the onboarding spec](docs/design/onboarding/SPEC.md) before changing onboarding behavior, content or layout. Read [the implementation plan](docs/plans/2026-09-22-onboarding-redesign.md) when implementing. The spec owns screen-specific geometry and states; this file owns shared visual rules. Current application APIs remain authoritative for capabilities and operational status.

Apply this language to new or revised Cue surfaces. Do not restyle unrelated existing windows as part of onboarding. Preserve native menu behavior and make frequent paste interactions immediate.

## Intent

Cue helps someone paste the relevant detail from one copied block of text into the focused field. The onboarding demonstrates that behavior with one paragraph containing an email, phone and URL. The original paragraph stays intact while a highlighted substring appears in a destination field. This visual model does not prescribe a rewrite of the application's existing clipboard storage or decision engine.

The visual signature is a pair of surfaces that seem to unfold from one another. The upper sheet presents source information or a choice; the lower sheet reveals its consequence, setup action or preview. A coral highlight identifies text or an instructional target. Blue identifies controls and selection. Paper is suggested through geometry and shadow, not a photograph or large decorative sculpture.

## Color tokens

Use one SwiftUI token namespace with explicit light/dark values. Suggested implementation location: `Sources/CueKit/Views/OnboardingStyle.swift`. Once implemented, code becomes the source of truth for mechanical values; keep this document's roles synchronized. Hex values use sRGB.

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| canvas | #F7F8FA | #202226 | Main content background |
| sheet | #FFFFFF | #2B2E33 | Upper elevated surface |
| unfoldedSheet | #FCFCFD | #26292E | Lower receiving surface |
| textPrimary | #17191D | #F4F5F7 | Titles, body and values |
| textSecondary | #626873 | #B3B8C2 | Explanations and field labels |
| textTertiary | #646B76 | #A1A8B3 | Necessary metadata; never simply lower opacity |
| separator | #DFE2E7 | #454A53 | Structural divisions |
| inputFill | #FFFFFF | #22252A | Editable field interior |
| inputStroke | #B9C0CB | #747D8B | Field boundary |
| action | #0067E6 | #0067E6 | Default blue primary button; white label |
| selectionFill | #EDF4FF | #25374F | Selected model row background |
| selectionStroke | #BED5FA | #4E719D | Selected model row edge |
| highlight | #FFD0C8 | #EBA395 | Selected sample substring |
| highlightText | #242124 | #242124 | Text on coral highlight |
| foldEdge | #F28F7E | #C77869 | Thin lip of fold; decorative only |

Prefer native semantic error/success colors with a symbol and text. Use the platform focus ring for editable controls. Blue selection does not replace a radio indicator. Coral is not an error color. Avoid white text on coral; it is a highlight surface, not the primary action fill.

Do not claim contrast compliance from this table alone. Verify rendered text/background pairs in both modes: 4.5:1 normal text, 3:1 large text, 3:1 essential control boundaries/focus indicators. Native controls can vary with OS version and user accent settings. Keep native keyboard behavior even when using custom blue button styling.

## Typography

Use SF Pro through `.system`, without bundling fonts. Use SF Mono only for editable endpoint/model identifiers when it aids reading. The message paragraph uses proportional body text; it must look like an ordinary message.

| Role | Size in points | Weight | Target line box |
| --- | --- | --- | --- |
| Cue wordmark | 20 | Semibold | 25 |
| Screen title | 28 | Semibold | 34 |
| Screen support | 16 | Regular | 22 |
| Sample paragraph | 17 | Regular | 25 |
| Section title | 16 | Semibold | 21 |
| Row title / value | 15 | Medium / regular | 21 |
| Field label / row detail | 13 | Medium / regular | 18 |
| Helper / status | 12 | Regular | 17 |
| Primary button | 15 | Semibold | 20 |

Use sentence case. Keep the title on one line at the canonical window size when possible, two at larger accessibility text sizes. Never shrink necessary body text below 12 points to fit. Native controls may use their platform font metrics; adjust surrounding spacing rather than forcing pixel-perfect glyph rasterization.

## Layout

All dimensions are logical macOS points. Canonical content view: 760 × 580. Use a 600-point central panel column, 80-point side margins and an anchored footer. Grow vertically or scroll only the central content at large text sizes; preserve header, Back and primary action. The spec gives coordinates per screen.

Spacing scale: 4, 8, 12, 16, 24, 32, 40. Use 8 within label/value groups, 16 between related controls, 24 between sections, 32 between header and central content. Align visible text edges across upper/lower panels. Lower panels inset 16 points per side relative to the upper sheet.

Treat whitespace as part of the composition. Do not fill the central surface with unused meters, badges, decoration or repeating descriptions. A short state may retain the same panel bounds as its longer sibling to avoid jumping controls.

## Shapes and depth

| Element | Radius |
| --- | --- |
| Upper/lower sheet | 16, continuous |
| Field / button / selected row | 8, continuous where custom |
| Inline highlight | 4 |
| Small icon tile | 10 |

Use real AppKit window chrome and window shadow. Never draw fake traffic-light controls. Standard window corner geometry belongs to macOS; matching the generated outline precisely is not required.

Upper sheet light shadow: black at 0.06 opacity, radius 2, y 1; second shadow black at 0.09, radius 10, y 6. Lower sheet: black at 0.06, radius 8, y 4. Dark sheets use a white 0.08-opacity 0.5-point edge and black 0.18 shadow, radius 8, y 4. Inspect stacking so shadows do not become a thick gray seam.

Upper sheet overlaps the lower sheet by 12 points. Lower content begins 28 points below its top, leaving 16 visible points after overlap. Render lower sheet first, then upper. Reserve a 24 × 20-point fold lip near the horizontal center or aligned with the highlighted span. Use a small curved filled Shape with a coral edge and subtle neutral shading. The lip must not obscure text or imitate an arrow.

Only the demo extraction needs a moving highlight. Plain setup screens can use the structural fold without animation or coral decoration. Do not bend text or an entire form to imitate perspective in the generated reference.

## Components and semantics

- Shell: shared wordmark, heading, support, content area and footer. It owns spacing and navigation, not network requests.
- Fold-out surface: two content slots with shared geometry. It owns shape and elevation, not screen state. A full generic card library is unnecessary.
- Primary action: one filled button per screen, minimum 140 × 38, maximum 240 unless localized text needs more. Disabled/pending states preserve width and readable label.
- Back: native plain button with `chevron.left`, 64 × 38 hit region, bottom-left. Visible except on Welcome. Its position does not move between screens.
- Inputs: native TextField/SecureField or narrow NSTextField bridge where AX labeling/focus requires it; 36-point minimum visual height, labels above or alongside as specified.
- Model choice: native radio semantics and full-row hit target, minimum 60-point row. Details and variants live below the list; avoid nested interactive controls inside a row button.
- Segmented control: native picker, minimum 32-point height. It changes a view within a screen, not the onboarding route.
- Instruction preview: noninteractive illustration, accessibility-hidden if surrounding text explains it. A pictured OS toggle cannot be clicked to grant permission.
- Error: inline message with recovery action in the same panel. Preserve user input and selected model.

Use SF Symbols for utility glyphs. Model thumbnails are uniform neutral monogram tiles using the model title's initial, not invented colored logos. The app identity should reuse the real app icon when available, otherwise use the existing paperclip symbol in a neutral tile. No new branding asset is needed.

## Motion

The source paragraph remains intact. A duplicate highlight layer can lift 3 points, move to the receiving field, then fade as the native field value appears. This is an illustrative welcome demo only. Real paste success is driven by actual results.

Welcome demonstration: 420 ms maximum per deliberate field switch; ease out with control points (0.23, 1, 0.32, 1). Sheet entrance: 180 ms opacity plus 6-point vertical translation. Route change: 180 ms crossfade, no whole-window slide. Button press: 0.98 scale, 100 ms, if custom styling does not interfere with native press state. Success label: 150 ms opacity. Do not animate ordinary keyboard paste delivery.

Cancel/retarget demo animation when selection changes. Stop animations when the window is hidden or the screen exits. Reduced Motion: remove translations, rotations and peeling; use an immediate selected highlight and field update, optionally a 100 ms opacity transition. Increased Contrast: strengthen input edges and selection marks. Reduced Transparency: use solid surface colors. Nothing essential relies on motion.

## Fidelity and scope

The approved images are in `docs/design/onboarding/references`. They are reference artifacts only. Do not ship them as screen-sized images or flatten controls/text into a raster. The native implementation must remain localizable, selectable where appropriate, keyboard-accessible and theme-aware.

Preserve the fold-out relationship, quiet elevation, balanced column, readable sample, coral highlight and blue action. Correct generated errors: fictional model claims/icons, mistaken hotkey glyphs, underspecified setup states, optional text that implies a real field is decorative, and inconsistent footer placement.

Dark mode is required with the same hierarchy. The reference set only establishes light-mode art direction. Verify dark mode as a derived implementation, without calling it user-approved imagery.
