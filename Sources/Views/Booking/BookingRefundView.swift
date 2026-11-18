import SwiftUI
struct BookingRefundPreview: Decodable {
    struct Item: Decodable, Identifiable { let code: String; let label: String; let amountCents: Int; let refundCents: Int?; let reason: String; var id: String { code } }
    let available: Bool; let items: [Item]; let estimateCents: Int?; let supportCents: Int?; let paidCents: Int?; let refundedCents: Int?
}
struct BookingRefundView: View {
    let bookingID: String; let bookingToken: String
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var preview: BookingRefundPreview?; @State private var busy=false; @State private var sent=false; @State private var confirm=false; @State private var error:String?
    private func t(_ r:String,_ e:String,_ u:String,_ c:String)->String { IumrahFlightCopy.text(settings.language,r,e,u,c) }
    private func money(_ cents:Int)->String { (Double(cents)/100).formatted(.currency(code:"USD")) }
    private var headers:[String:String] { var h:[String:String]=[:]; if !bookingToken.isEmpty { h["x-booking-token"]=bookingToken }; if let token=account.bearerToken { h["Authorization"]="Bearer "+token }; return h }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:16) {
            Text(t("Предварительный расчёт возврата","Preliminary refund estimate","Qaytarishning dastlabki hisobi","Қайтаришнинг дастлабки ҳисоби")).font(.title2.bold())
            if let preview {
                if preview.available {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(preview.items) { item in
                            HStack { VStack(alignment:.leading,spacing:4) { Text(item.label).font(.subheadline); Text(money(item.amountCents)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(item.refundCents.map(money) ?? t("Уточняется","Review required","Aniqlanadi","Аниқланади")).font(.subheadline.weight(.semibold)) }; Divider()
                        }
                        if let support=preview.supportCents { HStack { Text(t("Комиссия 9% · предварительно","9% fee · estimated","9% komissiya · taxminiy","9% комиссия · тахминий")); Spacer(); Text(money(support)) }.font(.subheadline) }
                        if let estimate=preview.estimateCents { Text(money(estimate)).font(.largeTitle.bold()) }
                        Text(t("Итог проверит менеджер. Комиссия оплаты и тарифы поставщиков уточняются отдельно.","A manager will verify the final amount, payment fee and supplier rules.","Yakuniy summani menejer tekshiradi.","Якуний суммани менежер текширади.")).font(.caption).foregroundStyle(.secondary)
                    }.iumrahCard()
                } else { Text(t("Расчёт подготовит менеджер.","A manager will calculate the refund.","Menejer qaytarishni hisoblaydi.","Менежер қайтаришни ҳисоблайди.")).iumrahCard() }
                Button { confirm=true } label: { Text(sent ? t("Запрос отправлен","Request sent","So‘rov yuborildi","Сўров юборилди") : t("Запросить отмену всей поездки","Request cancellation of entire trip","Safarni bekor qilishni so‘rash","Сафарни бекор қилишни сўраш")) }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(busy||sent)
                Text(t("Запрос не отменяет поездку автоматически и не переводит деньги.","The request does not automatically cancel the trip or transfer money.","So‘rov safarni avtomatik bekor qilmaydi.","Сўров сафарни автоматик бекор қилмайди.")).font(.caption).foregroundStyle(.secondary)
            } else if error == nil { ProgressView() }
            if let error { Text(error).font(.caption).foregroundStyle(.red); Button(t("Повторить","Retry","Qayta urinish","Қайта уриниш")) { Task { await load() } } }
        }.padding(IumrahDesign.pagePadding) }.navigationTitle(t("Отмена и возврат","Cancellation and refund","Bekor qilish va qaytarish","Бекор қилиш ва қайтариш")).navigationBarTitleDisplayMode(.inline).task { await load() }.confirmationDialog(t("Отправить запрос на отмену всей поездки?","Request cancellation of the entire trip?","Safarni bekor qilish so‘rovi?","Сафарни бекор қилиш сўрови?"),isPresented:$confirm,titleVisibility:.visible) { Button(t("Отправить запрос","Send request","So‘rov yuborish","Сўров юбориш"),role:.destructive){Task{await submit()}} }
    }
    @MainActor private func load() async { error=nil; do { preview=try await APIClient.shared.get("/api/catalog/hotels/client/bookings/\(bookingID)/refund-preview",headers:headers) } catch { self.error=error.localizedDescription } }
    @MainActor private func submit() async { busy=true; defer{busy=false}; do { let result=try await BookingService().requestCancellation(id:bookingID,headers:headers); sent=result.ok==true; if !sent { self.error=t("Запрос не подтверждён","Request not confirmed","So‘rov tasdiqlanmadi","Сўров тасдиқланмади") } } catch {self.error=error.localizedDescription} }
}
