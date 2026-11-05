# iumrah — guarded localization preflight repair, November 5, 2026

## Evidence

GitHub Actions run checked out `im-ceo-bitch/kepler-ios`, commit `cbce1ecb50ff6581385e45ea4d6613ae095d4c1f`, and failed in `Repository preflight` before Xcode archiving or TestFlight. Failures: missing root `.layoutDirection`, and 33 tuple-switch stages without Turkish/Indonesian/Malay/Arabic cases (132 cases). Two unassigned JPEG notices are **warnings**, not the failing cause.

## What is inside this ZIP

This ZIP is an **additive** file update for the existing `iumrah-beta-update-*.zip` unpacker. It installs `scripts/iumrah_preflight_repair_20261105.py` under `scripts/` and this document under `docs/`. It does **not** overwrite any application Swift files or alter business logic.

The script is **not run automatically by the existing ZIP unpacker**. Do not mistake successful extraction for a fixed TestFlight build.

## How to run against the current repository

1. Upload this root ZIP to the repository and confirm that the `Apply iumrah Beta ZIP update` workflow extracted its two files.
2. In the repository root, run:

   ```bash
   python3 scripts/iumrah_preflight_repair_20261105.py --check
   python3 scripts/iumrah_preflight_repair_20261105.py --apply
   python3 scripts/iumrah_preflight_repair_20261105.py --check
   python3 scripts/ci_language_audit.py
   ```

3. Review the six modified Swift files and commit them, then run `testflight.yml`.

If you do not use a terminal, upload the companion file `iumrah-preflight-repair-workflow.yml` **directly** to `.github/workflows/iumrah-preflight-repair.yml` using the GitHub web editor, then run **Actions → Repair iumrah language preflight (manual) → Run workflow** after the ZIP extractor completed. The current ZIP extractor skips `.github/workflows/*` other than its allowlisted deployment workflow, so including a workflow in this ZIP would not install it.

## Guardrails

- The script aborts on unexpected Swift switch structure (source code may have changed).
- Existing translations remain unchanged; it adds explicit translations for 4 additional languages.
- It checks the source before writing; second run is idempotent.
- No API, pricing, bookings, services or build signing secrets are changed.
- A real Xcode build is still required. Passing source parse is not proof of compile or TestFlight upload.
- Do not upload old October 24-file UI/UX ZIP to November main until merged with fresh source.

## Tests performed

Against the available October 8 baseline: dry-run found 6 files, 132 missing switch arms and RTL; apply created 133 source lines; second dry-run found no changes; `swiftc -frontend -parse` completed without errors on all six Swift files. **Current November main has not been cloned locally**, so application to that exact source and its Xcode build are unverified.
