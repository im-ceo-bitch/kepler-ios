import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const root = new URL("../../../", import.meta.url);
const journey = fs.readFileSync(new URL("Sources/State/JourneyStore.swift", root), "utf8");
const store = fs.readFileSync(new URL("Sources/State/HotelStorefrontStore.swift", root), "utf8");
const models = fs.readFileSync(new URL("Sources/Models/HotelStorefrontModels.swift", root), "utf8");
const home = fs.readFileSync(new URL("Sources/Views/Tabs/HotelsHomeView.swift", root), "utf8");
const compat = fs.readFileSync(new URL("Sources/Views/Tabs/HotelStorefrontCompatibility.swift", root), "utf8");
const primary = fs.readFileSync(new URL("Sources/Views/Hotels/PrimaryHotelView.swift", root), "utf8");
const imageCache = fs.readFileSync(new URL("Sources/Services/HotelImageCache.swift", root), "utf8");
const hotelCard = fs.readFileSync(new URL("Sources/Views/Components/HotelCard.swift", root), "utf8");
const finalPackage = fs.readFileSync(new URL("Sources/Views/Package/FinalPackageView.swift", root), "utf8");
const bookingDetail = fs.readFileSync(new URL("Sources/Views/Booking/BookingDetailView.swift", root), "utf8");
const flightDiscovery = fs.readFileSync(new URL("Sources/Views/Flights/IumrahFlightDiscoveryView.swift", root), "utf8");

test("Primary Hotel selection resolves the Business editorial slot before factual-star fallback", () => {
  assert.match(journey, /resolvedPrimaryHotel\(from: all, city: "Makkah"\)/);
  assert.match(journey, /resolvedPrimaryHotel\(from: all, cityAliases: aliases\)/);
  const makkahBlock = journey.slice(journey.indexOf("func loadMakkahHotels"), journey.indexOf("func loadMadinahHotels"));
  const madinahBlock = journey.slice(journey.indexOf("func loadMadinahHotels"), journey.indexOf("private func resolvedPrimaryHotel"));
  assert.doesNotMatch(makkahBlock, /primaryCandidates/);
  assert.doesNotMatch(madinahBlock, /primaryCandidates/);
  assert.match(madinahBlock, /"Madinah", "Medina", "Madina", "Medinah"/);
});

test("Flights Scanner composes short Comfort and 4-15 day Standard packages from regional Uzbekistan departures", () => {
  assert.match(models, /enum StorefrontUmrahPackageKind/);
  assert.match(models, /case makkahComfortShort/);
  assert.match(models, /case makkahMadinahStandard/);
  assert.match(store, /preferredNames: \["Nawazi Hotel", "Nawazi Watheer Hotel"\]/);
  assert.match(store, /preferredNames: \["Mihrab Tayyiba", "Mihrab Tayba", "Mihrab Taiba"\]/);
  assert.match(store, /preferredNames: \["Shohada Hotel", "Al Shohada Hotel", "Shuhada Hotel", "Al Shuhada Hotel"\]/);
  assert.match(store, /\(2\.\.\.3\)\.contains\(gapDays\)/);
  assert.match(store, /\(4\.\.\.15\)\.contains\(gapDays\)/);
  assert.match(store, /returnDestination: preferredDestination/);
  assert.match(store, /returnDestination: "TAS"/);
  assert.match(store, /output\[pair\.returnOptionID\] == nil/);
  assert.match(store, /trip\.packageTier = \.comfort/);
  assert.match(store, /trip\.packageTier = \.standard/);
  assert.match(store, /trip\.adults = 1/);
  assert.match(store, /packageEngine\.packageQuote\(/);
  assert.doesNotMatch(store, /LocalPackagePricingEngine\.calculate\(/);
  assert.match(store, /TripStayPlanner\.breakdown/);
});

test("Flights discovery uses the new search form and routes to real supplier-backed results", () => {
  assert.match(home, /case \.flights: flightFields/);
  assert.match(home, /IumrahGuidedFlightSelectionView\(\)/);
  assert.match(home, /journey\.trip\.flightFilters = filters/);
  assert.match(home, /flightResultsPresented = true/);
  assert.match(home, /NuiteeHotelsCatalogView\(/);
  assert.match(home, /manualQuoteRequired/);
  assert.doesNotMatch(home, /private var flightsBoard/);
  assert.match(compat, /struct StorefrontFlightOptionCard/);
  assert.match(flightDiscovery, /FlightDiscoveryPriceGraphSheet/);
  assert.match(flightDiscovery, /CuratedFlightRecommendationService/);
});

test("panoramic hotel photos are constrained by the card viewport and the meal UI remains intact", () => {
  assert.match(imageCache, /GeometryReader \{ proxy in/);
  assert.match(imageCache, /frame\(width: proxy\.size\.width, height: proxy\.size\.height\)/);
  // Accept both algebraically identical Swift spellings: with or without the
  // optional grouping parentheses around horizontal page padding. The contract
  // is the viewport-constrained card width, not the source's exact typography.
  assert.match(primary, /let contentWidth\s*=\s*max\(\s*0\s*,\s*viewport\.size\.width\s*-\s*(?:\(\s*IumrahDesign\.pagePadding\s*\*\s*2\s*\)|IumrahDesign\.pagePadding\s*\*\s*2)\s*\)/);
  assert.match(primary, /frame\(width: contentWidth, alignment: \.leading\)/);
  assert.match(primary, /HotelCachedImage\(rawURL: hotel\.coverImageURL\)/);
  assert.match(primary, /mealPlanCard\(role: role\)/);
  assert.match(primary, /frame\(maxWidth: \.infinity, alignment: \.leading\)/);
  assert.match(hotelCard, /HotelCachedImage\(rawURL: hotel\.coverImageURL\)/);
  assert.match(finalPackage, /PackageHotelDetailCard\(/);
  assert.match(compat, /HotelCachedImage\(rawURL: imageURL\)/);
  assert.match(bookingDetail, /HotelCachedImage\(/);
  assert.match(finalPackage, /mealCount\(\.makkah\)/);
  assert.match(finalPackage, /mealCount\(\.madinah\)/);
});
