# iumrah iOS — Booking Empty State & Static Splash 17 (cumulative)

This cumulative ZIP includes updates 01–16 **plus** update 17. Apply the ZIP once at the repository root using the existing apply-beta-update workflow. It is a patch, not a complete repository.

## Changes

- `Sources/App/IumrahLaunchExperience.swift`: immediate static launch handoff, single soft haptic on ordinary cold launch, preserves cold deep links and quick actions; no artificial multi-beat launch timeline.
- `Sources/App/IumrahSignatureLaunchLayer.swift`: black background with a white existing iumrah wordmark. No animated sphere, cross-fade, or animated world map **in the splash only**. All other app animations are untouched.
- `Sources/Views/Tabs/BookingsHomeView.swift`: compact empty state, one working primary `Создать путешествие` action; compact `Найти бронирование` and `Сохранённые путешествия` navigation links. Removes large Telegram, package CTA, Configurator and Care showcase cards from **empty-state rendering**. Active booking UI stays unchanged. Displays an actionable retry notice rather than a false empty state if signed-in trip recovery fails.
- `Sources/State/BookingStore.swift`: publishes authenticated trip recovery lifecycle and treats remote list/detail failures separately from a truly empty list.
- `Sources/Views/Booking/IumrahBookingAccessCard.swift`: shared standalone booking lookup screen expands the existing verified email/SMS access form immediately; no required sign-up and no weaker server verification.
- `Sources/AppShell/IumrahAccountView.swift`: authenticated profile includes a `Найти бронирование` entry beneath My trips. Guest profile keeps its existing booking access card.

## Verification

- Static validation of new routes, existing OTP and one-shot splash: `scripts/test_booking_empty_splash_17.sh`.
- Swift syntax parser over all 348 Swift sources of the merged original repo and cumulative patch.
- Existing Brand Experience 15, seamless booking, Smart stability and Trip Summary design checks passed against merged sources.

Not tested here: iOS binary build via Xcode, hardware haptics, interactive screenshot QA, end-to-end server OTP delivery. The booking lookup retains the original server-side behavior.
