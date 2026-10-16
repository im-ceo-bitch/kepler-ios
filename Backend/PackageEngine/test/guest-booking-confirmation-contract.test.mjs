import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = new URL('../../../', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const screen = read('Sources/Views/Booking/IumrahBookingConfirmationView.swift');
const service = read('Sources/Services/IumrahBookingContactService.swift');
const backend = read('Backend/PackageEngine/src/booking-contact-verification.ts');
const index = read('Backend/PackageEngine/src/index.ts');
const migration = read('Backend/PackageEngine/migrations/0008_devsms_phone_verification.sql');

test('all three booking entry points use a full navigation page and never a profile sheet', () => {
  for (const path of [
    'Sources/Views/Booking/BookingCheckoutView.swift',
    'Sources/Views/Package/FinalPackageView.swift',
    'Sources/Views/Tabs/HotelsHomeView.swift',
  ]) {
    const source = read(path);
    assert.match(source, /navigationDestination\(isPresented: \$isProfileSheetPresented\)|navigationDestination\(isPresented: \$showProfileSheet\)/);
    assert.match(source, /IumrahBookingConfirmationView\(createBooking:/);
    assert.doesNotMatch(source, /BookingProfileCaptureSheet/);
  }
});

test('guest SMS confirmation precedes booking creation and no login or account creation is involved', () => {
  const confirmIndex = screen.indexOf('verificationService.confirmCode(challengeID: challengeID');
  const bookingIndex = screen.indexOf('session = try await createBooking(profile)');
  const attachIndex = screen.indexOf('verificationService.attachVerifiedPhone(');
  assert.ok(confirmIndex >= 0 && confirmIndex < bookingIndex && bookingIndex < attachIndex);
  assert.match(screen, /firstName: firstName\.trimmingCharacters/);
  assert.match(screen, /lastName: lastName\.trimmingCharacters/);
  assert.ok(screen.includes('998[0-9]{9}'));
  assert.match(screen, /LoopingVideoView\(resource: "iumrah-security-identity"/);
  assert.match(screen, /settings\.phone = confirmedPhone/);
  assert.doesNotMatch(screen, /startPhoneRegistration|confirmPhoneLogin|password:/);
  assert.match(screen, /let savedBooking \{ session = savedBooking \}/); // no duplicate on retry
});

test('Telegram opt-in appears after phone verification on the booking success screen', () => {
  assert.match(screen, /if isFinished, let savedBooking/);
  assert.match(screen, /IumrahTelegramConnectCard\(session: session, style: \.standard\)/);
  assert.match(screen, /checkmark\.seal\.fill/);
  assert.match(screen, /noPaymentNotice/);
  assert.match(screen, /passportWarning/);
});

test('guest OTP uses DevSMS with bounded attempts, single use proof and authenticated booking attachment', () => {
  assert.match(service, /booking-contact\/sms\/start/);
  assert.match(service, /booking-contact\/sms\/confirm/);
  assert.match(service, /x-booking-token/);
  assert.match(backend, /SMS_RATE_LIMITED/);
  assert.match(backend, /attempts>=5|Number\(row\.attempts\) >= 5/);
  assert.match(backend, /verified_at IS NULL/);
  assert.match(backend, /verification_token_hash/);
  assert.match(backend, /attachVerifiedBookingPhone/);
  assert.match(backend, /SMS_DELIVERY_UNAVAILABLE/);
  assert.match(index, /handleGuestBookingPhone\(request, env, url\)/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS iumrah_guest_booking_phone_challenges/);
});
