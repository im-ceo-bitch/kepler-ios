# iumrah Home Personalization — cumulative client update, 2026-11-16

Root-overlay update for kepler-ios-main. All existing Home sections remain. New sections: recent actions/resume, destinations, published packages, Rewards/referral, recommended hotels, benefits and personalization preferences.

Recent actions are local, isolated by account; guest history is separate. Smart draft answers and step are saved; assembled packages are rebuilt/requoted when resumed, not guaranteed at a previously displayed price. Published packages and hotel metadata are read from existing APIs; no new backend endpoints and no new live flight search. Welcome bonus is not advertised until server eligibility exists. Referral promotion uses the existing program.

Includes preceding cumulative Smart V3, booking/gallery/Care, build fixes, Account Rewards, performance/documents and Push/Refresh/Referral V2 UZ client changes. No Business/backend changes in this archive.

Validation: repository ci_preflight.py passed (337 Swift files parsed, 424 language switches, 96 assets/plists); 18 isolated Swift persistence/privacy assertions passed using actual history models with platform shims. Full Xcode type checking, real device UI and production API behavior are not verified in Linux.

Install: upload ZIP to client repo root, apply existing unpacker, then client build-only/TestFlight. Business/backend deployment only needed for separately released previous Push/Referral V2 UZ if not already installed.
