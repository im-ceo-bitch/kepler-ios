# iumrah Orbit V5 — native SwiftUI

Reusable showcase component, iOS 17+ (SwiftUI / Canvas / TimelineView).
No network, GIF, video, web view, UIKit image decoding or external libraries.

## Install in iumrah

Overlay the archive at the repository root. The two Swift files live in
`Sources/Views/Components`, and the logo image set lives in
`Resources/Assets.xcassets`. The supplied kepler-ios-main 8 project.yml already
includes both source and asset directories. For other Xcode projects, add both
Swift files and the image set to the app target.

This is additive: it does not replace `IumrahOrbitIconRing`, alter any existing
screen or change booking / account / backend logic. Existing progress and
package-assembly modes are deliberately not replaced by this showcase view.

## Use

```swift
IumrahOrbitV5(diameter: 340)
```

```swift
IumrahOrbitV5(diameter: 210, lightOnDark: true)
```

```swift
IumrahOrbitV5(
    services: [
        .init(id: "flight", symbol: "airplane"),
        .init(id: "hotel", symbol: "building.2.fill")
    ],
    diameter: 280,
    rotationDuration: 25,
    revealDuration: 3.2,
    isActive: isPageVisible,
    logo: Image("IumrahOrbitAccountLogo"),
    logoWidthFraction: 0.38,
    accessibilityTitle: "Все услуги iumrah"
)
```

For an alternative center logo, pass a different monochrome template-compatible
Image. `lightOnDark: nil` follows the system appearance. Override it on cards
whose background differs from the system theme. Use a white or black parent
background as appropriate; the view itself is transparent. `isActive` lets
carousel / tab owners explicitly pause when not visible. The component also
pauses on disappearance, when the app is inactive, or with Reduce Motion.
In Reduce Motion the first expanded icon remains still.

## V5 geometry

- Four staggered rings, 24 points each, 96 total.
- Rotation: 25 s per revolution by default. Reveal cycle: 3.2 s.
- The selected point is on row 2 from the outside (row 3 from the center).
- The point expands to 55 pt at a component diameter of 360 pt, shifts to the
  radial midpoint, and neighboring dots shrink and fade. All values scale.
- The SF Symbol stays upright. The center image does not rotate.
- The spatial spectrum is continuous, matching the V5 preview palette.
- The center logo is cropped from the provided original iumrah ACCOUNT image,
  with a transparent background and template rendering. No substituted font.

## Validation

Swift 6.2.1 on Linux: both Swift sources parsed; pure Foundation geometry
compiled and passed 16 reveal cycles, annulus bounds, 307,296 visibility
checks, full revolution and Reduce Motion assertions. Asset catalog JSON and
ZIP integrity checked. Full SwiftUI type checking, Xcode build, SF Symbol
rendering and iPhone visual testing require the Apple SDK and were not run.
