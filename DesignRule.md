SYSTEM DESIGN SPECIFICATION
PROJECT: CAT Inspect iOS App
CONTEXT: Used by Caterpillar inspection officers for fleet walkarounds, task evidence capture, and report submission.
THEME: Light by default with optional Dark Mode in Profile.

---

DEFINE GLOBAL DESIGN PRINCIPLES

* Prioritize clarity and speed for field operation.
* Keep camera capture area unobstructed during active inspection.
* Use consistent interaction patterns across Fleet, Inspections, Reports, and Profile.
* Never rely on color alone for status; always pair with text/icon.
* Persist critical user and inspection data locally for resilience.
* Support draft-first workflows when reports are not yet submitted.

---

DEFINE PLATFORM + NAVIGATION

PLATFORM:

* Primary target is iOS.
* Optimize for one-hand usage and quick task transitions.

BOTTOM TAB NAVIGATION (REQUIRED):

1. Fleet
2. Inspections
3. Reports
4. Profile

RULES:

* Tab order must remain fixed.
* Shared search is accessible from Fleet, Inspections, and Reports.
* Inspection workflow opens full-screen from Fleet/Inspections and returns to previous state when closed.

---

DEFINE LAYOUT + SPACING

* Use 8px spacing scale.
* Touch targets >= 48px for all primary actions.
* Keep camera preview dominant in workflow screens.
* Workflow controls must stay in bottom panel to keep top/middle visible for capture.

---

DEFINE TYPOGRAPHY

* Font family: SF system sans-serif.
* Max 3 effective hierarchy levels per section.

Sizes:

* Large heading: 24-28px
* Section heading: 18px
* Body: 14-16px
* Caption: 12-13px

Rules:

* No decorative type.
* Avoid all-caps blocks except short labels/badges.

---

DEFINE COLOR SYSTEM (CAT THEME)

BRAND:

* CAT Yellow: #FFCD11
* CAT Black (dark text/button): near #121217

LIGHT MODE TOKENS:

* Background: soft neutral light
* Card: white
* Elevated card: light gray-blue
* Border: subtle gray border
* Heading text: dark neutral
* Body text: medium neutral
* Muted text: soft neutral

DARK MODE TOKENS:

* Background: near black
* Card: charcoal
* Elevated card: darker charcoal
* Heading text: white
* Body/muted text: desaturated light grays

SEMANTIC:

* Success: green
* Warning: amber/yellow
* Critical: red
* Info: blue

RULES:

* Primary CTAs use CAT Yellow gradient + dark text.
* Draft state uses yellow indicator dot + text label "Draft".
* Submitted/complete states use green indicators.

---

DEFINE CORE SCREEN STRUCTURE

FLEET SCREEN:

* Top nav title uses CAT logo in principal title area.
* Must include:
1. Create Inspection
2. Search Fleet
3. Scan Fleet QR
4. Today's Inspections horizontal list
5. Action to open Inspections screen

INSPECTIONS SCREEN:

* Search trigger (shared global search)
* Inspections to do (top list)
* Previous inspections in expandable dropdown section

REPORTS SCREEN:

* Search trigger (shared global search)
* Fleet report list with status indicator
* Submitted reports: open PDF + feedback send
* Draft reports: open legal completion form (no PDF preview requirement for draft)

PROFILE SCREEN:

* Editable inspector profile fields
* Profile photo picker
* Dark mode toggle
* Persisted locally and reflected in dashboard header

---

DEFINE INSPECTION WORKFLOW

ENTRY:

* Can start from Fleet (today list/create flow) or Inspections list.

WORKFLOW SCREEN:

* Full-screen camera preview.
* Top overlay: fleet info + progress metrics.
* Bottom panel:
  * Activate Walk Around button
  * Horizontal task tabs
  * Task detail + controls

TASK FLOW:

* Each task must show task number and description.
* Start Task -> enables evidence capture.
* Capture up to 5 photos per task.
* Captured task photos must be visible as thumbnails and previewable.
* Voice recording (start/stop) captures audio evidence.
* While recording voice, task switching must be disabled.
* Send Feedback saves task feedback + media references.
* After send, auto-advance to next task.
* Completed task label/text should render success (green) state.
* Reopening completed task must show previously saved feedback and photos.

ALL TASKS COMPLETE STATE:

Replace task actions with:

1. Save Draft
2. Create Report

SAVE DRAFT BEHAVIOR:

* Create draft report in Reports list.
* Mark as Draft with yellow state.
* Exit workflow and return to previous dashboard state.

CREATE REPORT BEHAVIOR:

* Open legal report form.
* Collect required legal/compliance inputs.
* Submit as report (status Submitted).
* Exit workflow and return to previous dashboard state.

---

DEFINE DATA + PERSISTENCE

INSPECTIONS DATABASE (LOCAL):

* Persist all inspections and their task records.
* Persist per-task feedback text, audio filename, and photo filename array.
* Maintain backward compatibility for older single-photo records.

PROFILE STORAGE (LOCAL):

* Persist editable inspector profile including image data.

REPORT STORE (LOCAL):

* Persist report status (Draft/Submitted) and report metadata.

API INTEGRATION GUIDELINE:

* Keep stubs/hooks for backend dashboard, voice stream, and report sync.
* Local-first save, remote sync later.

---

DEFINE ACCESSIBILITY + USABILITY

* Contrast ratio >= 4.5:1.
* Controls >= 48px touch targets.
* Keep labels explicit for every major action.
* Avoid blocking overlays that hide camera evidence area during inspection.

---

DEFINE PROHIBITED PATTERNS

* Hidden critical actions.
* Contextless icon-only primary actions.
* Multi-step modal stacking that interrupts active capture.
* Losing captured evidence when switching tasks/screens.
* Showing draft reports as finalized/submitted documents.

---

DEFINE RELEASE VALIDATION CHECKLIST

* Bottom tabs exactly: Fleet, Inspections, Reports, Profile.
* Fleet contains create/search/scan/today list/open inspections.
* Inspections has to-do + previous dropdown + search.
* Reports supports draft and submitted paths distinctly.
* Profile edits persist and reflect in dashboard header.
* Workflow keeps camera visible and supports complete task evidence loop.
* All-task completion exposes Save Draft / Create Report actions.
* Save Draft and Create Report both return user to prior dashboard context.

END SPECIFICATION.
