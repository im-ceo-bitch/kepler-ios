#!/usr/bin/env python3
"""Fail-closed compatibility for newly added language enum members.

Repair remaining flat, exhaustive AppSettingsStore.Language switch statements by
sharing existing English branches for untranslated new languages. This is an
explicit English fallback, not a translation, and never removes original cases.
Tuple cases have their own explicit translation repair, run first.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = ('russian', 'english', 'uzbek', 'uzbekCyrillic', 'turkish', 'indonesian', 'malay', 'arabic')
NEW = ('turkish', 'indonesian', 'malay', 'arabic')

class UnsafeChange(Exception): pass

def switches(source):
    # Deliberately narrow: don't touch unrelated Swift enums.
    pattern = re.compile(r'\bswitch\s+(settings\.language|language|self)\s*\{')
    for m in pattern.finditer(source):
        opening=m.end()-1
        depth=1; i=opening+1
        while i<len(source) and depth:
            if source[i]=='{': depth+=1
            if source[i]=='}': depth-=1
            i+=1
        if depth: raise UnsafeChange('Unclosed switch at offset '+str(m.start()))
        yield m.group(1), opening+1, i-1

def additions(source, target):
    edits=[]; count=0
    for expr,opening,closing in switches(source):
        body=source[opening:closing]
        candidates=list(re.finditer(r'(?m)^([ \t]*)case\s+([^:\n]+):', body))
        if not candidates: continue
        minindent=min(len(c.group(1)) for c in candidates)
        cases=[c for c in candidates if len(c.group(1)) == minindent]
        covered=set()
        for c in cases:
            covered.update(re.findall(r'\.('+ '|'.join(EXPECTED) +r')\b',c.group(2)))
        # Keep unknown switches untouched: 'self' may refer to an unrelated enum.
        if expr=='self':
            if not {'russian','english','uzbek','uzbekCyrillic'}.issubset(covered):continue
        elif expr=='language':
            if len(set(EXPECTED[:4]) & covered)<3: continue
        elif not {'english','russian'}.issubset(covered):
            continue
        if not set(covered).issubset(EXPECTED):
            raise UnsafeChange(f'Unexpected language cases: {covered} in {target}')
        if re.search(r'(?m)^\s*(?:@unknown\s+)?default\s*:',body):continue
        missing=[name for name in EXPECTED if name not in covered]
        if not missing: continue
        english=next((c for c in cases if re.search(r'\.english\b',c.group(2))),None)
        if not english: raise UnsafeChange(f'No English fallback in {target} offset {opening}')
        old=english.group(0)
        # Append the missing enum patterns to an existing case arm. That preserves
        # the English implementation, rather than inventing behavior.
        pos=opening+english.start()+len(old)-1
        edits.append((pos, ', '+', '.join('.'+l for l in missing)))
        count+=1
    for pos,insertion in sorted(edits,reverse=True):
        source=source[:pos]+insertion+source[pos:]
    return source,count

def run(apply:bool):
    settings=(ROOT/'Sources/AppShell/AppSettingsStore.swift')
    if not settings.is_file():raise UnsafeChange('AppSettingsStore.swift missing')
    enum=settings.read_text('utf-8')
    for name in EXPECTED:
        if not re.search(r'\bcase\s+'+name+r'\s*=',enum):raise UnsafeChange('Language enum lacks '+name)
    changed={}; total=0
    for p in sorted((ROOT/'Sources').rglob('*.swift')):
        before=p.read_text('utf-8')
        after,n=additions(before,str(p.relative_to(ROOT)))
        if before!=after:changed[p]=after
        total+=n
    print(f'FLAT LANGUAGE SWITCHES: {total} switch arms in {len(changed)} files need new-language English fallbacks')
    for p in changed: print(' - '+str(p.relative_to(ROOT)))
    if apply:
        for p,after in changed.items():p.write_text(after,'utf-8')
        print('APPLIED: these are English fallbacks, NOT completed translations.')
    else:print('CHECK ONLY: no files changed')

if __name__=='__main__':
    p=argparse.ArgumentParser()
    ex=p.add_mutually_exclusive_group(required=True)
    ex.add_argument('--check',action='store_true');ex.add_argument('--apply',action='store_true')
    args=p.parse_args()
    try:run(args.apply)
    except (UnsafeChange,OSError) as e:
        print('STOP: '+str(e));raise SystemExit(2)
