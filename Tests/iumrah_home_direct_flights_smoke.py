#!/usr/bin/env python3
"""Compile the production projection with real DTOs on Linux; UI layout is static-checked."""
from pathlib import Path
import subprocess, tempfile
home=Path('Sources/Views/Home/HomeDashboardView.swift').read_text()
assert home.index('.id("journey-search")') < home.index('publishedFlightSection\n') < home.index('IumrahDashboardBalanceCard(compact: true)') < home.index('SmartConfiguratorHomeCard(onOpen: startNewSmart)')
assert home.count('publishedFlightSection\n') == 1
assert 'direction: 0, onAllFlights: openOfficialFlights' in home and 'direction: 1, onAllFlights: openOfficialFlights' in home
assert 'Продолжить выбор отеля' in home and 'showPublishedHotels = true' in home
assert 'IumrahGuidedFlightSelectionView()' in home and 'NuiteeJourneyHotelsView()' in home
source=Path('Sources/Views/Home/IumrahPublishedFlightCarousel.swift').read_text()
assert 'Прямые рейсы туда' in source and 'Прямые рейсы обратно' in source and 'Все авиабилеты' in source
assert 'onSelect: { select(flight) }' in source and 'ForEach(flights)' in source
assert 'SmartConfiguratorFlow(firstLaunch: true)' in Path('Sources/Views/RootView.swift').read_text()
start=source.index('    static func flatten(')
end=source.index('\n}\n\nstruct IumrahAllPublishedFlightBoard',start)
flatten=source[start:end]
assert 'ForEach(flights)' in source and 'flightBoard(allPublished: true)' in source
assert 'board.catalogComplete == true' in source
models=Path('Sources/Models/HotelStorefrontModels.swift').read_text()
leg=models[models.index('struct StorefrontFlightLeg:'):models.index('/// One independently selectable')]
board=models[models.index('struct StorefrontFlightBaseline:'):models.index('/// A locally composed')]
local=Path('Sources/Models/LocalJourneySelection.swift').read_text().split('struct LocalJourneyRoom:')[0].replace('var discoveryOffer: FlightDiscoveryOffer? = nil','')
main=local+'\n'+leg+'\n'+board+'\nstruct Projection {\n'+flatten+'''\n}
func leg(_ origin:String,_ destination:String,_ departure:String,_ stops:Int=0,_ cabin:String="economy") -> StorefrontFlightLeg { .init(airline:"HY",flightNumber:"123",airlineCode:"HY",origin:origin,destination:destination,departureAt:departure,arrivalAt:departure,durationMinutes:300,stops:stops,cabinClass:cabin) }
func option(_ id:String,_ a:StorefrontFlightLeg,_ b:StorefrontFlightLeg?=nil,_ currency:String="USD") -> StorefrontFlightOption { .init(id:id,kind:b == nil ? "one_way":"open_jaw",priority:100,currency:currency,travelerCount:2,totalFare:200,perTravelerFare:100,observedAt:"2026",outbound:a,inbound:b,baggage:nil) }
let rows=(0..<350).map { option("pub-\\($0)",leg($0 % 2 == 0 ? "TAS":"FEG","JED","2099-12-01T10:00:00Z",0,$0 % 2 == 0 ? "economy":"business")) }
let extra=[option("pair",leg("NMA","MED","2099-12-01T10:00:00Z"),leg("JED","NMA","2099-12-09T10:00:00Z")),option("return",leg("MED","SKD","2099-12-02T10:00:00Z")),option("nonusd",leg("BHK","MED","2099-12-03T10:00:00Z"),nil,"UZS"),option("connection",leg("TAS","JED","2099-12-01T10:00:00Z",1))]
let flights=Projection.flatten(rows+extra+[rows[0]])
precondition(flights.count == 354)
precondition(Set(flights.map(\\.id)).count == 354)
precondition(flights.contains{$0.origin == "FEG" && $0.publishedCabin == "business"})
precondition(flights.filter{$0.publishedID == "pair"}.count == 2)
precondition(flights.first{$0.publishedID == "nonusd"}!.displayedPrice == nil)
precondition(!flights.contains{$0.publishedID == "connection"})
let old=StorefrontFlightBoardResponse(ok:true,origin:"TAS",generatedAt:"2026",baseline:nil,options:rows)
let decoded=try JSONDecoder().decode(StorefrontFlightBoardResponse.self,from:JSONEncoder().encode(old))
precondition(decoded.catalogComplete == nil)
print("PASS: 354 distinct legs, all airports/cabins/directions, paired IDs, currency, legacy response")
'''
with tempfile.TemporaryDirectory() as d:
    src=Path(d)/'main.swift'; src.write_text(main)
    subprocess.run(['swiftc',str(src),'-o',str(Path(d)/'check')],check=True)
    subprocess.run([str(Path(d)/'check')],check=True)
