import SwiftUI
import Security
import UIKit

struct SavedPackageSnapshot: Codable {
    let totalUsd: Double
    let perPilgrimUsd: Double
    let input: BookingInputRecord
    let hotelNames: BookingHotelNames
    let flight: String
    let includedServices: [String]
    let tripSummary: TripSummaryPublicPrice?
}
struct SavedPackageEntry: Identifiable {
    let credential: TripSummaryOwnerCredential
    let receipt: TripSummarySavedReceipt
    var id: String { receipt.packageID }
}
struct PackageThread: Decodable {
    struct Message: Decodable, Identifiable { let id: Int; let revision: Int; let sender: String; let body: String; let createdAt: String }
    struct RoomRequest: Decodable { let revision: Int; let adults: Int; let rooms: Int; let state: String; let note: String }
    let packageID: String; let revision: Int; let messages: [Message]; let roomRequest: RoomRequest?
}
enum TripSummaryLifecycle {
    static func read(_ receipt: TripSummarySavedReceipt, _ credential: TripSummaryOwnerCredential) async throws -> TripSummarySavedReceipt {
        try await APIClient.shared.get("/api/offers/saved/\(receipt.packageID)", headers: ["x-package-owner":credential.token])
    }
    static func thread(_ receipt: TripSummarySavedReceipt, _ credential: TripSummaryOwnerCredential) async throws -> PackageThread {
        try await APIClient.shared.get("/api/offers/saved/\(receipt.packageID)/thread", headers: ["x-package-owner":credential.token])
    }
    struct Message: Encodable { let revision: Int; let body: String; let requestID: String; let requestRooms: Int? }
    static func send(_ receipt: TripSummarySavedReceipt, _ credential: TripSummaryOwnerCredential, _ body: Message) async throws -> PackageThread {
        try await APIClient.shared.post("/api/offers/saved/\(receipt.packageID)/thread", body: body, headers: ["x-package-owner":credential.token])
    }
    struct Link: Codable { let revision: Int; let bookingID: String }
    static func link(receipt: TripSummarySavedReceipt, credential: TripSummaryOwnerCredential, booking: StoredBookingSession) async throws {
        let _: IumrahSimpleResponse = try await APIClient.shared.post("/api/offers/saved/\(receipt.packageID)/booking", body: Link(revision: receipt.revision, bookingID: booking.id), headers: ["x-package-owner":credential.token,"x-booking-token":booking.accessToken])
        credential.removePendingLink(receipt.packageID)
    }
}
// A saved local selection is a restoration hint, never a quote. No booking grant or supplier cost is persisted here.
struct TripSummaryLocalDraft: Codable {
    let trip: TripDraft; let ages: [Int]; let local: Bool; let flights: [LocalJourneyFlight]; let rooms: [String:LocalJourneyRoom]
    let path: String; let flex: Int; let complete: String?; let outboundID: String?; let inboundID: String?; let mixed: String?
    let hotel: HotelSummary?; let madinahHotel: HotelSummary?; let room: HotelRoom?; let madinahRoom: HotelRoom?
    let roomCategory: IumrahRoomCategoryOption?; let madinahCategory: IumrahRoomCategoryOption?; let outbound: FlightOffer?; let inbound: FlightOffer?
    let vehicle: TransferVehicleKind?; let confirmed: Bool; let train: Bool; let fare: HaramainFareClass; let trainAdults: Int; let trainChildren: Int
    let stagedOutbound: FlightDiscoveryOffer?; let stagedInbound: FlightDiscoveryOffer?; let stagedRoundTrip: FlightDiscoveryOffer?
    @MainActor init(journey j: JourneyStore) {
        trip=j.trip; ages=j.tripSummaryChildAges; local=j.usesLocalJourney; flights=j.localJourneyFlights; rooms=j.localJourneyRooms
        path=j.packageFlightPath.rawValue; flex=j.flightSearchFlexDays; complete=j.selectedPublishedCompleteID; outboundID=j.selectedPublishedOutboundID; inboundID=j.selectedPublishedReturnID; mixed=j.mixedFlightIdentity
        hotel=j.selectedHotel; madinahHotel=j.selectedMadinahHotel; room=j.selectedRoom; madinahRoom=j.selectedMadinahRoom; roomCategory=j.selectedRoomCategory; madinahCategory=j.selectedMadinahRoomCategory; outbound=j.selectedOutbound; inbound=j.selectedInbound
        vehicle=j.selectedTransferVehicle; confirmed=j.transferSelectionConfirmed; train=j.haramainTrainSelected; fare=j.haramainFareClass; trainAdults=j.haramainAdultTickets; trainChildren=j.haramainChildTickets
        stagedOutbound=j.stagedAviasalesOffers[.outbound]; stagedInbound=j.stagedAviasalesOffers[.inbound]; stagedRoundTrip=j.stagedAviasalesOffers[.roundTrip]
    }
    @MainActor func restore() -> JourneyStore {
        let j=JourneyStore(); j.trip=trip; j.tripSummaryChildAges=ages; j.usesLocalJourney=local; j.localJourneyFlights=flights; j.localJourneyRooms=rooms
        j.packageFlightPath=PackageFlightPath(rawValue:path) ?? .publishedDirect; j.flightSearchFlexDays=flex; j.selectedPublishedCompleteID=complete; j.selectedPublishedOutboundID=outboundID; j.selectedPublishedReturnID=inboundID; j.mixedFlightIdentity=mixed
        j.selectedHotel=hotel; j.selectedMadinahHotel=madinahHotel; j.selectedRoom=room; j.selectedMadinahRoom=madinahRoom; j.selectedRoomCategory=roomCategory; j.selectedMadinahRoomCategory=madinahCategory; j.selectedOutbound=outbound; j.selectedInbound=inbound
        j.selectedTransferVehicle=vehicle; j.transferSelectionConfirmed=confirmed; j.haramainTrainSelected=train; j.haramainFareClass=fare; j.haramainAdultTickets=trainAdults; j.haramainChildTickets=trainChildren
        j.stagedAviasalesOffers[.outbound]=stagedOutbound; j.stagedAviasalesOffers[.inbound]=stagedInbound; j.stagedAviasalesOffers[.roundTrip]=stagedRoundTrip
        j.invalidateTripSummaryQuote(); return j
    }
}
extension TripSummaryOwnerCredential {
    private func key(_ service: String, _ id: String) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:id] }
    private func put<T:Encodable>(_ value:T,_ service:String,_ id:String) { guard let data=try? JSONEncoder().encode(value) else{return}; let q=key(service,id); SecItemDelete(q as CFDictionary); var insert=q;insert[kSecValueData as String]=data;insert[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; SecItemAdd(insert as CFDictionary,nil) }
    private func get<T:Decodable>(_ type:T.Type,_ service:String,_ id:String)->T? { var q=key(service,id);q[kSecReturnData as String]=true;var result:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil};return try? JSONDecoder().decode(type,from:data) }
    func recordDraft(_ draft:TripSummaryLocalDraft,packageID:String){put(draft,"com.iumrah.saved-package-draft",packageID)}
    func draft(_ id:String)->TripSummaryLocalDraft?{get(TripSummaryLocalDraft.self,"com.iumrah.saved-package-draft",id)}
    func recordPendingLink(receipt:TripSummarySavedReceipt,booking:StoredBookingSession){put(booking.id,"com.iumrah.saved-package-link",receipt.packageID)}
    func pendingLink(_ id:String)->String?{get(String.self,"com.iumrah.saved-package-link",id)}
    func removePendingLink(_ id:String){SecItemDelete(key("com.iumrah.saved-package-link",id) as CFDictionary)}
}
struct PackageNativeShareButton: View {
    let items: [Any]; let title: String
    @State private var showing = false
    var body: some View { Button { showing=true } label: { Label(title,systemImage:"square.and.arrow.up") }.buttonStyle(IumrahPrimaryButtonStyle()).sheet(isPresented:$showing){ Activity(items:items) } }
    private struct Activity: UIViewControllerRepresentable {
        let items:[Any]
        func makeUIViewController(context:Context)->UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
        func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
    }
}
struct SavedPackageThreadView: View {
    let receipt: TripSummarySavedReceipt; let credential: TripSummaryOwnerCredential; let initialMessage: String; let requestedRooms: Int?
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var value: PackageThread?; @State private var draft=""; @State private var requestID=UUID().uuidString; @State private var sending=false; @State private var error:String?
    private func t(_ r:String,_ e:String,_ u:String,_ c:String)->String { IumrahFlightCopy.text(settings.language,r,e,u,c) }
    var body: some View {
        VStack(alignment:.leading,spacing:12){
            Text(receipt.packageID).font(.caption.monospaced()).foregroundStyle(.secondary)
            if let room=value?.roomRequest { VStack(alignment:.leading,spacing:4){ Text(t("Запрос на размещение","Room request","Joylashuv so‘rovi","Жойлашув сўрови")).font(.headline);Text(room.state == "pending" ? t("На согласовании","Under review","Ko‘rib chiqilmoqda","Кўриб чиқилмоқда") : room.note).font(.subheadline) }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.yellow.opacity(0.14),in:RoundedRectangle(cornerRadius:14)) }
            ForEach(value?.messages ?? []) { msg in VStack(alignment:.leading,spacing:4){Text(msg.sender == "staff" ? "iumrah" : t("Вы","You","Siz","Сиз")).font(.caption.weight(.semibold));Text(msg.body).font(.subheadline).textSelection(.enabled);Text(msg.createdAt).font(.caption2).foregroundStyle(.secondary)}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:14)) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if receipt.status != "converted" {
                TextField(t("Написать сообщение…","Write a message…","Xabar yozing…","Хабар ёзинг…"),text:$draft,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...6).disabled(sending || value == nil)
                Button { Task { await send() } } label:{Label(t("Отправить","Send","Yuborish","Юбориш"),systemImage:"paperplane.fill")}.buttonStyle(IumrahPrimaryButtonStyle()).disabled(sending || value == nil || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            Button(t("Обновить","Refresh","Yangilash","Янгилаш")){Task{await load()}}.font(.caption)
        }.task { draft=initialMessage; await load(); while !Task.isCancelled { do{try await Task.sleep(for:.seconds(12))}catch{break};if !sending {await load()} } }
    }
    @MainActor private func load() async {do{value=try await TripSummaryLifecycle.thread(receipt,credential);error=nil}catch{self.error=error.localizedDescription}}
    @MainActor private func send() async {guard !sending,let value else{return}; sending=true;defer{sending=false};do{self.value=try await TripSummaryLifecycle.send(receipt,credential,.init(revision:value.revision,body:draft,requestID:requestID,requestRooms:value.roomRequest == nil ? requestedRooms : nil));draft="";requestID=UUID().uuidString;error=nil}catch{self.error=error.localizedDescription}}
}
struct SavedJourneysView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @State private var entries:[SavedPackageEntry]=[]; @State private var selected:SavedPackageEntry?; @State private var restored:JourneyStore?; @State private var error:String?
    private func t(_ r:String,_ e:String,_ u:String,_ c:String)->String{IumrahFlightCopy.text(settings.language,r,e,u,c)}
    var body: some View { ScrollView { VStack(alignment:.leading,spacing:16){
        if entries.isEmpty { ContentUnavailableView(t("Нет сохранённых путешествий","No saved journeys","Saqlangan safarlar yo‘q","Сақланган сафарлар йўқ"),systemImage:"bookmark") }
        ForEach(entries){entry in VStack(alignment:.leading,spacing:10){Text(entry.receipt.packageID).font(.caption.monospaced());if let p=entry.receipt.package {Text(p.hotelNames.makkah).font(.headline);Text(p.input.startDate+" — "+p.input.endDate);Text(p.totalUsd,format:.currency(code:"USD")).font(.title2.bold())};Text(entry.receipt.status == "expired" ? t("Требуется новый расчёт","New quote required","Yangi hisob kerak","Янги ҳисоб керак") : t("Сохранённое путешествие","Saved journey","Saqlangan safar","Сақланган сафар")).font(.caption).foregroundStyle(.secondary)
            if entry.receipt.status != "converted",let draft=entry.credential.draft(entry.id){Button(t("Открыть и проверить цену","Open and reprice","Ochish va narxni tekshirish","Очиш ва нархни текшириш")){restored=draft.restore();selected=entry}.buttonStyle(IumrahPrimaryButtonStyle())}
            if let raw=entry.receipt.shareURL,let url=URL(string:raw){Link(destination:url){Label(t("Посмотреть предложение","View proposal","Taklifni ko‘rish","Таклифни кўриш"),systemImage:"arrow.up.right")};ShareLink(item:url)}
            NavigationLink { ScrollView{SavedPackageThreadView(receipt:entry.receipt,credential:entry.credential,initialMessage:"",requestedRooms:nil).padding(20)} } label:{Label(t("Задать вопрос","Ask a question","Savol berish","Савол бериш"),systemImage:"headphones")}
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:20))}
        if let error {Text(error).font(.caption).foregroundStyle(.red)}
        WhyIumrahCarousel(primaryTitle: t("Продолжить бронирование","Continue booking","Bronni davom ettirish","Бронни давом эттириш"), onPrimary: { if entries.count == 1, let entry = entries.first, entry.receipt.status != "converted", let draft = entry.credential.draft(entry.id) { restored = draft.restore(); selected = entry } })
    }.padding(20)}.navigationTitle(t("Сохранённые путешествия","Saved journeys","Saqlangan safarlar","Сақланган сафарлар")).task{await load()}.refreshable{await load()}.navigationDestination(isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil;restored=nil}})){if let selected,let restored{FinalPackageView(restoration:selected).environmentObject(restored)}} }
    @MainActor private func load() async { var next:[SavedPackageEntry]=[];for (credential,receipt) in TripSummaryOwnerCredential.all(){if let id=credential.pendingLink(receipt.packageID),let booking=bookings.booking(id:id){try? await TripSummaryLifecycle.link(receipt:receipt,credential:credential,booking:booking)};do{let fresh=try await TripSummaryLifecycle.read(receipt,credential);credential.record(fresh);next.append(.init(credential:credential,receipt:fresh))}catch{next.append(.init(credential:credential,receipt:receipt));self.error=error.localizedDescription}};entries=next.filter{$0.receipt.status != "converted"} }
}
