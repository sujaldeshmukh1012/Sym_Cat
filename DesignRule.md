SYSTEM DESIGN SPECIFICATION
PROJECT: Industrial High-Intensity Dashboard (Mobile + Desktop)
CONTEXT: Used by managers and field employees in heavy industrial environments.
THEME: Light. Professional. Operationally fail-proof.

---

DEFINE GLOBAL DESIGN PRINCIPLES

* Prioritize clarity over aesthetics.
* Eliminate ambiguity in all controls.
* Minimize cognitive load.
* Optimize for fast decision-making under stress.
* Ensure identical structural logic across mobile and desktop.
* Never rely solely on color to communicate meaning.
* Assume intermittent connectivity.

---

DEFINE GRID SYSTEM

SPACING:

* Use 8px base unit system.
* All margins and padding must be multiples of 8px.

DESKTOP:

* 12-column grid.
* Max content width: 1440px.
* Sidebar width: 240px fixed.
* Top navigation bar fixed height: 64px.

MOBILE:

* 4-column grid.
* Top bar fixed height: 56px.
* Bottom navigation required (max 5 items).
* No hamburger menu for critical functions.

---

DEFINE LAYOUT STRUCTURE

DESKTOP LAYOUT:

Top Bar (fixed)
Left Sidebar (persistent)
Main Content Area (card-based modular layout)

MOBILE LAYOUT:

Top Bar (fixed)
Primary KPI Section
Operational Cards
Bottom Navigation (persistent)

RULE:
Structure hierarchy must remain identical across breakpoints.
Desktop expands horizontally.
Mobile stacks vertically.
Module order must not change.

---

DEFINE TYPOGRAPHY

Font family: Neutral sans-serif (Inter/SF/Roboto class).
Maximum 3 font weights.

Heading Large (H1): 24–28px
Section Heading: 18px
Body Text: 14–16px
Minimum body size: 14px.

No decorative fonts.
No excessive uppercase.
No more than 3 hierarchy levels per screen.

---

DEFINE COLOR SYSTEM (LIGHT THEME)

Background: #F7F9FB
Card: #FFFFFF
Border: #E5EAF0
Primary Action: Industrial yellow (muted)
Success: Muted green
Warning: Amber
Critical: Red

RULES:

* Status = icon + text label + color.
* Never use color alone to communicate state.
* No gradients.
* No decorative shadows beyond subtle elevation.

---

DEFINE COMPONENT RULES

BUTTONS:

* Minimum height: 48px.
* Border radius: 8px.
* One primary button per screen maximum.
* Secondary = outline.
* Tertiary = text only.

INTERACTION FEEDBACK:

* Press state visible.
* Animation duration < 200ms.
* No decorative motion.

CARDS:
Each card must include:

* Clear title
* Main data value
* Status indicator
* Timestamp (if data-driven)

No empty decorative cards.

---

DEFINE DATA DISPLAY RULES

KPIs:

* Large numeric value.
* Trend indicator (arrow + %).
* Last updated timestamp.

TABLES (DESKTOP):

* Sticky header.
* Row height ≥ 44px.
* Zebra striping.
* Inline status badges.
* Bulk actions only visible when rows selected.

TABLES (MOBILE):

* No horizontal scrolling.
* Convert rows to expandable cards.
* Show top 3 critical fields by default.

No dense raw data walls.

---

DEFINE ERROR HANDLING

All error states must include:

* Clear title.
* Human-readable explanation.
* Primary recovery action.
* Secondary fallback action.

Never display raw system errors.
Never leave user without next step.

---

DEFINE DESTRUCTIVE ACTION PROTOCOL

For delete/critical changes:

* Confirmation modal required.
* Explicit description of impact.
* Optional undo window.

For high-risk operational commands:

* Double confirmation.
* Mobile: Slide to confirm.
* Desktop: Hold to confirm (minimum 1 second).

---

DEFINE ALERT SYSTEM

Severity Levels:

1. Critical – Red – Non-dismissible until action taken.
2. Warning – Amber – Dismissible.
3. Info – Neutral.

Critical alerts must:

* Appear as sticky banner.
* Be visually dominant.
* Provide immediate action button.

---

DEFINE OFFLINE BEHAVIOR

System must detect connectivity state.

Display banner when offline.

All actions must show status:

* Synced
* Pending
* Failed

Queue offline actions locally.
Retry automatically when connection restored.

Never silently drop user actions.

---

DEFINE ACCESSIBILITY

Minimum contrast ratio: 4.5:1.
Full keyboard navigation on desktop.
Touch targets ≥ 48px.
Minimum spacing between interactive elements: 12px.
No color-only communication.

---

DEFINE PERFORMANCE CONSTRAINTS

First meaningful paint < 2 seconds.
Avoid blocking loaders.
Prefer skeleton states over spinners.
Must run on mid-tier industrial mobile devices.

---

DEFINE DASHBOARD STRUCTURE TEMPLATE

Every dashboard must contain:

1. KPI Summary Strip (top)
2. Active Alerts Section
3. Operational Overview (cards/charts)
4. Task / Action Queue
5. Historical Insights Section

Order must remain consistent across devices.

---

DEFINE PROHIBITED PATTERNS

* Hidden navigation for critical actions.
* Infinite scroll dashboards.
* Icon-only primary actions.
* Modal stacking.
* Decorative animations.
* Contextless minimalism.

---

DEFINE RELEASE VALIDATION CHECKLIST

* Core task completion ≤ 3 steps.
* All destructive actions protected.
* Every alert actionable.
* Mobile preserves hierarchy.
* System fails safely.
* No ambiguous controls.
* No visual clutter.

END SPECIFICATION.
