#!/usr/bin/env python3
"""Fail-closed static checks for the new Iumrah Apple Team (stdlib only)."""
import os
import plistlib
import re
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EXPECTED_TEAM = "HVT4U96286"
TEAM = os.environ.get("APPLE_TEAM_ID", EXPECTED_TEAM)
if TEAM != EXPECTED_TEAM:
    sys.exit("STOP: APPLE_TEAM_ID must be the new Iumrah recipient team (not old team).")
for path in ("Resources/iUmra.entitlements", "Resources/iUmraMacCatalyst.entitlements", "WidgetExtension/iUmraWidgets.entitlements"):
    with (ROOT/path).open("rb") as f:
        obj=plistlib.load(f)
    group=obj.get("keychain-access-groups",[])
    assert group == [f"{TEAM}.com.iumrah.shared"], f"{path}: wrong Keychain Sharing group: {group}"
widget=(ROOT/"Sources/WidgetShared/IumrahWidgetSnapshot.swift").read_text()
assert f'static let keychainAccessGroup = "{TEAM}.com.iumrah.shared"' in widget, "Widget Swift keychain group inconsistent"
project=(ROOT/"project.yml").read_text()
for name in ("com.iumrah.app", "com.iumrah.app.widgets"):
    assert f"PRODUCT_BUNDLE_IDENTIFIER: {name}" in project, "Bundle ID changed: " + name
assert 'MARKETING_VERSION: "2.1.0"' in project
assert 'CURRENT_PROJECT_VERSION: "200"' in project
assert len(re.findall(r"CODE_SIGN_STYLE: Automatic",project)) >= 3, "Targets not configured for automatic signing"
assert 'CODE_SIGN_STYLE: Manual' not in project, "Manual signing still configured"
print(f"PASS: transferred app identifiers, widget Keychain, version 2.1.0, auto signing, Team {TEAM}")
