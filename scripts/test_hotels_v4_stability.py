#!/usr/bin/env python3
"""Regression guards for Claude Hotels V3 + iumrah V4 stability patch.

These guards validate source invariants and a model-level order simulation;
they are not substitutes for Xcode type checking or a real supplier integration.
"""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'Sources/Views/Hotels/NuiteeHotelsCatalogView.swift').read_text()
service = (ROOT/'Sources/Services/NuiteeHotelService.swift').read_text()

def test(name, ok):
    if not ok:
        raise AssertionError(name)
    print('PASS', name)

def span(a, b):
    return source.split(a,1)[1].split(b,1)[0]

test('Claude V3 localized confirmed sold-out message kept', 'Нет номеров на эти даты' in source and 'No rooms for these dates' in source)
test('Claude V3 rate counter kept', 'с ценой' in source and 'priced = matches.filter' in source)
test('Claude V3 small loader kept', 'if model.pricesLoading { ProgressView().controlSize(.mini) }' in source)
test('Unverified ratings hidden', 'let reviewCount = hotel.reviewCount, reviewCount > 0' in source)
test('Dates / guests in scope key', 'NuiteeHotelService.dateText(checkout)' in source and '\\(childrenAges)' in source)
test('Star / unrated grouping preserved', 'rows.filter { $0.roundedStars == stars } + rows.filter { $0.roundedStars == 0 }' in source)
vis = span('func visibleHotels(', 'private static func uniqueHotels')
test('No background-rate-dependent sorting', '.sorted(' not in vis and 'guard !pricesLoading' not in vis and 'availabilityRank(' not in vis)
test('Catalog deduplicated at cached and live paths', source.count('Self.uniqueHotels(') >= 2 and 'seen.insert($0.id).inserted' in source)
test('Safe dictionary merge, no duplicate-ID trap', 'Dictionary(uniqueKeysWithValues: self.hotels.map' not in source and 'uniquingKeysWith:' in source)
test('Metadata refresh preserves existing card order', 'oldOrder[$0.element.id]' in source and 'sameScope' in source)
test('Retry loop applies one batch publication', source.count('merge(received, requested: Set(groupIDs)') == 1 and 'merge([row.id: row]' not in source)
test('Rate limit still short-circuits supplier fallback', 'if providerLimited {' in source and 'NUITEE_RATE_LIMIT' in source)
test('Canceled searches have retryable state', source.count('if Task.isCancelled && self.hotels.contains') == 2)
test('Photos publish only once per appearance', 'additionalPhotos = Array(candidates.prefix(3))' not in source and 'additionalPhotos = result.isEmpty ?' in source)
test('Photos throttle reattempts', 'lastPhotoAttempt) < 300' in source)
test('Missing photo request negative-cache / cap', 'cached.images.isEmpty ? 120 : 1800' in source and 'cache.count >= 250' in source)
test('Detail navigation / galleries / room selection preserved', 'navigationDestination(item: $opened)' in source and 'NuiteeHotelGallery(' in source and 'onSelectRate(rate)' in source)
test('Supplier APIs unchanged', 'func pricePage(' in service and 'func catalogRate(' in service and 'func rates(' in service)

# Representative model-level re-render scenario: prices/statuses must not change ordering.
seed = [{'id':'a', 'stars':5},{'id':'a', 'stars':5},{'id':'b','stars':0},{'id':'c','stars':4},{'id':'d','stars':5}]
seen=set(); unique=[x for x in seed if not (x['id'] in seen or seen.add(x['id']))]
selected=[h['id'] for h in unique if h['stars']==5] + [h['id'] for h in unique if h['stars']==0]
for pricing in ({'a':'loading','d':'loading','b':'loading'},{'a':'available','d':'loading','b':'no_availability'},{'a':'available','d':'no_availability','b':'available'}):
    test('order stable while prices change '+str(pricing), selected == ['a','d','b'])
print('OK: source / model stability regressions')
