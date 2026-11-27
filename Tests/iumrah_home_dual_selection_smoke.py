#!/usr/bin/env python3
"""Compile the production selection/compatibility methods with real trip and flight DTOs.
JourneyStore staging is mocked; actual iOS navigation/rendering requires Xcode.
"""
from pathlib import Path
import subprocess, tempfile
read=lambda f:Path(f).read_text()
source=read('Sources/Views/Home/IumrahPublishedFlightCarousel.swift')
clock=read('Sources/Views/Flights/IumrahFlightResultCard.swift')
clock=clock[clock.index('enum IumrahFlightClock {'):clock.index('struct IumrahFlightFilterState:')]
helpers=source[source.index('    static func day('):source.index('\n}\n\nstruct IumrahPublishedFlightCarousel')]
selection=source[source.index('@MainActor final class IumrahHomePublishedSelection'):source.index('// Home discovery keeps')].replace('@MainActor final class IumrahHomePublishedSelection: ObservableObject','final class IumrahHomePublishedSelection').replace('@Published ','')
classifiers=source[source.index('    nonisolated static func direction('):source.index('    func visibleFlights(')] + source[source.index('    nonisolated static func isFuture('):source.index('    static func flatten(')]
classifiers=classifiers.replace('nonisolated static','static')
ranking=source[source.index('    static func prioritized('):source.index('    func prioritizedFlights(')]
local=read('Sources/Models/LocalJourneySelection.swift').split('struct LocalJourneyRoom:')[0].replace('var discoveryOffer: FlightDiscoveryOffer? = nil','')
filters=read('Sources/FlightEngine/FlightSearchRequest.swift').split('/// Provider-neutral request')[0]
base=read('Sources/Services/AirportMapBootstrapCatalog.swift')
base=base[:base.index('    static var points:')]+base[base.index('    static func airport(code:'):]
mock='''import Foundation
struct AppSettingsStore { enum Language { case english } }
enum L10n { static func text(_ key:String,_ language:AppSettingsStore.Language)->String { key } }
enum IumrahHaptics { static func selection() {} }
final class JourneyStore {
 var trip = TripDraft()
 var localJourneyFlights: [LocalJourneyFlight] = []
 var staged: [StagedUmrahFlight] = []
 var packageFlightPath: PackageFlightPath = .publishedDirect
 var selectedPublishedCompleteID: String?
 var selectedPublishedOutboundID: String?
 var selectedPublishedReturnID: String?
 var usesLocalJourney = false
 var resetCount = 0
 var hotelStageCount = 0
 var hasCompleteStagedFlightSelection: Bool { staged.contains{$0.kind == .roundTrip} || (staged.contains{$0.kind == .outbound} && staged.contains{$0.kind == .inbound}) }
 func resetAfterTripChange() { resetCount += 1; localJourneyFlights=[]; selectedPublishedCompleteID=nil; selectedPublishedOutboundID=nil; selectedPublishedReturnID=nil; trip.saudiArrivalDate=nil }
 func clearStagedUmrahFlights() { staged=[]; trip.selectedReturnAirport=nil }
 func stageUmrahFlight(_ f:StagedUmrahFlight) { staged.append(f) }
 func prepareFlightFirstHotelStage() { hotelStageCount += 1 }
}
'''
test=r'''
func flight(_ id:String,_ origin:String,_ destination:String,_ day:String,_ cabin:String="economy",_ pair:String?=nil,_ price:Double?=200)->LocalJourneyFlight {
 .init(id:id,origin:origin,destination:destination,airline:"HY",flightNumber:"HY 123",airlineCode:"HY",durationMinutes:300,stops:0,departureAt:day+"T10:00:00Z",arrivalAt:day+"T15:00:00Z",displayedPrice:price,publishedID:pair ?? id,publishedIsPair:pair != nil,publishedCabin:cabin)
}
let a=flight("a","FEG","MED","2099-12-01","business")
let b=flight("b","JED","FEG","2099-12-10","business")
let wrong=flight("wrong","JED","TAS","2099-12-10","business")
let early=flight("early","JED","FEG","2099-12-01","business")
let wrongClass=flight("wrongClass","JED","FEG","2099-12-11")
let expired=flight("expired","TAS","JED","2000-01-01")
let noPrice=flight("noprice","FEG","JED","2099-12-10","business",nil,nil)
precondition(IumrahAllPublishedFlightStore.direction(of:a)==0)
precondition(IumrahAllPublishedFlightStore.direction(of:b)==1)
precondition(!IumrahAllPublishedFlightStore.isFuture(expired))
let j=JourneyStore(); j.trip.scope = .makkahOnly; j.trip.adults=3; j.trip.rooms=2
let sel=IumrahHomePublishedSelection()
precondition(sel.choose(a,direction:0,journey:j)); sel.reconcile(j.trip)
precondition(j.trip.originCode=="FEG" && j.trip.scope == .makkahAndMadinah && j.trip.arrivalAirport == .madinah && j.trip.effectiveFlightFilters.cabinClass == .business)
precondition(j.trip.adults==3 && j.trip.rooms==2 && sel.outbound==a)
for bad in [wrong,early,wrongClass,noPrice] { precondition(!sel.choose(bad,direction:1,journey:j)); precondition(sel.outbound==a && sel.inbound==nil) }
precondition(sel.choose(b,direction:1,journey:j)); sel.reconcile(j.trip)
precondition(sel.complete && sel.commit(j)); sel.reconcile(j.trip)
precondition(j.selectedPublishedOutboundID=="a" && j.selectedPublishedReturnID=="b" && j.staged.count==2 && j.hotelStageCount==1 && j.usesLocalJourney && j.localJourneyFlights==[a,b])
precondition(sel.commit(j) && j.hotelStageCount==1 && j.resetCount==1)
precondition(sel.choose(a,direction:0,journey:j) && sel.outbound==nil && sel.inbound==b)
let reverse=IumrahHomePublishedSelection(); let j2=JourneyStore()
precondition(reverse.choose(b,direction:1,journey:j2)); reverse.reconcile(j2.trip)
precondition(reverse.choose(a,direction:0,journey:j2)); reverse.reconcile(j2.trip)
precondition(reverse.complete && reverse.commit(j2))
let pa=flight("pa","TAS","JED","2099-12-01","economy","pair")
let pb=flight("pb","MED","TAS","2099-12-10","economy","pair")
let other=flight("other","MED","TAS","2099-12-11","economy","different")
let j3=JourneyStore(); let paired=IumrahHomePublishedSelection()
precondition(paired.choose(pa,direction:0,journey:j3)); precondition(!paired.choose(other,direction:1,journey:j3))
precondition(paired.choose(pb,direction:1,journey:j3) && paired.commit(j3))
precondition(j3.selectedPublishedCompleteID=="pair" && j3.selectedPublishedOutboundID==nil && j3.staged.count==1 && j3.staged.first?.kind == .roundTrip)
// The search form ranks matching airports/cabin/day before every fallback.
var plan=TripDraft(); plan.origin="TAS"; plan.originAirport=AirportMapBootstrapCatalog.airport(code:"TAS")
plan.scope = .makkahAndMadinah; plan.arrivalAirport = .madinah; plan.selectedReturnAirport = nil
plan.departureDate=IumrahPublishedCarouselCatalog.day("2099-12-07T10:00:00Z","TAS")!
plan.returnDate=IumrahPublishedCarouselCatalog.day("2099-12-12T10:00:00Z","JED")!
let tasMedExact=flight("tasMedExact","TAS","MED","2099-12-07")
let tasMedLater=flight("tasMedLater","TAS","MED","2099-12-09")
let tasMedEarlier=flight("tasMedEarlier","TAS","MED","2099-12-03")
let tasJed=flight("tasJed","TAS","JED","2099-12-01")
let nmaMed=flight("nmaMed","NMA","MED","2099-12-02")
let tasMedBusiness=flight("tasMedBusiness","TAS","MED","2099-12-07","business")
let jedTasExact=flight("jedTasExact","JED","TAS","2099-12-12")
let jedTasLater=flight("jedTasLater","JED","TAS","2099-12-14")
let medTas=flight("medTas","MED","TAS","2099-12-10")
let jedFeg=flight("jedFeg","JED","FEG","2099-12-10")
let jedTasTooSoon=flight("jedTasTooSoon","JED","TAS","2099-12-07")
func ranked(_ input:[LocalJourneyFlight], _ plan:TripDraft, _ direction:Int, _ other:LocalJourneyFlight?=nil)->[String] {
 let times=Dictionary(uniqueKeysWithValues: input.map { ($0.id,IumrahAllPublishedFlightStore.departureInstant($0)!) })
 return IumrahAllPublishedFlightStore.prioritized(input,trip:plan,direction:direction,other:other,departureInstants:times).map(\.id)
}
let outboundRows=[tasJed,nmaMed,tasMedLater,tasMedBusiness,tasMedExact,tasMedEarlier]
let inboundRows=[jedTasTooSoon,medTas,jedFeg,jedTasLater,jedTasExact]
precondition(ranked(outboundRows,plan,0)==["tasMedEarlier","tasMedExact","tasMedLater","tasMedBusiness","tasJed","nmaMed"])
precondition(ranked(inboundRows,plan,1,tasMedExact)==["jedTasTooSoon","jedTasExact","jedTasLater","jedFeg","medTas"])
func anchor(_ input:[LocalJourneyFlight],_ plan:TripDraft,_ direction:Int,_ other:LocalJourneyFlight?=nil)->String? {
 let times=Dictionary(uniqueKeysWithValues:input.map{($0.id,IumrahAllPublishedFlightStore.departureInstant($0)!)})
 let sorted=IumrahAllPublishedFlightStore.prioritized(input,trip:plan,direction:direction,other:other,departureInstants:times)
 return IumrahAllPublishedFlightStore.dateAnchor(sorted,trip:plan,direction:direction,other:other)
}
precondition(anchor(outboundRows,plan,0)=="tasMedExact")
precondition(anchor(inboundRows,plan,1,tasMedExact)=="jedTasExact")
var gap=plan; gap.departureDate=Calendar.current.date(byAdding:.day,value:1,to:plan.departureDate)!
precondition(anchor(outboundRows,gap,0)=="tasMedLater")
plan.arrivalAirport = .jeddah
precondition(ranked(outboundRows,plan,0).first=="tasJed" && ranked(inboundRows,plan,1).first=="medTas")
plan.scope = .makkahOnly
precondition(anchor(inboundRows,plan,1)=="jedTasExact")
let many=(0..<350).map { flight("fallback-\($0)","FEG","JED","2099-12-05") }
let result=ranked(outboundRows+many,plan,0)
precondition(result.count==356 && Set(result).count==356)
precondition(reverse.canContinue(j2.trip)); var changed=j2.trip; changed.returnDate=Calendar.current.date(byAdding:.day,value:1,to:changed.returnDate)!
precondition(!reverse.canContinue(changed))
print("PASS: chronological route/cabin groups and date anchors, MED/JED reversal, compatible return priority, 356 retained, CTA invalidated after date edit")
print("PASS: direction split, expiry, route/cabin synchronization, party preservation, incompatible legs, reverse-first, single-leg IDs, paired fare ID, idempotent hotel handoff")
'''
main='\n'.join([mock,read('Sources/Models/AirportModels.swift'),base,filters,read('Sources/Models/TripModels.swift'),local,read('Sources/FlightEngine/FlightReferenceCatalog.swift'),clock,'enum IumrahPublishedCarouselCatalog {\n'+helpers+'\n}', 'enum IumrahAllPublishedFlightStore {\n'+classifiers+ranking+'\n}',selection,test])
with tempfile.TemporaryDirectory() as d:
    src=Path(d)/'main.swift'; src.write_text(main)
    subprocess.run(['swiftc',str(src),'-o',str(Path(d)/'check')],check=True)
    subprocess.run([str(Path(d)/'check')],check=True)
