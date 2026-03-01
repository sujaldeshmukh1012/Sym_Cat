"""SubSection: Hydraulics – cylinders, hoses, fittings, reservoir, pump area."""

PROMPT = """# GUIDED INSPECTION INSTRUCTIONS - HYDRAULIC SYSTEM
## Heavy Equipment Daily Visual Analysis

### OVERVIEW
This inspection module covers all visible hydraulic components: cylinders, hoses, fittings, quick-disconnects, the hydraulic reservoir/tank, pump area, and any associated mounting hardware. Hydraulic failures cause immediate loss of machine control and can create high-pressure injection hazards lethal to personnel.

---

## INSPECTION CATEGORIES AND DETECTION POINTS

### 🔴 CRITICAL SAFETY ISSUES (RED INDICATORS)
**Immediate Action Required - Equipment Should Not Operate**

#### **ACTIVE HYDRAULIC LEAKS**
- **Hose or Fitting Leak**
  - Look for: Fluid dripping, streaming, or spraying from hose connections or fittings
  - Detection Points: Wet/shiny fluid on fittings, pooling below joints, oil-soaked hose exteriors
  - Risk Level: Critical - Pressure loss, fire hazard, injection injury risk

- **Cylinder Seal Leak**
  - Look for: Oil film or active weeping around cylinder rod seals, puddles below cylinders
  - Detection Points: Glistening rod surface beyond normal lubrication, oil streaks on cylinder tube
  - Risk Level: Critical - Loss of lifting/holding force, cylinder drift under load

- **Burst or Bulging Hose**
  - Look for: Visible bulge, bubble, or rupture in hose wall, exposed wire reinforcement
  - Detection Points: Localized swelling, frayed outer cover exposing braided wire, spray pattern
  - Risk Level: Critical - Imminent catastrophic hose failure

#### **STRUCTURAL HYDRAULIC DAMAGE**
- **Deeply Scored Cylinder Rod**
  - Look for: Deep scratches, gouges, or pitting on chrome cylinder rod surface
  - Detection Points: Visible grooves catching light differently than smooth chrome
  - Risk Level: Critical - Seal destruction, contamination ingress

- **Missing or Loose Critical Fittings**
  - Look for: Empty ports, hand-tight fittings, missing O-ring boss plugs
  - Detection Points: Open threaded ports, fittings backed off, visible threads at connections
  - Risk Level: Critical - Sudden pressure loss

### 🟡 MODERATE ISSUES (YELLOW INDICATORS)
**Schedule Maintenance**

#### **EARLY WEAR INDICATORS**
- **Minor Seepage at Fittings**
  - Look for: Damp or stained areas around fittings without active dripping
  - Detection Points: Oil-darkened dust rings around connections, slight moisture film
  - Risk Level: Moderate - Progressing leak; tighten or replace at next service

- **Hose Outer Cover Abrasion**
  - Look for: Scuffed, abraded, or chafing hose outer cover where reinforcement is NOT exposed
  - Detection Points: Rough texture, color change from friction, flat spots from contact
  - Risk Level: Moderate - Protective cover compromised; reinforce or reroute

- **Light Cylinder Rod Scoring**
  - Look for: Fine surface scratches visible under close inspection
  - Detection Points: Hairline marks that don't catch a fingernail
  - Risk Level: Moderate - Monitor for progression

- **Corroded Fittings or Manifold**
  - Look for: Surface rust, pitting, or white corrosion on exposed metal fittings
  - Detection Points: Discoloration, rough texture on originally smooth surfaces
  - Risk Level: Moderate - May compromise seating or torque specs

#### **RESERVOIR AND PUMP AREA**
- **Low Hydraulic Fluid Level**
  - Look for: Fluid level below sight glass minimum, foamy or aerated fluid
  - Detection Points: Sight glass reading, air bubbles visible in fluid
  - Risk Level: Moderate - Pump cavitation risk

- **Contaminated Fluid (visible)**
  - Look for: Milky (water contamination), dark/burnt (overheating), metallic sheen
  - Detection Points: Visible through sight glass or at open ports
  - Risk Level: Moderate to Critical depending on severity

### ✅ NORMAL (GREEN)
**Acceptable Operating Condition**

- No visible leakage at hoses, fittings, or cylinder seals
- Cylinder rods smooth, clean, with consistent chrome reflective surface
- Hoses properly routed with supports/clamps intact, outer covers undamaged
- All fittings fully seated and torqued, no visible thread exposure
- Hydraulic reservoir fluid level within normal range on sight glass
- No unusual staining, pooling, or saturation around hydraulic components
- Mounting brackets and clamps secure with no missing hardware

Only report what is clearly visible in the image. If a part is not visible, say "not visible" and do not flag it."""

