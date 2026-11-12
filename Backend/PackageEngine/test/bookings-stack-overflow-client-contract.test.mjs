import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../../../Sources/Views/Tabs/BookingsHomeView.swift', import.meta.url), 'utf8');

test('booking tab root isolates complicated SwiftUI view types before navigation modifiers', () => {
  assert.match(source, /private var bookingScrollRoot: AnyView\s*\{\s*AnyView\(\s*IumrahRootScrollingPage/);
  assert.match(source, /header:\s*\{\s*AnyView\(bookingHeader\(hasActiveBooking: activeSession != nil\)\)/);
  assert.match(source, /content:\s*\{\s*AnyView\(bookingTabContent\)/);
  // Chrome may wrap the erased root in body, or live inside the erased root.
  // Both preserve the scroll behavior and keep the heavy view tree isolated.
  const root = source.match(/private var bookingScrollRoot: AnyView\s*\{([\s\S]*?)\n    \}/)?.[1];
  const bodyPrefix = source.match(/\bvar body: some View\s*\{\s*(bookingScrollRoot[\s\S]*?)\.task\s*\{/)?.[1];
  assert.ok(root, 'bookingScrollRoot must remain an independently erased view');
  assert.ok(bodyPrefix, 'body must use bookingScrollRoot before starting its refresh task');
  const chrome = /\.modifier\(IumrahPrimaryTabScrollChrome\(\)\)/g;
  const chromeCount = [...root.matchAll(chrome), ...bodyPrefix.matchAll(chrome)].length;
  assert.equal(chromeCount, 1, 'booking scroll root must apply its chrome exactly once');
  assert.match(bodyPrefix, /^bookingScrollRoot\s*(?:\.modifier\(IumrahPrimaryTabScrollChrome\(\)\)\s*)?$/);
});

test('booking tab erases active and empty branches before inserting them into main VStack', () => {
  assert.match(source, /if let activeSession\s*\{\s*AnyView\(activeBookingHub\(activeSession\)\)/);
  assert.match(source, /else\s*\{\s*AnyView\(emptyBookingHome\)/);
});

test('booking progress/status/schedule are independent and do not construct inactive panels', () => {
  assert.match(source, /private func bookingPanelContent\(_ session: StoredBookingSession\) -> AnyView/);
  assert.match(source, /case \.booking:\s*return AnyView\(bookingProgress\(session\)/);
  assert.match(source, /case \.status:\s*return AnyView\(bookingStatusPanel\(session\)\)/);
  assert.match(source, /case \.schedule:\s*return AnyView\(\s*BookingItineraryCalendarView/);
  assert.match(source, /bookingFulfillmentCenter\(session, checkout: activeCheckout\)/);
  assert.match(source, /IumrahTelegramConnectCard\(/);
  assert.match(source, /NavigationLink \{\s*IumrahTelegramIntegrationView\(\)/);
  assert.match(source, /\.navigationDestination\(isPresented: \$showCareRequestBuilder\)/);
});
