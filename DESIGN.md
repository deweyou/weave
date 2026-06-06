---
name: weave-design
description: Durable interface rules for Weave's local-first desktop app.
version: 1
tokens:
  color:
    canvas: "#f5f2ed"
    surface: "#fffdf9"
    text: "#1e2528"
    primary: "#8b5e34"
  typography:
    control: "system-ui"
    content: "system-ui"
  spacing:
    rhythm: "8px"
---

# Weave Design

Weave should feel like a quiet local workspace for writing, memos, and todos:
focused, readable, and restrained.

## Design Thesis

Prioritize fast capture, clear resurfacing, and calm review. Avoid marketing-page
composition inside the app.

## Principles

- Keep the first screen usable as the product, not a landing page.
- Prefer dense but breathable workspace layouts over decorative sections.
- Make local-first status and workspace context visible without making them the
  primary content.

## Typography

Use the system UI stack until the writing surface has stronger content needs.
Avoid viewport-scaled typography.

## Color

Use warm neutral canvas and paper-like surfaces sparingly. Keep accent color for
metadata and active state, not broad background fills.

## Layout

Use stable grids and explicit responsive constraints. Cards may represent actual
items, but page sections should not become nested card stacks.

## Components

Keep reusable UI local to `apps/desktop` until reuse is proven. Extract component
packages only when a second consumer exists.

## Interaction

Favor direct actions and predictable navigation. Desktop behavior should not
assume mobile patterns until the mobile app exists.

## Accessibility

Maintain semantic landmarks, labels for grouped content, and readable contrast.

## Do

- Keep controls compact and obvious.
- Use durable class names that express product meaning.
- Preserve keyboard and screen-reader friendly structure.

## Don't

- Do not add decorative gradients, orbs, or card-heavy marketing layouts.
- Do not create shared UI abstractions before repeated use.
- Do not design iOS-specific behavior before the stack is selected.

---
*Last updated: 2026-06-06 | Reason: initial design memory for desktop-first rewrite*
