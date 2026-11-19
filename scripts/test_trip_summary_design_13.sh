#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func component(_ code: String, _ value: String) -> TripSummaryPublicPrice.Component {
    .init(code: code, label: code, amountUsd: Decimal(string: value)!, cancellationPolicy: nil)
}
func check(_ ok: Bool, _ name: String) { precondition(ok,name); print("PASS: " + name) }
let components = [component("flight_outbound","656"), component("flight_inbound","654"),component("makkah_hotel","363.46"),component("madinah_hotel","637.29"),component("visa","240"),component("meal_makkah_makkah:0_breakfast","180"),component("meal_makkah_makkah:0_lunch","180"),component("meal_makkah_makkah:0_dinner","180"),component("meal_madinah_madinah:0_breakfast","90"),component("meal_madinah_madinah:0_dinner","90"),component("transfers","568.19"),component("accompaniment","400"),component("ziyarat_makkah","100"),component("ziyarat_madinah","100")]
let groups = TripReviewPriceGrouping.groups(components)
check(groups.map(\.key) == ["flights","makkah_hotel","madinah_hotel","visa","meals","transfer","accompaniment","ziyarats"],"approved order and eight compact component rows")
check(groups.first { $0.key == "meals" }?.amount == 720,"all five room-meal amounts combined")
check(groups.first { $0.key == "flights" }?.amount == 1310,"flight legs combined")
check(groups.first { $0.key == "ziyarats" }?.amount == 200,"both ziyarat programs combined")
check(groups.reduce(Decimal.zero) { $0 + $1.amount } == Decimal(string:"4438.94")!,"grouping preserves every cent")
check(groups.reduce(Decimal.zero) { $0 + $1.amount } + Decimal(string:"399.50")! + Decimal(string:"98.80")! + Decimal(string:"2.76")! == 4940,"screenshot total reconciles")
let addon = TripReviewPriceGrouping.groups([component("transfers","300"),component("vip_transfer_upgrade","750"),component("haramain_train_addon","100")])
check(addon.count == 2 && addon[0].amount == 1050 && addon[1].amount == 100,"VIP grouped, Haramain remains separate")
check(TripReviewPriceGrouping.key("future_service") == "future_service","unknown services are not discarded")
SWIFT
swiftc Sources/FlightEngine/FlightSearchRequest.swift Sources/Models/FlightModels.swift Sources/FlightEngine/FlightReferenceCatalog.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/Views/Package/FinalPackageView.swift').read_text()
price=s.split('var priceBreakdownCard: some View {',1)[1].split('var chartCard:',1)[0]
checks={
 'flat price rows without disclosure': 'disclosure(' not in price and 'ForEach(displayPriceRows(price))' in price,
 'both fees and rounding stay visible': all(x in price for x in ['supportAmountUsd','paymentAmountUsd','roundingUsd','summaryPricePair()']),
 'hero image and gradient': 'Image("AboutIumrahKaabaCorner")' in s and 'LinearGradient(colors:' in s,
 'chart separated from price list': 'case .chart: return AnyView(chartCard)' in s,
 'one compact booking bar and actual action': 'Button(copy("Забронировать", "Book"' in s and 'if canBook { isProfileSheetPresented = true; return }' in s,
 'save and share connected to actual server function': 'requestSave(share: true)' in s and 'await saveCurrentPackage()' in s and 'TripSummarySavedClient.save' in s,
 'flight, hotel and vehicle edit sessions retained': all(x in s for x in ['capsuleAction(changeTitle)', 'TripSummaryEditSession(kind: .flights','TripSummaryEditSession(kind: .hotel(city)','TripSummaryEditSession(kind: .transfer']),
 'capsules minimum tap size and disabled appearance': 'minHeight: 44' in s and '.opacity(!isEnabled ? 0.45' in s,
 'real price and quote validation retained': 'price.reconciles(with: quote.totalPackagePrice)' in s,
}
for k,v in checks.items(): print(('PASS: ' if v else 'FAIL: ')+k)
assert all(checks.values())
PY
