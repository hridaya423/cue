# Documentation validation

Validation performed on 2026-09-22. This checks the handoff package, not the unimplemented app.

- All local Markdown links resolve.
- Markdown code fences are balanced.
- All six reference image checksums match manifest.json.
- No application source or settings were changed.
- Native UI runtime, model setup, paste behavior and dark-mode rendering remain unverified.

## Proposed token contrast

Calculated using sRGB relative luminance. These are opaque token pairs, not measured screenshots. Native states, opacity, focus indicators and actual compositing still require implementation-time inspection.

| Pair | Contrast |
| --- | --- |
| Primary/light | 16.56:1 |
| Secondary/light | 5.27:1 |
| Tertiary/light | 5.06:1 |
| Primary/dark | 14.60:1 |
| Secondary/dark | 8.00:1 |
| Tertiary/dark | 6.65:1 |
| Action label | 5.14:1 |
| Highlight/light | 11.46:1 |
| Highlight/dark | 7.74:1 |

## Format boundary

DESIGN.md is a native SwiftUI implementation guide with Markdown tables. It is not a web design-token interchange document, and no web exporter/linter was used. Checks here cover local document integrity, source grounding, reference integrity and explicit separation of proposed values from observed implementation.
