# Cue site (Next.js)

Next.js 16, App Router, static export (`out/`). Replaces the old static `website/`, which is deleted and purged from git history (backup bundle: `../../smartcopypaste-before-website-purge.bundle`). Not committed.

## Done (2026-10-20)
- `npm run build` writes a static site to `out/`; serve it with any static server (checked on port 4417).
- Page: intro (striped mark draws, flies into the header logo), hero, Privacy (tapes, seam, paper laptop), close with the striped mark, 404.
- How it works removed (owner's call). Pause control removed. Menu removed: the header is logo, Privacy, Download.
- Hero: copy stacked on the left (headline, one line, Download for Mac). On the right a chat window (traffic lights,
  search, channel header with members, Today divider, reaction) and a mail compose (Cc Bcc, split Send) stacked in flow,
  the mail overlapping only the chat's composer. Loop: a macOS pointer drags a per-line selection over Nadia's message,
  ⌘C chord, pointer clicks into To (the selection greys as the chat loses focus), ⌘V chord, only the address turns cobalt,
  lifts out on an arc and morphs into the recipient chip. Modifiers press before the letter. Reduced motion: chip filled.
  True to the app with ⌘V intercept on: the whole message doesn't fit an email field, so ⌘V goes to the engine; "To" is an
  email field and one email option pastes with no model call.
- `components/Mark.tsx` holds the 42 capsules once; header, laptop screen, close and footer use it.
- `components/Motion.tsx` is the old main.js minus How, menu and Pause: one GSAP ticker, Lenis. three.js and the ribbon
  are gone.

- Comments and dead CSS removed (`.sr`, `.is-away`, three unused colour tokens); boilerplate README replaced.

## Evidence
- Hero loop frames `/tmp/cueL/lp-1440-*.png`, `lp-390-*.png`; earlier `/tmp/cueN/hero-1440-*.png`, `hero-390-*.png`, `intro-*.png`, `404-*.png`, scroll frames `d-1440-*`, `m-390-*`. Console: no errors on `/`.

## Open
- The hero loop runs with no pause control (removed on request). It stops off screen and is static under reduced motion,
  but WCAG 2.2.2 asks for a pause on motion over 5 s.
