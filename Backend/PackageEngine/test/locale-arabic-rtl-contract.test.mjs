import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const here = new URL('../', import.meta.url);
const read = p => fs.readFileSync(new URL(p, here), 'utf8');

test('Arabic is normalized from ar/ar-SA/ar_SA for the server booking itinerary', () => {
  const code = `
    import {buildBookingItinerary} from ${JSON.stringify(new URL('src/itinerary-planner.ts', here).href)};
    const booking = {
      input: {includeMadinah: false, flightTripType:'oneWay'},
      stay: {makkahNights:3, madinahNights:0},
      generatorTrace: {outbound: {origin:'TAS',destination:'JED',departureAt:'2026-11-10T10:00:00+05:00',arrivalAt:'2026-11-10T15:00:00+03:00'}}
    };
    for (const language of ['ar','ar-SA','ar_SA']) {
      const items = buildBookingItinerary('arabic-qa',booking,language).items;
      if (items.length<5 || items[0].title !== 'الوصول إلى المملكة العربية السعودية') throw new Error(language + JSON.stringify(items[0]));
    }
    console.log('ARABIC_ITINERARY_PASS');`;
  assert.match(execFileSync(process.execPath, ['--no-warnings','--experimental-strip-types','--input-type=module','-e',code], {encoding:'utf8'}),/ARABIC_ITINERARY_PASS/);
});

test('Arabic account email has Arabic copy and RTL document direction', () => {
  const src = read('src/client-account-security.ts');
  assert.match(src, /ar: \{\s*verify: "تأكيد البريد الإلكتروني/);
  assert.match(src, /primary === "ar"/);
  assert.match(src, /dir="\$\{accountEmailLocale\(locale\) === "ar" \? "rtl" : "ltr"\}"/);
});

test('selected Arabic app language controls iPhone widget strings and direction', () => {
  const src = fs.readFileSync(new URL('../../WidgetExtension/IumrahWidgets.swift',here),'utf8');
  assert.match(src,/if code\.hasPrefix\("ar"\) \{ return \.ar \}/);
  assert.match(src,/case \.ar: formatter\.locale = Locale\(identifier: "ar_SA"\)/);
  assert.match(src,/case \.ar: return arabicCopy\[en\] \?\? en/);
  assert.equal((src.match(/\.environment\(\\\.layoutDirection, IumrahWidgetL10n\.isArabic/g)||[]).length,5);
});
