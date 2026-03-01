

# CAT Omni-Glass: Interactive 3D Inspection Portal

## Overview
A cinematic React Three Fiber landing experience for the HackIllinois entry. Users see a 3D CAT machine in a dark industrial hangar, interact with it, and "enter" the cab to view narrative slides before proceeding to the admin dashboard.

---

## Page 1: The 3D Hangar Scene (Home `/`)

### Environment
- Dark industrial background (#111111) with a subtle grid floor
- Studio cinematic lighting: warm rim light (#FFCD00) on machine edges, cool ambient fill
- Environment map for realistic metallic reflections on the yellow body

### The Machine
- A stylized CAT excavator/crane built with R3F geometric primitives (boxes, cylinders) since sourcing a free .glb with proper licensing is unreliable — primitives give us full control and the abstract industrial look fits the "Power Edge" aesthetic
- CAT Yellow (#FFCD00) metallic materials on the body, Machine Black (#191919) on treads/joints
- Idle "breathing" animation: subtle hydraulic piston movement on the boom arm

### Interaction — The Cabin Door
- A floating "INSPECT" marker pulses near the cab door
- **On Hover**: Door outlines in yellow, cursor changes to crosshair
- **On Click**: Door swings open, camera smoothly flies through the doorway with a cinematic zoom — screen fades to the interior cab view

---

## Page 2: Inside the Cab — HUD Narrative (still on `/`)

### Visual Style
- Dark background with a subtle cockpit frame/vignette
- Glass-morphism semi-transparent cards with yellow accent borders
- HUD-style typography (monospaced headers, clean sans-serif body)

### Slides (manual left/right navigation with arrows + keyboard)
1. **"WHO WE ARE"** — "The Elite HackIllinois Crew. We don't just build apps; we build the future of the jobsite."
2. **"THE TECH"** — "Omni-Glass: Raspberry Pi Edge + Modal VLM + Actian VectorDB. Hands-free. Eyes-on. Zero manual entry."
3. **"THE VISION"** — "Turning unstructured field data into instant procurement orders."

### CTA — Final Slide
- Large industrial yellow button with beveled edge: **"ENTER COMMAND CENTER"**
- Hover effect: scanning line animation with "SYSTEM AUTHORIZED" text
- Click navigates to `/admin/dashboard`

---

## Page 3: Admin Dashboard Placeholder (`/admin/dashboard`)

- Simple branded placeholder page with CAT color scheme
- Message: "Command Center — Ready for deployment"
- Back button to return to the 3D experience

---

## Design System Updates
- Add CAT brand colors to the Tailwind theme (cat-yellow, machine-black, alert-red)
- Add custom animations (pulse glow, scan line, fade transitions)
- Monospaced + industrial typography for the HUD elements

## Technical Approach
- React Three Fiber + @react-three/drei for the 3D scene
- Framer Motion or CSS transitions for the 3D-to-2D cab transition (fade-to-black)
- React Router for navigation to /admin/dashboard

