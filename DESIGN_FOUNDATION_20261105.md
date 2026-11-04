# iumrah Design Foundation — v1 (2026-11-05)

## Purpose
Unify the customer-facing iOS presentation while retaining all existing business logic, API requests, data stores, booking state and navigation.

## Single source of truth

`Sources/Core/IumrahFoundation.swift` defines:

- `IumrahFoundation.Space`: 4 / 8 / 12 / 16 / 18 / 22 / 28 pt spacing.
- `IumrahFoundation.Radius`: controls 19, compact cards 22, cards 28, hero 34 pt (continuous).
- `IumrahFoundation.TypeStyle`: semantic, Dynamic Type-aware SF Pro/SF Pro Rounded styles.
- `IumrahFoundation.Motion`: press 0.16 s, state changes 0.24 s, entrance spring 0.48 s; Orbit 11 s revolution and 0.95 s service reveal.
- `IumrahFoundation.Size`: 56 pt primary CTA and 44 pt minimum tap target.

The older `IumrahDesign` names remain as compatibility aliases. Do not introduce another arbitrary global spacing/radius definition on new screens.

## Components

| Component | Responsibility |
|---|---|
| `IumrahFoundationCard` | Neutral elevated content card and dark branded variant |
| `IumrahFoundationSectionTitle` | Consistent section heading and support copy |
| `IumrahFoundationHomeHero` | Family-first value proposition, included services and real configurator CTA |
| `IumrahFoundationFeature` | Compact SF Symbols + text service feature |
| `IumrahFoundationStageRail` | Five real generator states, with accessible active/completed presentation |
| `IumrahFoundationCompactSteps` | Eight-step family flow; includes localized VoiceOver status |
| `IumrahOrbitIconRing` | Existing native Orbit; timing defaults now shared with Foundation |

## Screen integration

**Home**
- Family-first hero card with direct **Plan/Calculate Umrah** action; restores saved draft before navigation.
- White search card with uniform title typography, radius and primary CTA; existing Hotels-tab search routing unchanged.
- All `IumrahHomeSectionHeader` instances now use one foundation heading component.
- Product Configurator Orbit retains its dedicated dark card.

**Onboarding**
- Final screen uses neutral/monochrome Orbit presentation, localized service benefit labels and the same black CTA style as Home.
- Orbit pauses offscreen/in inactive scenes and respects Reduce Motion.
- Existing five-page onboarding order, native navigation and completion callback remain unchanged.

**Configurator Flow**
- `IumrahGeneratorHeader` uses an explicit step title and horizontal circular status rail in place of a decorative 3D carousel; five stage values remain the existing `TripProgressStage` cases.
- The eight-step family branch uses one step-counter component for stages 3–8 (where existing step labels were shown).
- Final package title and assembly card inherit Foundation typography and surfaces; selected-service Orbit remains a *visual summary*, not a booking confirmation.

## Rules for subsequent UI work

1. Use semantic typography from `IumrahFoundation.TypeStyle`; avoid per-card font sizes.
2. Prefer SF Symbols, monochrome content and neutral white cards. Use semantic status colors only for real states (success, error, pending).
3. The black filled CTA is reserved for primary actions; secondary controls should not visually compete.
4. Liquid Glass belongs to navigation/floating controls, not dense reading cards.
5. Motions should communicate a transition or state change; avoid multiple continuous animations on a screen and respect Reduce Motion.
6. Treat iPhone 13 mini / iPhone 11 as baseline layouts. Keep touch targets at least 44 pt and test Dynamic Type / dark mode.
7. Never fake server prices, supplier availability or booking confirmation with local animations.
8. Every new visible string should be localized; do not replace real navigation or API logic in a design pass.

## Release verification

Completed locally:
- Swift parser validation of all project Swift sources.
- ZIP content integrity and application overlay verification.

**Not completed:** Apple SDK type checking, Xcode iOS archive, UI screenshot regression and TestFlight installation. Those require the macOS CI runner / Xcode 26. Run the existing build-only gate before publishing.

## Next design passes

This version establishes Foundation and refreshes the three top-level journeys. It does **not** claim that all 5 tabs, every sheet, hotel details, checkout and all edge states have already been pixel-audited. Continue with an iPhone-size screenshot audit, then migrate secondary screens component-by-component.
