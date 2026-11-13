# V18 — client changes
Apply to current kepler-ios (V13 UI retained). No backend code or workflows included. Send server quoteProof when creating bookings; transfer screen uses the server total instead of computing a local final total. Public option prices are display-only.

After extraction, run from a clean kepler-ios checkout:

    bash scripts/remove-legacy-configurator.sh --dry-run
    bash scripts/remove-legacy-configurator.sh --apply

Review git status, commit and push the staged deletions. This removes the obsolete server directory, snapshot directory, obsolete deployment workflow and tracked update ZIPs containing those paths. It does not rewrite history or push. Keep the private canonical engine in lattice-mobile. No changes to TestFlight or unpack workflow. Audit historical commits/artifacts separately; make private any repository containing confidential formulas.

Swift frontend syntax check: 312 files. Xcode/TestFlight not run. Deploy backend from Business; production cutover remains gated until real D1/R2 migration is verified and clients are compatible.
