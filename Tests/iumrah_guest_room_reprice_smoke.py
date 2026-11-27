#!/usr/bin/env python3
"""Run the production guest-edit and room refresh methods against deterministic provider fixtures."""
from pathlib import Path
import tempfile, subprocess
read=lambda f:Path(f).read_text()
s=read('Sources/State/JourneyStore.swift'); apply=s[s.index('    func applyTripSummaryGuests('):s.index('    func tripSummaryEditingCopy(')]
s=read('Sources/Models/LocalJourneySelection.swift'); room=s[s.index('struct LocalJourneyRoom:'):s.index('struct LocalJourneyPriceLine:')]; refresh=s[s.index('    func repricePendingJourneyRooms('):s.index('    func refreshLocalJourneyRoomRates(')]
models=read('Sources/Models/NuiteeHotelModels.swift'); hotel=models[models.index('struct NuiteeHotel:'):models.index('struct NuiteeHotelListEnvelope:')]; rates=models[models.index('struct NuiteeCancellationDeadline:'):models.index('struct NuiteeSelectedStay:')]; meals=s[s.index('struct HotelMealChoices:'):]
guest=read('Sources/Views/Package/TripSummarySupport.swift');guest=guest[guest.index('struct TripSummaryGuestDraft {'):guest.index('@MainActor\nfinal class TripSummaryEditSession')]
mock='''import Foundation
struct TripDraft: Equatable { var adults=2; var children=0; var infants=0; var rooms=1; var travelerCount:Int {adults+children+infants} }
enum TransferVehicleKind { case carnival; var passengerCapacity:Int { 9 } }
@MainActor final class JourneyStore {
 var trip=TripDraft(); var localJourneyRooms:[String:LocalJourneyRoom]=[:]; var tripSummaryChildAges:[Int]=[]; var usesLocalJourney=true
 var hotelPriceSnapshot:String?; var selectedTransferVehicle:TransferVehicleKind? = .carnival; var transferSelectionConfirmed=true
 var haramainTrainSelected=false; var haramainAdultTickets=2; var haramainChildTickets=0
 func invalidateTripSummaryQuote() {} ; func cancelHotelPricePrefetch() {}
}
@MainActor struct NuiteeHotelService {
 static var calls=0; static var available=true
 static func dateText(_ d:Date)->String { String(d.timeIntervalSince1970) }
 func rates(hotelID:String,checkin:Date,checkout:Date,adults:Int,childrenAges:[Int],language:String) async throws -> NuiteeRatesEnvelope {
 Self.calls += 1
 let rates = Self.available ? [makeRate("wrong", "other", 99),makeRate("fresh-\\(adults)","double",Double(adults*100)),makeRate("expensive","double",999)] : [makeRate("wrong","other",99)]
 return .init(ok:true,sandbox:false,checkin:Self.dateText(checkin),checkout:Self.dateText(checkout),adults:adults,rates:rates,cached:false)
 }
}
func makeRate(_ offer:String,_ room:String,_ price:Double)->NuiteeRoomRate { .init(offerId:offer,roomId:room,roomName:"Double",mealPlan:"Room only",price:price,currency:"USD",refundable:false,cancellationTag:"",cancellationDescription:"",cancellationDeadlines:[],chargeOnArrival:[]) }
'''
test='''
@main struct Check {
 @MainActor static func main() async {
 let j=JourneyStore(); let date=Date(); let end=date.addingTimeInterval(86400)
 let hotel=NuiteeHotel(id:"lp123",name:"Hotel",city:"makkah",address:nil,stars:4,rating:nil,reviewCount:nil,coverImageURL:nil,previewImages:nil,latitude:nil,longitude:nil,minimumRate:.init(hotelId:"lp123",price:200,currency:"USD",offerId:nil))
 for city in ["makkah","madinah"] { let key=city+":0"; j.localJourneyRooms[key] = .init(id:key,city:city,hotel:hotel,rate:makeRate("original","double",200),checkin:date,checkout:end,adults:2,childrenAges:[],meals:.init(breakfast:true)) }
 var next=j.trip; next.adults=5; j.applyTripSummaryGuests(next,ages:[])
 precondition(j.localJourneyRooms.count==2 && j.localJourneyRooms.values.allSatisfy{$0.requiresRateRefresh==true && $0.adults==5 && $0.hotel.minimumRate==nil && $0.rate.roomId=="double"})
 await j.repricePendingJourneyRooms(); precondition(j.localJourneyRooms.values.allSatisfy{$0.requiresRateRefresh==false && $0.rate.offerId=="fresh-5" && $0.meals?.breakfast==true})
 var draft=TripSummaryGuestDraft(journey:j); draft.adults=6; next=draft.trip(from:j.trip); precondition(next.rooms==2)
 j.applyTripSummaryGuests(next,ages:[]); precondition(j.localJourneyRooms.count==4 && j.localJourneyRooms.values.allSatisfy{$0.adults==3 && $0.requiresRateRefresh==true})
 NuiteeHotelService.available=false; await j.repricePendingJourneyRooms(); precondition(j.localJourneyRooms.count==4 && j.localJourneyRooms.values.allSatisfy{$0.requiresRateRefresh==true && $0.hotel.id=="lp123"})
 NuiteeHotelService.available=true; await j.repricePendingJourneyRooms(); precondition(j.localJourneyRooms.values.allSatisfy{$0.requiresRateRefresh==false && $0.rate.offerId=="fresh-3"})
 let encoded=try! JSONEncoder().encode(j.localJourneyRooms["makkah:0"]!); var old=(try! JSONSerialization.jsonObject(with:encoded)) as! [String:Any]; old.removeValue(forKey:"requiresRateRefresh"); let decoded=try! JSONDecoder().decode(LocalJourneyRoom.self,from:JSONSerialization.data(withJSONObject:old)); precondition(decoded.requiresRateRefresh==nil)
 print("PASS: 2→5 guests, 5→6 guests / two rooms per city, same room and meals, unavailable provider keeps selection pending, confirmed fresh rate, legacy decoding")
 }
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'Check.swift';p.write_text('\n'.join([mock,hotel,rates,meals,room,guest,'@MainActor extension JourneyStore {\n'+apply+refresh+'\n}',test]));subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(Path(d)/'check')],check=True);subprocess.run([str(Path(d)/'check')],check=True)
