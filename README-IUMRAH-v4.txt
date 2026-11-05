IUMRAH · TestFlight guarded compilation repair · 2026-11-05

Purpose: fix the exact new Swift compile errors in workflow log 113838161142
(checked-out commit 9aa5191fb64df5cdfd2a2cc45d7d6a4ae266c246).

Compatible with repository-root ZIP unpacker: archive entries have scripts/... paths.
Requires previous v3 preflight compatibility script to be present in current repository;
updated scripts/iumrah_language_switch_compat_20261105.py now calls the new
scripts/iumrah_compile_repair_20261105.py automatically during CI preflight.

The helper validates every expected source anchor and refuses changed layouts.
Changes to Swift are applied in the GitHub Actions checkout ONLY, not committed
back to the repository. This is a temporary compile unblock, not a source merge.
Booking checkout remains gated by existing SMS/email OTP verification.

KNOWN LIMITS: No macOS Xcode compile available in this environment. The helper
was Python-syntax checked and is based on the exact source files at the SHA above;
build success cannot be claimed. The fix does not replace translations.

Upload this ZIP to root and trigger the same unpack workflow. After extracting,
run TestFlight workflow normally. Do NOT upload the old October 24-file redesign.
