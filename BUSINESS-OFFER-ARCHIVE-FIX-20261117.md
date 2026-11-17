# iumrah iOS V9 — Business Offer archive compatibility

Based on the supplied kepler-ios-main 7.zip and cumulative V8 overlay. The latest
GitHub build (commit 18fcce9db9e1ce1c49eb2d0618736c57d03a07d1, log
119361770840) fails at BusinessOfferView.swift:58:53 because BookingStore no longer
has adoptOfferBooking. All three reported errors are from that missing method.

The native Business offer acceptance endpoint in lattice-mobile-main 8.zip returns
`{booking, accessToken, trip, identityReady}`. Restore the missing synchronous
`adoptOfferBooking(_ response: BookingCreateResponse) throws -> StoredBookingSession`
entry point. It adopts the already-created booking using the returned access token,
persists in the existing Keychain-backed store, merges the canonical trip identity,
rejects malformed/mismatched receipts, and preserves a previously stored trip on
idempotent retries. It does not issue another create request. An existing account-only
record can receive the verified guest token without losing local state.

Validation:
- `scripts/test_business_offer_adoption_v9.sh` compiles the actual production method,
  actual booking/session/response model declarations, and the actual upsert and lookup
  methods against a lightweight harness. Tests cover normal acceptance, identity,
  duplicate retries, absent/incorrect token, mismatched trip, pending identity, and
  upgrading a restored trip. Keychain persistence is represented by a test counter.
- `scripts/ci_preflight.py`: 343 Swift files parsed, 426 language switches checked,
  96 assets and plists validated. Two pre-existing unassigned asset warnings.
- Prior hotel stability, creation notifications, guest Care, seamless booking, Smart
  edit, and catalog compatibility suites passed.

Limitations: the actual newer BusinessOfferView.swift is not in the supplied base ZIP;
its call site is visible in the Xcode log, and the expected receipt shape is grounded
in the supplied server code. The new file is not overwritten. Full Xcode archive
and current GitHub checkout type checking are not available in this Linux environment.
No changes to workflows, signing, or backend. All V8 files are retained; only
BookingStore.swift differs from V8, and this note and regression script are new.
