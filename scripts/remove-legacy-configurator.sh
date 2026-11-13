#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[[ -d Sources && -f project.yml ]] || { echo 'Run in kepler-ios, not lattice-mobile.' >&2; exit 1; }
[[ ! -d Backend/IumrahBackend ]] || { echo 'Refusing to remove anything from canonical backend repository.' >&2; exit 1; }
case "${1:-}" in --apply|--dry-run|'') ;; *) echo 'Usage: bash scripts/remove-legacy-configurator.sh [--dry-run|--apply]'; exit 2;; esac
paths=(Backend/PackageEngine Backend/UnifiedDeploySnapshot .github/workflows/deploy-package-engine.yml)
# Remove only tracked update ZIPs containing the retired server implementation.
while IFS= read -r -d '' archive; do
    paths+=("$archive")
done < <(python3 - <<'PY'
import subprocess,zipfile,sys
for raw in subprocess.check_output(['git','ls-files','-z']).split(b'\0'):
    if not raw: continue
    path=raw.decode()
    if '/' in path or not path.startswith('iumrah-beta-update-') or not path.endswith('.zip'): continue
    try:
        with zipfile.ZipFile(path) as z:
            if any(n.replace('\\','/').startswith(('Backend/PackageEngine/','Backend/UnifiedDeploySnapshot/','Backend/IumrahBackend/')) for n in z.namelist()):
                sys.stdout.buffer.write(raw+b'\0')
    except (OSError,zipfile.BadZipFile):
        print('Inspect archive manually: '+path,file=sys.stderr)
PY
)
echo 'Tracked legacy paths to remove:'
git ls-files -- "${paths[@]}"
if [[ "${1:-}" != --apply ]]; then
    echo 'Dry run only. Run again with --apply to stage deletions.'
    exit 0
fi
git rm -r --ignore-unmatch -- "${paths[@]}"
echo 'Staged deletions. Review git status, commit, and push. No history rewrite or push was performed.'
