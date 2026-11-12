import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (relative) => fs.readFileSync(new URL(`../../../${relative}`, import.meta.url), 'utf8');
const storefront = read('Sources/State/HotelStorefrontStore.swift');
const home = read('Sources/Views/Home/HomeDashboardView.swift');
const services = read('Sources/Views/Home/HomeAppleStoreSections.swift');
const servicesPage = read('Sources/Views/Home/IumrahServicesView.swift');
const notificationCenter = read('Sources/Services/ClientNotificationCenter.swift');
const pushService = read('Sources/Services/ClientPushService.swift');

test('native hotel storefront admits ready priced server snapshots without the obsolete exact-trio engine gate', () => {
  const applyStart = storefront.indexOf('private func applyHotelServerPackages');
  const applyEnd = storefront.indexOf('private func isUsableHotelFirstSnapshot', applyStart);
  assert.ok(applyStart >= 0 && applyEnd > applyStart);
  const apply = storefront.slice(applyStart, applyEnd);
  assert.match(apply, /isUsableHotelFirstSnapshot/);
  assert.doesNotMatch(apply, /isValidHotelFirstGroup/);
  assert.match(storefront, /standardQuotes\[hotel\.id\] \?\? comfortQuotes\[hotel\.id\] \?\? luxuryQuotes\[hotel\.id\]/);
});

test('home configurator keeps its white card, CTA and the actual search navigation', () => {
  assert.match(home, /let cardHeight: CGFloat = 540/);
  const hero = home.slice(home.indexOf('private var hero: some View'), home.indexOf('private var configuratorTimeBadge: String'));
  assert.match(hero, /focusJourneySearchRevision \+= 1/);
  assert.match(hero, /Image\("StoreConfiguratorPhones"\)/);
  assert.match(hero, /Text\(configuratorHeroCTA\)/);
  assert.match(hero, /\.background\(Color\.white\)/);
  assert.match(hero, /\.accessibilityLabel\(configuratorHeroTitle\)/);
});

test('transfer car order is Malibu then Carnival then Yukon everywhere', () => {
  // The former image-card carousel was deliberately replaced by the
  // expandable Services screen; the standalone vehicle selector retains its order.
  assert.match(servicesPage, /case transfer, guide, ziyarat|case visa, flights, hotels, transfer/);
  assert.match(services, /@State private var selectedVehicle: TransferVehicleKind = \.malibu/);
  assert.match(services, /private let vehicles: \[TransferVehicleKind\] = \[\.malibu, \.carnival, \.yukon\]/);
});

test('push registration reports the actual signed application bundle to Hotels Cloud', () => {
  assert.match(notificationCenter, /appBundleID: AppIdentity\.runtimeBundleID/);
  assert.match(pushService, /appBundleID: AppIdentity\.runtimeBundleID/);
  assert.match(notificationCenter, /for attempt in 0\.\.<3/);
});
