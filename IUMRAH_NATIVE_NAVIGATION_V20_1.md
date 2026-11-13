# iumrah — Native Navigation V20.1

Scope: native Apple navigation controls, on top of the V20 client update. This is not the other planned V21 manual-configurator and server partial-quote update.

- Normal NavigationStack pages keep the stock back control and system toolbars.
- Custom brand/flow/flight headers use IumrahGlassIconButton and the native SwiftUI glass button style on iOS 26. On earlier iOS versions the button uses the standard bordered style. No hand-drawn circle/blur on these back controls.
- Manual flight detail uses the same chrome modifier as the official flight detail.
- Hotel detail groups share and help in one ToolbarItemGroup. System toolbar help does not apply its own glass style.
- Calendar step navigation and text CTAs are not page Back buttons and remain content controls.
- Shared controls also cover the ritual guide, modal close buttons, prayer controls, account card and video overlays as updated in this patch.

Apply to kepler-ios after V20. No workflow, signing secret, backend or pricing engine changes. Run TestFlight. Swift syntax checked using Linux Swift 6.2.1 (316/316 source files); no iOS SDK, Xcode compilation or device rendering verification available in this environment.
