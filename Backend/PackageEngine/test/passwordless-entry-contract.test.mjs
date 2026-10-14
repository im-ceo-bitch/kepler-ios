import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const backend = readFileSync(new URL('../src/client-account-security.ts', import.meta.url), 'utf8');
const base = new URL('../../../', import.meta.url);
const file = (relative) => readFileSync(new URL(relative, base), 'utf8');
const account = file('Sources/AppShell/IumrahAccountView.swift');
const booking = file('Sources/Views/Booking/PilgrimCheckoutView.swift');
const service = file('Sources/Services/IumrahAccountService.swift');
const models = file('Sources/Models/IumrahAccountModels.swift');
const bridge = file('Sources/Services/IumrahAccountActivationBridge.swift');

function between(source, begin, end) {
  const start = source.indexOf(begin);
  const stop = source.indexOf(end, start + begin.length);
  assert.ok(start >= 0 && stop > start, `Unable to inspect ${begin}`);
  return source.slice(start, stop);
}

test('email login requires a verified linked email and an activated account', () => {
  const start = between(backend, 'async function startEmailLogin(', 'async function confirmEmailLogin(');
  assert.match(start, /INNER JOIN iumrah_accounts/);
  assert.match(start, /e\.verified_at IS NOT NULL/);
  assert.doesNotMatch(start, /WHERE .*p\.email/i);
  assert.match(start, /createEmailChallenge/);
  assert.match(start, /audit\(db/);
});

test('email code verification binds challenge, account and email before session creation', () => {
  const confirm = between(backend, 'async function confirmEmailLogin(', 'async function linkVerifiedEmail(');
  assert.match(confirm, /e\.pilgrim_id=c\.pilgrim_id AND e\.email_normalized=c\.email_normalized/);
  assert.match(confirm, /e\.verified_at IS NOT NULL/);
  assert.match(confirm, /verifyEmailChallenge/);
  assert.match(confirm, /createAccountSession/);
  assert.match(confirm, /bindCurrentSession/);
  assert.match(confirm, /email_sign_in/);
});

test('registration and booking OTP confirmation create non-reusable random credentials when password omitted', () => {
  for (const func of [
    'confirmBookingEmailActivation','confirmBookingSMSActivation',
    'confirmStandaloneEmailRegistration','confirmStandalonePhoneRegistration',
  ]) {
    const segment = backend.slice(backend.indexOf(`async function ${func}(`),
      backend.indexOf('\nasync function ',backend.indexOf(`async function ${func}(`)+20));
    assert.match(segment, /payload\?\.password === undefined \? randomToken\(48\)/, func);
    assert.doesNotMatch(segment, /if \(!validPassword\(payload\?\.password\)\)/, func);
  }
  assert.match(backend, /async function loginWithPassword/);
});

test('iOS sends email and phone OTP without password and consumes verified auth session directly', () => {
  assert.match(service, /login\/email\/start/);
  assert.match(service, /login\/email\/confirm/);
  assert.match(service, /login\/sms\/start/);
  assert.match(service, /login\/sms\/confirm/);
  for (const request of [
    'IumrahEmailLoginConfirmRequest','IumrahPhoneRegistrationConfirmRequest',
    'IumrahAccountActivationEmailConfirmRequest','IumrahAccountActivationSMSConfirmRequest',
  ]) {
    const struct = between(models, `struct ${request}:`, '\n}');
    assert.doesNotMatch(struct, /let password:/, request);
  }
  assert.doesNotMatch(bridge, /let password: String/);
});

test('Account and booking flows provide only email/SMS entry, no password prompt or iumrah ID login', () => {
  const guest = between(account, 'private var guestSignInFields:', 'private var guestRegistrationFields:');
  const register = between(account, 'private var guestRegistrationFields:', 'private var unsupportedSMSNotice:');
  const checkout = between(booking, 'private func activationCard(', 'private var existingLoginChallengePending:');
  for (const view of [guest, register, checkout]) {
    assert.doesNotMatch(view, /accountPasswordField\(|passwordField\(|\$registrationPassword|\$loginPassword/);
    assert.doesNotMatch(view, /case \.iumrahID:/);
  }
  assert.doesNotMatch(account, /IumrahGuestAuthMethod\.iumrahID/);
  assert.doesNotMatch(booking, /IumrahActivationMethod\.iumrahID|IumrahCheckoutLoginMethod\.iumrahID/);
  assert.match(booking, /existingLoginEmailChallengeID/);
  assert.match(booking, /existingLoginSMSChallengeID/);
  assert.match(account, /acceptVerifiedSession/);
});
