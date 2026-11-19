#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
r=Path('Sources')
s=(r/'Views/Home/IumrahPublishedFlightCarousel.swift').read_text()
core=s[s.index('@MainActor final class'):s.index('struct IumrahPublishedFlightCarousel: View')]+s[s.index('@MainActor final class IumrahHomePublishedSelection'):]
local=(r/'Models/LocalJourneySelection.swift').read_text().split('struct LocalJourneyRoom')[0].replace('import Foundation','')
curated=(r/'Models/CuratedFlightRecommendationModels.swift').read_text().replace('import Foundation','')
staged=(r/'Models/TripModels.swift').read_text().split('enum PackageFlightPath')[0].replace('import Foundation','')
stubs='''import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct FlightDiscoveryOffer: Codable, Hashable {}
enum FlightCabinClass: String { case economy, business }
struct Filters { var cabinClass = FlightCabinClass.economy }
enum JourneyScope { case makkahOnly, makkahAndMadinah }
enum SaudiArrivalAirport: String { case jeddah = "JED", madinah = "MED" }
enum TripType { case roundTrip }
enum Flexibility { case exact }
enum PackageFlightPath { case publishedDirect }
struct TripDraft { var originCode = "TAS"; var scope = JourneyScope.makkahAndMadinah; var arrivalAirport = SaudiArrivalAirport.madinah; var selectedReturnAirport: SaudiArrivalAirport?; var departureDate = Date(); var returnDate = Date().addingTimeInterval(864000); var saudiArrivalDate: Date?; var flightTripType = TripType.roundTrip; var flexibility = Flexibility.exact; var effectiveFlightFilters = Filters(); var outboundDestinationCode: String { scope == .makkahOnly ? "JED" : arrivalAirport.rawValue }; var returnOriginCode: String { selectedReturnAirport?.rawValue ?? (scope == .makkahOnly || arrivalAirport == .madinah ? "JED" : "MED") }; var canContinue: Bool { returnDate > departureDate } }
@MainActor final class JourneyStore { var trip = TripDraft(); var localJourneyFlights:[LocalJourneyFlight]=[]; var staged:[StagedUmrahFlight]=[]; var usesLocalJourney=false; var packageFlightPath = PackageFlightPath.publishedDirect; var selectedPublishedCompleteID:String?; var selectedPublishedOutboundID:String?; var selectedPublishedReturnID:String?; var resets=0; var hasCompleteStagedFlightSelection:Bool { staged.count == 2 || staged.first?.kind == .roundTrip }; func resetAfterTripChange(){ resets += 1; localJourneyFlights=[]; selectedPublishedCompleteID=nil; selectedPublishedOutboundID=nil; selectedPublishedReturnID=nil }; func clearStagedUmrahFlights(){staged=[];trip.selectedReturnAirport=nil}; func stageUmrahFlight(_ f:StagedUmrahFlight){staged.append(f)}; func prepareFlightFirstHotelStage(){} }
enum IumrahFlightClock { static func local(_ s:String,airport:String)->String { s } }
enum IumrahHaptics { static func selection() {} }
@MainActor final class CuratedFlightRecommendationService { static let shared=CuratedFlightRecommendationService(); var result:[CuratedFlightRecommendation]=[]; var calls=0; func load(trip:TripDraft,from:Date,days:Int,force:Bool=false) async throws -> [CuratedFlightRecommendation]{ calls+=1; try? await Task.sleep(nanoseconds: 10_000_000); return result } }
'''
tests='''
func check(_ yes:Bool,_ name:String) { precondition(yes,name); print("PASS: "+name) }
func future(_ offset:Int)->String { let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.locale=Locale(identifier:"en_US_POSIX");return f.string(from:Calendar.current.date(byAdding:.day,value:offset,to:Date())!) + "T12:00:00" }
func leg(_ a:String,_ b:String,_ offset:Int,_ number:String,stops:Int=0)->CuratedFlightRecommendation.Leg { .init(airline:"Test",flightNumber:number,airlineCode:"TT",origin:a,destination:b,departureAt:future(offset),arrivalAt:future(offset),durationMinutes:120,stops:stops,cabinClass:"economy") }
func row(_ id:String,_ a:CuratedFlightRecommendation.Leg,_ b:CuratedFlightRecommendation.Leg?=nil,price:Double?=200)->CuratedFlightRecommendation { .init(id:id,outboundDate:a.departureAt,inboundDate:b?.departureAt,cabinClass:"economy",airlineCodes:[],airlineNames:[],flightNumbers:[],observedAt:"",outbound:a,inbound:b,nonstop:true,recommendationLabel:"",offerType:nil,journeyRole:nil,fareUsdPerTraveler:price) }
@MainActor func run() async {
 let svc=CuratedFlightRecommendationService.shared
 let a=leg("TAS","MED",3,"100"), b=leg("JED","TAS",8,"200"), early=leg("JED","TAS",4,"201")
 svc.result=[row("out",a),row("back",b),row("early",early),row("pair",a,b),row("other",leg("TAS","JED",3,"300")),row("unpriced",a,price:nil),row("connecting",leg("TAS","MED",3,"400",stops:1))]
 let catalog=IumrahPublishedCarouselCatalog.shared, journey=JourneyStore(), selection=IumrahHomePublishedSelection()
 async let first:Void = catalog.load(journey.trip); async let second:Void = catalog.load(journey.trip); _ = await(first,second)
 check(svc.calls==1,"concurrent loads coalesced")
 await catalog.load(journey.trip); check(svc.calls==1,"reopening uses cached publications")
 let outs=catalog.flights(journey.trip,direction:0,selected:nil,other:nil)
 check(outs.count==2,"direct route and priced published-only filtering")
 let out=outs.first{$0.publishedID=="out"}!, pairOut=outs.first{$0.publishedID=="pair"}!
 check(selection.choose(out,direction:0,journey:journey),"outbound selection accepted")
 check(!selection.complete && selection.inbound==nil,"outbound does not auto-select return")
 check(Calendar.current.isDate(journey.trip.departureDate,inSameDayAs:IumrahPublishedCarouselCatalog.day(a.departureAt,a.origin)!),"search departure date updated")
 let backs=catalog.flights(journey.trip,direction:1,selected:nil,other:out)
 check(backs.count==1 && backs[0].publishedID=="back","reject early and incompatible paired return")
 check(selection.choose(backs[0],direction:1,journey:journey) && selection.complete,"manual return makes pair complete")
 check(Calendar.current.isDate(journey.trip.returnDate,inSameDayAs:IumrahPublishedCarouselCatalog.day(b.departureAt,b.origin)!),"search return date updated")
 check(selection.commit(journey) && journey.selectedPublishedOutboundID=="out" && journey.selectedPublishedReturnID=="back" && journey.localJourneyFlights.count==2,"canonical IDs and local legs transferred to hotel flow")
 check(selection.commit(journey) && journey.resets==1,"unchanged pair does not reset hotel selections")
 check(selection.choose(pairOut,direction:0,journey:journey) && selection.inbound==nil,"changing to paired publication invalidates incompatible return")
 let pairBacks=catalog.flights(journey.trip,direction:1,selected:nil,other:pairOut)
 check(pairBacks.count==1 && pairBacks[0].publishedID=="pair","paired fare uses exact publication ID")
 check(selection.choose(pairBacks[0],direction:1,journey:journey) && selection.commit(journey) && journey.selectedPublishedCompleteID=="pair" && journey.staged.count==1,"paired fare staged once without double charge")
 journey.trip.originCode="SKD"; selection.reconcile(journey.trip); check(!selection.complete && selection.outbound==nil,"route edit invalidates prior selection")
}
await run()
'''
Path(sys.argv[1]).write_text(stubs+'\n'+local+'\n'+curated+'\n'+staged+'\n'+core+'\n'+tests)
PY
swiftc -swift-version 5 "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
python3 - <<'PY'
from pathlib import Path
r=Path('Sources'); home=(r/'Views/Home/HomeDashboardView.swift').read_text(); b=(r/'Views/Home/IumrahBrandExperience.swift').read_text(); c=(r/'Views/Home/IumrahPublishedFlightCarousel.swift').read_text(); root=(r/'Views/RootView.swift').read_text(); chrome=(r/'Core/Components/IumrahSignatureChrome.swift').read_text(); hotels=(r/'Views/Tabs/HotelsHomeView.swift').read_text()
checks={
'home section ordering':home.index('publishedFlightSection\n')<home.index('WhyIumrahCarousel(onPrimary:')<home.index('IumrahMissionCard()')<home.index('HomeRecentActivitySection(resumeSmart:'),
'original moving border enabled':'.modifier(IumrahAnimatedSearchBorder(forceOnEfficiency: true))' in chrome and 'AngularGradient' in chrome and 'animate: false' not in chrome,
'no auto-switch when choosing flight':'publishedDirection = $0' in home and home.count('publishedDirection = ')==2,
'both continuation CTAs wired': 'onContinue: continuePublishedFlights' in home and 'action: continuePublishedFlights' in home and 'NuiteeJourneyHotelsView()' in home,
'published-only carousel': 'CuratedFlightRecommendationService.shared.load' in c and 'AviasalesFlightDiscoveryService' not in c and 'isAviasales: false' in c,
'independent tap and check': 'onSelect: { onSelect(flight) }, action: { onOpen(flight) }' in c,
'flight tab carousel': 'IumrahPublishedFlightCarousel(trip: browseTrip' in hotels,
'eight approved marketing slides': all(f'.init(id:{i},label:' in b for i in range(8)),
'brand slogan exact': 'Ближе к своим близким. Ближе к поклонению.' in b and 'IumrahWorldDotsHeaderBackground' in b,
'comparison and first-run onboarding': 'struct WhyIumrahView' in b and 'struct IumrahWelcomeOnboarding' in b and 'IumrahWelcomeOnboarding {' in root and 'ForEach(0..<6)' in b,
'booking CTA goes through normal validation': 'case .why: return AnyView(WhyIumrahCarousel' in (r/'Views/Package/FinalPackageView.swift').read_text() and 'onPrimary: { handleBookTap() }' in (r/'Views/Package/FinalPackageView.swift').read_text(),
'account and care slogan': all('IumrahSloganCard()' in (r/f).read_text() for f in ['AppShell/IumrahAccountView.swift','Views/Tabs/CareHomeView.swift']),
}
for name,ok in checks.items():print(('PASS' if ok else 'FAIL')+': '+name)
assert all(checks.values())
PY
