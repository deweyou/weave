---
name: weave-design
description: Simple, operable, clean interface rules for Weave's local-first desktop app.
version: 1
tokens:
  color:
    canvas: "#f6f7f6"
    surface: "#ffffff"
    text: "#1e2528"
    muted: "#66706d"
    border: "#d7dbd8"
    primary: "#8b5e34"
  typography:
    control: "deweyou font stack --ui-font-control"
    content: "deweyou font stack --ui-font-content"
  spacing:
    rhythm: "8px"
---

# Weave Design

Weave should feel like a quiet local workspace for writing, memos, and todos:
simple, operable, clean, focused, readable, and restrained.

## Design Thesis

Prioritize fast capture, clear resurfacing, and calm review. The interface should
make the next useful action obvious without making the product feel empty,
decorative, or over-explained.

## Design Paradigm

Weave's interface standard is **simple, operable, clean**.

- **Simple** means every screen has one obvious purpose, a short information
  hierarchy, and no decorative explanation that does not help the current task.
- **Operable** means primary actions are visible, named with direct verbs, easy
  to hit with pointer or keyboard, and supported by clear loading, disabled,
  error, and recovery states.
- **Clean** means visual structure comes from alignment, spacing, typography,
  dividers, and restrained surfaces rather than gradients, nested cards,
  oversized hero sections, or ornamental illustration.

## Principles

- Keep the first screen usable as the product, not a landing page.
- Prefer dense but breathable workspace layouts over decorative sections.
- Make local-first status and workspace context visible without making them the
  primary content.
- Every view should make the current mode and the next action understandable
  within a few seconds.
- Use fewer words first. Add explanatory copy only when it reduces uncertainty
  about local files, data ownership, recovery, or irreversible actions.

## Typography

Use Weave's local deweyou font stack variables: content and display surfaces
should use `--ui-font-content`, while buttons, inputs, and controls should use
`--ui-font-control`. Avoid viewport-scaled typography.

Use compact desktop type. Large type is reserved for true app-level entry points;
panels, settings, lists, and tool surfaces should use tighter headings.

## Color

Use neutral light canvas and clean white surfaces. Keep accent color for
metadata and active state, not broad background fills.

Prefer neutral contrast and small accent moments. Avoid single-hue themes,
generic gradients, purple-blue dominance, or color used as decoration without
state meaning.

## Brand Assets

Use theme-aware Weave assets where the app controls rendering: light surfaces use
the paper icon/mark, dark surfaces use the ink icon/mark, and system theme follows
the current macOS appearance. Keep the packaged static app icon on the general
paper version unless the packaging chain explicitly supports appearance variants.

## Layout

Use stable grids and explicit responsive constraints. Cards may represent actual
items, but page sections should not become nested card stacks.

Desktop screens should feel precise: aligned edges, predictable gutters, stable
control sizes, and no layout shift when state changes. Empty and first-run states
should look like setup or workspace states, not marketing pages.

## Components

Keep reusable UI local to `apps/desktop` until reuse is proven. Extract component
packages only when a second consumer exists.

Prefer native-feeling controls and direct labels. Buttons are for clear commands;
settings and status areas should be compact, scannable, and visually quieter than
the primary workflow.

## Interaction

Favor direct actions and predictable navigation. Desktop behavior should not
assume mobile patterns until the mobile app exists.

Primary actions should be singular where possible. Secondary actions should stay
available but visually quieter. Recovery paths should be near the problem they
resolve, especially for missing local folders or unavailable filesystem access.

## Accessibility

Maintain semantic landmarks, labels for grouped content, and readable contrast.

Preserve visible focus states, keyboard reachability, readable line lengths, and
wrapping for long local paths. Disabled controls must look disabled and keep
layout stable.

## Do

- Keep controls compact and obvious.
- Use durable class names that express product meaning.
- Preserve keyboard and screen-reader friendly structure.
- Prefer concise Chinese UI copy for app surfaces, with English only where it is
  a file name, technical path, command, or established product term.
- Show local-first context through paths, folder structure, and recovery states
  instead of abstract trust claims.

## Don't

- Do not add decorative gradients, orbs, or card-heavy marketing layouts.
- Do not use onboarding carousels, large hero compositions, or feature-tour pages
  for required setup flows.
- Do not create shared UI abstractions before repeated use.
- Do not design iOS-specific behavior before the stack is selected.

---
*Last updated: 2026-06-07 | Reason: keep CI self-contained while preserving Weave font variables*
