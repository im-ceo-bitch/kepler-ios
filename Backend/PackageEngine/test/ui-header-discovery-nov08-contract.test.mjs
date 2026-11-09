import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const root = new URL('../../../', import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), 'utf8');
const header = read('Sources/Core/Components/IumrahSignatureHeaders.swift');
const hotels = read('Sources/Views/Tabs/HotelsHomeView.swift');
const account = read('Sources/AppShell/IumrahAccountView.swift');
const booking = read('Sources/Views/Tabs/BookingsHomeView.swift');
const support = read('Sources/Views/Tabs/CareHomeView.swift');
const rootNav = read('Sources/AppShell/AppNavigationContainer.swift');
const chrome = read('Sources/Core/Components/IumrahFlightUXChrome.swift');
const home = read('Sources/Views/Home/HomeDashboardView.swift');
const serviceCards = read('Sources/Views/Home/HomeAppleStoreSections.swift');
const services = read('Sources/Views/Home/IumrahServicesView.swift');

test('five root tabs use shared height and do not paint white status-bar safe area', () => {
  assert.match(header, /contentHeight: CGFloat = logoHeight \+ topInset \+ lowerInset/);
  assert.match(header, /frame\(height: IumrahSignatureHeaderGeometry\.contentHeight, alignment: \.top\)/);
  assert.match(read('Sources/Core/Components/IumrahRootScrollingPage.swift'), /extendsUnderStatusBar: Bool = true/);
  assert.match(rootNav, /background\(Color\.iumrahPageBackground\.ignoresSafeArea\(edges: \.bottom\)\)/);
  assert.match(account, /IumrahPrimaryTabHeader\(/);
  assert.match(booking, /bookingHeader\(hasActiveBooking: activeSession != nil\)/);
  assert.match(support, /IumrahPrimaryTabHeader\(/);
});

test('header chrome uses only native glass rendering, and root CTA/search are opaque capsules', () => {
  assert.match(chrome, /content\.buttonStyle\(\.glass\)\.buttonBorderShape\(\.circle\)/);
  assert.match(header, /chrome\.openNotifications\(\)/);
  assert.match(header, /chrome\.openSidebar\(\)/);
  assert.match(hotels, /frame\(height: 56\)/);
  assert.match(hotels, /background\(Color\.black, in: Capsule\(\)\)/);
});

test('hotel discovery has separate real searches and never invents a multi-room price', () => {
  assert.match(hotels, /case \.hotels: hotelFields/);
  assert.match(hotels, /case \.flights: flightFields/);
  assert.match(hotels, /case \.weekends: weekendFields/);
  assert.match(hotels, /IumrahGraphiteSearchSurface/);
  assert.match(read('Sources/Core/Components/IumrahSignatureChrome.swift'), /TimelineView\(\.animation/);
  assert.match(hotels, /NuiteeHotelsCatalogView\(/);
  assert.match(hotels, /hotelCatalog\.reload/);
  assert.match(hotels, /manualQuoteRequired = hotelRooms != 1 \|\| hotelChildren > 0 \|\| hotelAdults > 6/);
  assert.match(hotels, /IumrahGuidedFlightSelectionView\(\)/);
  assert.doesNotMatch(hotels, /private var hotelsBoard|StorefrontFlightOptionCard|HotelStorefrontCard/);
});

test('booking and support feature functional hero capsules', () => {
  assert.match(booking, /hasActiveBooking \? AnyView\(/);
  assert.match(booking, /IumrahHeaderTripleTabs/);
  assert.match(support, /IumrahHeaderCapsuleActions/);
  assert.match(support, /case 0: openPhone\(\)/);
  assert.match(support, /case 1: openTelegram\(\)/);
  assert.match(support, /BookingChatView\(bookingID: activeSession\.id\)/);
  assert.match(support, /enabled: \[!preferredPhone\.isEmpty, telegramURL != nil, activeSession != nil\]/);
});

// Corrected November 9 behavior: no sticky masthead during upward scrolling.
test('all five mastheads scroll offscreen upward and never stretch on refresh pull', () => {
  const scrolling = read('Sources/Core/Components/IumrahRootScrollingPage.swift');
  assert.match(scrolling, /ScrollView\(showsIndicators: false\)/);
  assert.match(scrolling, /masthead[\s\S]*?\.offset\(y: -overscroll\)/);
  assert.match(scrolling, /max\(0, scrollTop\)/);
  assert.match(scrolling, /if refreshing \|\| overscroll > 18/);
  assert.match(scrolling, /ProgressView\(\)/);
  assert.match(scrolling, /distance >= 76, !refreshing/);
  assert.match(scrolling, /IumrahPullObserver/);
  assert.match(scrolling, /await onRefresh\(\)/);
  assert.doesNotMatch(scrolling, /\.refreshable\s*\{/);
  assert.match(home, /IumrahRootScrollingPage\(onRefresh:/);
  assert.match(home, /presentation: \.header/);
  assert.match(home, /presentation: \.search/);
  for (const [tab, code] of [['account',account], ['booking',booking], ['support',support], ['hotels',hotels]]) {
    assert.match(code, /IumrahRootScrollingPage\(onRefresh:/, `${tab}: masthead must share the page ScrollView`);
    assert.doesNotMatch(code, /\.refreshable\s*\{/, `${tab}: do not put native spinner above scrolling masthead`);
  }
  assert.match(booking, /private func activeBookingHub\(_ session: StoredBookingSession\) -> some View \{\s*VStack/);
  assert.match(booking, /private var emptyBookingHome: some View \{\s*VStack/);
  assert.doesNotMatch(header, /position\(x:/);
});

test('the installed Services carousel and full screen survive the fix with every app language', () => {
  assert.match(home, /IumrahHomeServicesSection\(/);
  assert.match(serviceCards, /IumrahServicesView\(initialService: kind\)/);
  assert.match(services, /enum IumrahServiceKind/);
  assert.match(services, /case \.english, \.turkish, \.indonesian, \.malay, \.arabic/);
  assert.match(serviceCards, /case \.english, \.turkish, \.indonesian, \.malay, \.arabic/);
});

// November 9: direct visual QA fixes requested after the Booking comparison.
test('all primary tabs center the same brand row, with flat lower edge outside Home', () => {
  assert.match(header, /struct IumrahPrimaryHeaderBrandRow: View/);
  assert.match(header, /IumrahPrimaryTabHeader:[\s\S]*?IumrahPrimaryHeaderBrandRow\(\)/);
  assert.match(home, /private var blackTop:[\s\S]*?IumrahPrimaryHeaderBrandRow\(\)/);
  assert.match(header, /IumrahType\.bold\(28, relativeTo: \.largeTitle\)/);
  assert.doesNotMatch(header, /clipShape\(UnevenRoundedRectangle/);
  assert.match(home, /clipShape\(UnevenRoundedRectangle/);
  assert.match(header, /chrome\.openSidebar\(\)/);
  assert.match(header, /chrome\.openNotifications\(\)/);
  const scrolling = read('Sources/Core/Components/IumrahRootScrollingPage.swift');
  assert.doesNotMatch(scrolling, /\.zIndex\(1\)/);
});
