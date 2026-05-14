# NestBot Mascot Bible

Last updated: 2026-05-13

## Purpose

NestBot is the visual face of EMI Locker. The mascot must stay recognizable across the dealer app, user app, admin panel, investor material, marketing, and future payment app. Future work may create new poses, expressions, and animations, but it must not redesign the mascot unless a redesign is explicitly approved.

## Locked Identity

NestBot is a friendly green security robot for device-financing protection.

The approved identity is defined by:

- Rounded square robot head with dark green glass face.
- Large glowing mint eyes with simple friendly expression.
- Metallic green armor body.
- Gold/green shield-and-lock chest emblem.
- Side ear/helmet pods.
- Small antenna/signal element above the head.
- Short compact body proportions with large head, small torso, and sturdy boots.
- Soft premium 3D-rendered style, not flat cartoon and not aggressive.
- Calm, trustworthy, protective personality.

## Canonical Reference Assets

Use these assets as the current reference set:

- Master pose sheet: `D:\EMI APP\docs\mascot\nestbot-posture-sprite-source.png`
- Clean hero mascot: `D:\EMI APP\docs\mascot\emi-locker-mascot-clean-hero.png`
- Current welcome preview: `D:\EMI APP\docs\mascot\nestbot-welcome-postures-v5.gif`

Reference hashes:

| Asset | SHA-256 |
| --- | --- |
| `nestbot-posture-sprite-source.png` | `2B3BA011FE55AD8BCD5B433DDE8278AA330BA60DF646DFC47188AFC27C0475CD` |
| `emi-locker-mascot-clean-hero.png` | `B50763436DE9A566BDD67C85A37548BAB79CC997E92F10DEB8B2C9984026B779` |
| `nestbot-welcome-postures-v5.gif` | `5A282AD68F5ABF7F00942096AED070022A81612160050A17F2E01236E282B4F1` |

## What Can Change

Allowed changes:

- Arm pose.
- Hand gesture.
- Body posture.
- Facial expression, within the same eye and mouth style.
- Prop held by NestBot, such as activation code, shield, payment reminder, map pin, warning sign, or success badge.
- Camera framing and scale for UI needs.
- Small animation motion, such as gentle breathing, blink, wave, or pose settle.

## What Must Not Change

Do not change these without explicit approval:

- Head shape.
- Face panel shape.
- Eye style.
- Green/gold color family.
- Chest shield-lock emblem.
- Body armor pattern.
- Antenna/signal element.
- Helmet/ear pods.
- Overall proportions.
- 3D premium rendering style.
- Friendly/protective character personality.

## Pose Creation Rule

Every new pose must be treated as the same character acting differently, not a new character.

The correct prompt direction is:

> Create the exact same NestBot mascot from the approved reference. Preserve the same face, head shape, eyes, body proportions, green metallic armor, gold shield-lock chest emblem, antenna, side pods, color palette, and premium 3D style. Change only the pose/expression/held prop. Do not redesign the mascot.

Avoid prompts like:

> Create a robot mascot for EMI Locker.

That creates a new mascot and causes brand drift.

## Welcome Screen Pose Set

The welcome screen should use three posture states while keeping the mascot anchored in a stable visual position:

1. Welcome: friendly wave.
2. Activation: holding a six-digit activation code.
3. Protection: shield/check or confident protection posture.

The screen may transition between pages, but NestBot should not appear to jump, float, or become a different design.

## Asset Quality Checklist

Before approving a new mascot asset, check:

- Same NestBot identity as the canonical reference.
- No new head, face, armor, or color design.
- Transparent or clean background with no fake checkerboard artifacts.
- No cropped body parts unless intentionally framed.
- No text overlap.
- No square demo-card frame unless the UI itself requires one.
- Pose reads clearly at mobile size.
- Works on both light and dark UI backgrounds.

## Future Production Workflow

Recommended workflow:

1. Approve one master model sheet.
2. Create a pose library from the model sheet.
3. Export transparent PNG/WebP/Lottie-ready assets.
4. Use the same pose library inside Flutter instead of regenerating a new mascot each time.
5. When new art is needed, compare it against this bible before adding it to the app.

## Notes

Professional mascot systems use model sheets/turnaround sheets to keep the character "on model" across poses, artists, and animation. NestBot should follow that same rule because it represents EMI Locker's brand identity.
