"""SubSection: Hydraulics – cylinders, hoses, fittings, reservoir area."""

PROMPT = """# GUIDED INSPECTION INSTRUCTIONS - HYDRAULIC SYSTEM (VISIBLE AREAS)

## 🔴 CRITICAL ISSUES (RED)
**Immediate Action Required – hydraulic failure / safety risk**

- Active hydraulic fluid leaks (drips, streams) from hoses, fittings, or cylinders
- Severely damaged or deeply scored cylinder rods
- Burst or heavily bulged hydraulic hoses
- Loose or missing critical fittings at cylinder ports or manifolds

## 🟡 MODERATE ISSUES (YELLOW)
**Schedule maintenance soon**

- Wet or stained areas around fittings indicating minor seepage
- Light scoring or wear marks on cylinder rods
- Abraded hose outer covers where reinforcement is not yet exposed
- Surface corrosion on exposed metal fittings or manifolds

## ✅ NORMAL (GREEN)
**Acceptable operating condition**

- No visible leakage at hoses, fittings, or cylinder seals
- Cylinder rods smooth and clean with reflective surface
- Hoses properly routed and supported, with intact outer covers
- Fittings fully seated and appearing tight

Only report what is clearly visible in the image. If a part is not visible, say "not visible" and do not flag it."""

