import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const root = new URL('../../../', import.meta.url);
const read = (p) => fs.readFileSync(new URL(p, root), 'utf8');
const backend = read('Backend/PackageEngine/src/nuitee-hotels.ts');
const router = read('Backend/PackageEngine/src/index.ts');
const view = read('Sources/Views/Hotels/NuiteeHotelsCatalogView.swift');
const home = read('Sources/Views/Tabs/HotelsHomeView.swift');
const env = read('Backend/PackageEngine/src/env.ts');
const service = read('Sources/Services/NuiteeHotelService.swift');

test('Nuitee supplier authorization stays exclusively on server', () => {
  assert.match(backend, /'X-API-Key': key/);
  assert.match(router, /handleNuiteeHotelRequest/);
  assert.match(env, /NUITEE_API_KEY\?: string/);
  assert.match(backend, /env\.NUITEE_API_KEY/);
  assert.doesNotMatch(service, /NUITEE_API_KEY|X-API-Key|api\.liteapi\.travel/);
  assert.doesNotMatch(view, /NUITEE_API_KEY|X-API-Key|api\.liteapi\.travel/);
});

test('Hotels board switches provider without touching Flights and Sunday Club', () => {
  assert.match(home, /private var hotelsBoard:[\s\S]{0,150}NuiteeHotelsCatalogView\([^)]*\)/);
  assert.match(home, /case \.flights: flightsBoard/);
  assert.match(home, /case \.sundayClub: sundayClubBoard/);
  assert.match(view, /case makkah, madinah/);
  assert.match(view, /\[0, 1, 2, 3, 4, 5\]/);
});

test('Default one night 10 days in advance and supplier price is ROOM-ONLY', () => {
  assert.match(view, /value: 10, to: Date\(\)/);
  assert.match(view, /private var nights = 1/);
  assert.match(backend, /priceType: 'room_total'/);
  assert.match(backend, /minimum:v1:/);
  assert.match(backend, /48 \* 3600/);
  assert.match(backend, /10 \* 60/);
});

test('Hotel page contains a gallery, policy, privacy, real rates and no fake booking', () => {
  assert.match(view, /NuiteeHotelGallery/);
  assert.match(view, /cancellationAndPrivacy/);
  assert.match(view, /cancellationView\(rate\)/);
  assert.match(view, /service\.rates\(/);
  assert.doesNotMatch(view, /rates\/book|rates\/prebook/);
});
