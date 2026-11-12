import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const root = new URL("../../../", import.meta.url);
const journey = fs.readFileSync(new URL("Sources/State/JourneyStore.swift", root), "utf8");
const finalPackage = fs.readFileSync(new URL("Sources/Views/Package/FinalPackageView.swift", root), "utf8");
const pricing = fs.readFileSync(new URL("Backend/PackageEngine/src/pricing.ts", root), "utf8");

const comparisonBuilder = journey.slice(
  journey.indexOf("func buildPackageTierComparisons"),
  journey.indexOf("private func returnOffer")
);

const comparisonPricing = journey.slice(
  journey.indexOf("private func makePackageTierComparisonOption"),
  journey.indexOf("private func comparisonMakkahCatalog")
);

test("final package comparison keeps the exact selected flight itinerary and fare source", () => {
  assert.match(comparisonBuilder, /guard let outbound = selectedOutbound, outbound\.isVerifiedForBooking/);
  assert.match(comparisonBuilder, /guard let value = selectedInbound/);
  assert.match(comparisonBuilder, /returnPairMatches\(value, outbound: outbound\)/);
  assert.match(journey, /private func returnPairMatches[\s\S]*?packageFlightPath == \.aviasalesSelected[\s\S]*?return returnOffer\(inbound, matches: outbound\)/);
  assert.match(comparisonBuilder, /pricingOffer = value/);
  assert.match(comparisonBuilder, /pricingOffer = outbound/);
  assert.doesNotMatch(comparisonBuilder, /LocalFXRateService\.shared\.usd/);
  assert.match(comparisonPricing, /packageEngine\.packageQuote\(/);
  assert.match(comparisonPricing, /pricingOffer: flight\.pricingOffer/);
  assert.match(comparisonPricing, /outboundOffer: flight\.outboundOffer/);
  assert.match(comparisonPricing, /inboundOffer: flight\.inboundOffer/);
});

test("comparison hotel policy uses the agreed named hotels and Business Primary Hotel economy fallback", () => {
  assert.match(comparisonBuilder, /"Nawazi Hotel", "Nawazi Watheer Hotel"/);
  assert.match(comparisonBuilder, /"Mihrab Tayyiba", "Mihrab Tayba", "Mihrab Taiba"/);
  assert.match(comparisonBuilder, /"Shohada Hotel", "Al Shohada Hotel", "Shuhada Hotel", "Al Shuhada Hotel"/);
  assert.match(comparisonBuilder, /"Address Jabal Omar Makkah", "Address Jabal Omar", "Jabal Omar Address"/);
  assert.match(comparisonBuilder, /"Pullman Zamzam Madina", "Pullman Zamzam Madinah", "Pullman Zamzam"/);
  assert.match(comparisonBuilder, /if let policy = comparisonHotelPolicy\(for: tier, city: city\) \{[\s\S]*?return fixedComparisonHotel\(/);
  assert.match(comparisonBuilder, /let requestedStars = \[2, 1\]/);
  assert.match(comparisonBuilder, /packageEngine\.primaryHotel\(tier: tier, stars: stars, city: city\)/);
});

test("comparison recomputes hotel room nights but does not silently add Luxury Yukon or paid Comfort-Luxury meals", () => {
  assert.match(comparisonPricing, /trip: comparisonTrip/);
  assert.match(comparisonPricing, /makkahHotelID: makkahHotel\.id/);
  assert.match(comparisonPricing, /madinahHotelID: madinahHotel\?\.id/);
  assert.match(comparisonPricing, /makkahLunch: false/);
  assert.match(comparisonPricing, /makkahDinner: false/);
  assert.match(comparisonPricing, /madinahDinner: false/);
  assert.match(comparisonPricing, /transferVehicle: selectedTransferVehicle/);
  assert.doesNotMatch(comparisonPricing, /transferVehicle:\s*\.yukon/);
  assert.doesNotMatch(comparisonPricing, /selectedTransferVehicle\s*=\s*\.yukon/);
  assert.match(pricing, /const LUXURY_MARKUP = 0\.35/);
  assert.match(pricing, /input\.tier === "luxury" \? LUXURY_MARKUP : STANDARD_MARKUP/);
});

test("current package review preserves server pricing, flight detail and an explicit booking action", () => {
  // Package-tier comparisons still have their own price-policy tests above;
  // the current checkout intentionally uses a single server-confirmed journey
  // instead of the old carousel and routes local journeys through a wrapper.
  assert.match(finalPackage, /if journey\.usesLocalJourney \{ LocalJourneyReviewView\(\) \}/);
  assert.match(finalPackage, /LegacyFinalPackageView\(familyFlow: familyFlow\)/);
  assert.match(finalPackage, /IumrahJourneyHeader\(showsNotifications: true\)/);
  assert.match(finalPackage, /PackageFlightLegDetailCard\(leg: flightLeg\(outbound\)/);
  assert.match(finalPackage, /PackageFlightLegDetailCard\(leg: flightLeg\(inbound\)/);
  assert.match(finalPackage, /PackageHotelDetailCard\(/);
  assert.match(finalPackage, /journey\.hasFinalGeneratorQuote/);
  assert.match(finalPackage, /journey\.quote\?\.bookingAllowed != false/);
  assert.match(finalPackage, /Text\(totalText\)/);
  assert.match(finalPackage, /Text\(tr\("Забронировать поездку"/);
  assert.match(finalPackage, /\.disabled\(!canBook \|\| isSubmitting\)/);
});
