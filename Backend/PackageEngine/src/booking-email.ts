import type { Env } from './env';
import type { D1Like } from './d1';

// Notification state is independent of account sign-in and SMS registration.
// Subscription rows are only created after an email OTP and booking-token check.
const base = 'https://iumrah.app';
export type BookingMailLocale = 'ru' | 'uz' | 'uz-cyrl' | 'en';
export function mailLocale(raw: unknown): BookingMailLocale {
  const l = String(raw ?? '').toLowerCase().replace('_', '-');
  if (l === 'uz-cyrl' || l === 'uz-cyrillic') return 'uz-cyrl';
  if (l === 'uz' || l === 'uz-latn' || l === 'uz-uz') return 'uz';
  return l.startsWith('ru') ? 'ru' : l.startsWith('en') ? 'en' : 'en';
}
export async function ensureBookingMailSchema(db: D1Like) {
  await db.prepare(`CREATE TABLE IF NOT EXISTS iumrah_guest_booking_email_challenges (
    id TEXT PRIMARY KEY, email TEXT NOT NULL, salt TEXT NOT NULL, code_hash TEXT NOT NULL,
    created_at TEXT NOT NULL, expires_at TEXT NOT NULL, ip_hash TEXT NOT NULL DEFAULT '',
    attempts INTEGER NOT NULL DEFAULT 0, verified_at TEXT, verification_token_hash TEXT UNIQUE,
    proof_expires_at TEXT, consumed_at TEXT, booking_id TEXT
  )`).run();
  await db.prepare(`CREATE INDEX IF NOT EXISTS idx_guest_booking_email_rate
    ON iumrah_guest_booking_email_challenges(email,created_at)`).run();
  await db.prepare(`CREATE TABLE IF NOT EXISTS iumrah_booking_email_subscriptions (
    booking_id TEXT PRIMARY KEY, email TEXT NOT NULL, locale TEXT NOT NULL,
    verified_at TEXT NOT NULL, last_sent_status TEXT,
    lease_token TEXT, lease_until TEXT, last_sent_at TEXT, last_error TEXT
  )`).run();
}

function esc(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, v => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[v] ?? v));
}
function safeHttps(value: unknown): string | null {
  const raw=String(value ?? '').trim();
  if (!raw || raw.startsWith('//')) return null;
  try {
    const url = raw.startsWith('/') ? new URL(raw, base) : new URL(raw);
    return url.protocol === 'https:' && !url.username && !url.password && url.hostname.length > 3 && url.hostname.length < 180 ? url.toString() : null;
  } catch { return null; }
}
const text = {
  ru: { head: 'Ваше бронирование Umrah-пакета подтверждено', intro: 'Подождите, пока система повторно проверит наличие всех компонентов. Наличие мест и цены на авиабилеты и отели могут меняться несколько раз в день.', noPay: 'Сейчас вы ничего не оплачиваете. Оплата станет доступна только после повторного подтверждения наличия всех компонентов.', booking: 'Бронирование', guest:'Паломник', package:'Пакет', days:'Продолжительность', people:'Путешественники', total:'Итоговая стоимость', per:'На одного человека', priceNote:'Предварительная стоимость, подлежит проверке', hotelM:'Отель в Мекке', hotelD:'Отель в Медине', flight:'Перелёт', next:'Что дальше', nextBody:'Мы перепроверяем авиабилеты, отели и остальные услуги. Статус обновится автоматически.', telegram:'Подключите Telegram', telegramBody:'Получайте обновления поездки, статусы бронирования, уведомления о документах и билетах. Уведомления также доступны в приложении и по электронной почте.', connect:'Подключить Telegram', view:'Открыть бронирование', support:'Нужна помощь?', footer:'Транзакционное письмо о вашем бронировании iumrah.', available:'Доступность подтверждена', availableBody:'Компоненты поездки проверены. Теперь можно перейти к оплате и предоставить паспортные данные.', paid:'Оплата подтверждена', paidBody:'Оплата получена, бронирование подтверждено. Мы продолжаем подготовку поездки.', ready:'Документы готовы', readyBody:'Документы для вашей поездки подготовлены. Откройте бронирование для безопасного просмотра.', traveling:'Вы в поездке', travelingBody:'Желаем благополучной Умры! Информация о поездке доступна в вашем бронировании.', checking:'Проверяем доступность', payment:'Ожидается оплата и данные паспорта', confirmed:'Оплачено и подтверждено', docs:'Документы готовы', trip:'В поездке', status:'Статус' },
  en: { head:'Your Umrah package booking has been confirmed', intro:'Please wait while we recheck availability for every component. Flight and hotel prices and availability can change several times a day.', noPay:'You pay nothing now. Payment becomes available only after every component is reconfirmed.', booking:'Booking', guest:'Pilgrim', package:'Package', days:'Duration', people:'Travelers', total:'Total package price', per:'Per person', priceNote:'Indicative price, subject to reconfirmation', hotelM:'Makkah hotel', hotelD:'Madinah hotel', flight:'Flights', next:'What happens next', nextBody:'We are checking flights, hotels, and remaining services. Your status will update automatically.', telegram:'Connect Telegram', telegramBody:'Get trip updates, booking statuses, documents and ticket alerts. Updates are also available in the app and by email.', connect:'Connect Telegram', view:'View booking', support:'Need assistance?', footer:'A transactional message about your iumrah booking.', available:'Availability confirmed', availableBody:'Trip components have been checked. You can now proceed to payment and provide passport details.', paid:'Payment confirmed', paidBody:'Payment received and booking confirmed. We are preparing your trip.', ready:'Documents ready', readyBody:'Your travel documents are ready. Open your booking to view them securely.', traveling:'You are on your trip', travelingBody:'Wishing you a blessed Umrah! Your trip details are available in your booking.', checking:'Checking availability', payment:'Awaiting payment and passport details', confirmed:'Paid and confirmed', docs:'Documents ready', trip:'On trip', status:'Status' },
  uz: { head:'Umra paketingiz bron qilingani tasdiqlandi', intro:'Tizim barcha xizmatlarning mavjudligini qayta tekshirguncha kuting. Aviabilet va mehmonxona narxlari hamda mavjudligi kun davomida bir necha marta o‘zgarishi mumkin.', noPay:'Hozir hech qanday to‘lov qilmaysiz. To‘lov barcha xizmatlar mavjudligi qayta tasdiqlangandan keyin ochiladi.', booking:'Bron', guest:'Ziyoratchi', package:'Paket', days:'Davomiyligi', people:'Yo‘lovchilar', total:'Umumiy narx', per:'Bir kishi uchun', priceNote:'Narx dastlabki, qayta tasdiqlanadi', hotelM:'Makkadagi mehmonxona', hotelD:'Madinadagi mehmonxona', flight:'Parvoz', next:'Keyingi qadam', nextBody:'Aviabiletlar, mehmonxonalar va xizmatlar qayta tekshiriladi. Holat avtomatik yangilanadi.', telegram:'Telegramni ulang', telegramBody:'Safar yangiliklari, bron holati, hujjatlar va chiptalar haqida xabarlar oling. Xabarlar ilova va emailingizga ham keladi.', connect:'Telegramni ulash', view:'Bronni ko‘rish', support:'Yordam kerakmi?', footer:'iumrah broningiz haqidagi xizmat xabari.', available:'Mavjudlik tasdiqlandi', availableBody:'Safar xizmatlari tekshirildi. Endi to‘lov va pasport ma’lumotlarini yuborishingiz mumkin.', paid:'To‘lov tasdiqlandi', paidBody:'To‘lov qabul qilindi va bron tasdiqlandi. Safaringiz tayyorlanmoqda.', ready:'Hujjatlar tayyor', readyBody:'Safar hujjatlari tayyor. Ularni xavfsiz ko‘rish uchun bronni oching.', traveling:'Siz safardasiz', travelingBody:'Umrangiz muborak bo‘lsin! Safar ma’lumotlari broningizda mavjud.', checking:'Mavjudlik tekshirilmoqda', payment:'To‘lov va pasport kutilmoqda', confirmed:'To‘langan va tasdiqlangan', docs:'Hujjatlar tayyor', trip:'Safarda', status:'Holat' },
  'uz-cyrl': { head:'Умра пакетингиз брон қилингани тасдиқланди', intro:'Тизим барча хизматларнинг мавжудлигини қайта текширгунча кутинг. Авиабилет ва меҳмонхона нархлари ҳамда мавжудлиги кун давомида бир неча марта ўзгариши мумкин.', noPay:'Ҳозир ҳеч қандай тўлов қилмайсиз. Тўлов барча хизматлар мавжудлиги қайта тасдиқлангандан кейин очилади.', booking:'Брон', guest:'Зиёратчи', package:'Пакет', days:'Давомийлиги', people:'Йўловчилар', total:'Умумий нарх', per:'Бир киши учун', priceNote:'Нарх дастлабки, қайта тасдиқланади', hotelM:'Маккадаги меҳмонхона', hotelD:'Мадинадаги меҳмонхона', flight:'Парвоз', next:'Кейинги қадам', nextBody:'Авиабилетлар, меҳмонхоналар ва хизматлар қайта текширилади. Ҳолат автоматик янгиланади.', telegram:'Telegramни уланг', telegramBody:'Сафар янгиликлари, брон ҳолати, ҳужжатлар ва чипталар ҳақида хабарлар олинг. Хабарлар илова ва электрон почтангизга ҳам келади.', connect:'Telegramни улаш', view:'Бронни кўриш', support:'Ёрдам керакми?', footer:'iumrah брон ҳақидаги хизмат хабари.', available:'Мавжудлик тасдиқланди', availableBody:'Сафар хизматлари текширилди. Энди тўлов ва паспорт маълумотларини юборишингиз мумкин.', paid:'Тўлов тасдиқланди', paidBody:'Тўлов қабул қилинди ва брон тасдиқланди. Сафарингиз тайёрланмоқда.', ready:'Ҳужжатлар тайёр', readyBody:'Сафар ҳужжатлари тайёр. Уларни хавфсиз кўриш учун бронни очинг.', traveling:'Сиз сафардасиз', travelingBody:'Умрангиз муборак бўлсин! Сафар маълумотлари бронда мавжуд.', checking:'Мавжудлик текширилмоқда', payment:'Тўлов ва паспорт кутилмоқда', confirmed:'Тўланган ва тасдиқланган', docs:'Ҳужжатлар тайёр', trip:'Сафарда', status:'Ҳолат' },
} as const;
export type MailStage = 'checking'|'available'|'paid'|'ready'|'traveling';
export function resolveMailStage(raw: unknown): MailStage | null {
  const s = String(raw ?? '').trim().toLowerCase().replace(/[-\s]/g,'_');
  if (['new','availability_check','pending','requested','request_received','new_request','awaiting_availability','availability_check','checking','checking_availability','pending_verification','pending_availability'].includes(s)) return 'checking';
  if (['available','availability_confirmed','waiting_payment','awaiting_payment','confirmed_available','awaiting_payment_and_passport','pending_payment','payment_pending'].includes(s)) return 'available';
  if (['confirmed','paid','paid_confirmed','payment_confirmed','booking_confirmed','payment_completed'].includes(s)) return 'paid';
  if (['documents_ready','ready','ready_to_travel','travel_ready'].includes(s)) return 'ready';
  if (['in_trip','in_progress','traveling','travelling','on_trip'].includes(s)) return 'traveling';
  return null; // Never send incorrect payment messages for unknown status values.
}
function obj(value: unknown): Record<string, unknown> { return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function str(value: unknown, max = 160): string { return String(value ?? '').trim().slice(0,max); }
function money(value: unknown): string | null { const x=Number(value); return Number.isFinite(x) && x>0 ? `$${new Intl.NumberFormat('en-US',{maximumFractionDigits:0}).format(x)}` : null; }
function infoCell(key: string, value: unknown): string { return value ? `<tr><td style="padding:9px 4px;color:#727783">${esc(key)}</td><td align="right" style="padding:9px 4px;font-weight:650">${esc(value)}</td></tr>` : ''; }
function blockTitle(title: string): string { return `<h3 style="font-size:17px;margin:0 0 13px">${esc(title)}</h3>`; }
function hotelCard(title: string, name: string, image?: string | null): string {
  if (!name) return '';
  return `<div style="background:#fff;border:1px solid #e8e9ee;border-radius:18px;overflow:hidden;margin:11px 0">${image ? `<img alt="${esc(name)}" src="${esc(image)}" width="620" style="display:block;width:100%;max-height:220px;object-fit:cover"/>` : ''}<div style="padding:16px"><div style="font-size:12px;color:#878a94">${esc(title)}</div><div style="font-size:18px;font-weight:700;margin-top:4px">${esc(name)}</div></div></div>`;
}
export type BookingEmailSnapshot = { bookingID:string; bookingNumber?:string; status:string; payload:Record<string,unknown>; priceConfirmed?:boolean; makkahImage?:string|null; madinahImage?:string|null };
export function renderBookingEmail(snapshot: BookingEmailSnapshot, locale: BookingMailLocale, stage: MailStage) {
  const c=text[locale]; const payload=snapshot.payload; const booking=obj(payload.booking); const data=Object.keys(booking).length?booking:payload;
  const profile=obj(data.pilgrimProfile ?? payload.pilgrimProfile);
  const input=obj(data.input);
  const people=obj(input.travelers);
  const hotels=obj(data.hotelNames);
  const selection=obj(data.selection);
  const days=Number(obj(data.stay).totalDays??0);
  const count=Number(people.adults??0)+Number(people.children??0)+Number(people.infants??0);
  const total=money(data.totalUsd);
  const per=money(data.perPilgrimUsd)??(count>0&&Number(data.totalUsd)>0?money(Number(data.totalUsd)/count):null);
  const name=[str(profile.firstName,80),str(profile.lastName,80)].filter(Boolean).join(' ');
  const packageName=str(data.planId || input.preferredPlan);
  const makkahName=str(hotels.makkah || data.makkahHotel);
  const madinahName=str(hotels.madinah || data.madinahHotel);
  const flight=str(data.flight || obj(data.route).originCode);
  const displayNumber=str(snapshot.bookingNumber||snapshot.bookingID,24);
  const url='https://iumrah.uz/booking';
  const notice=stage==='checking'?c.noPay:stage==='available'?c.availableBody:stage==='paid'?c.paidBody:stage==='ready'?c.readyBody:c.travelingBody;
  const heading=stage==='checking'?c.head:stage==='available'?c.available:stage==='paid'?c.paid:stage==='ready'?c.ready:c.traveling;
  const stepStatus=stage==='checking'?c.checking:stage==='available'?c.payment:stage==='paid'?c.confirmed:stage==='ready'?c.docs:c.trip;
  const statusColor=stage==='checking'?'#f59e0b':stage==='available'?'#2887ff':stage==='paid'?'#24ad64':stage==='ready'?'#24ad64':'#8268ea';
  const subject=`iumrah · ${heading} · ${displayNumber}`;
  const dates=[str(input.startDate,20),str(input.endDate,20)].filter(Boolean).join(' → ');
  const datesLabel:Record<BookingMailLocale,string>={ru:'Даты',en:'Dates',uz:'Sanalar','uz-cyrl':'Саналар'};
  const rows=infoCell(c.booking,displayNumber)+infoCell(c.guest,name)+infoCell(c.package,packageName)+infoCell(c.days,days>0?String(days):'')+infoCell(datesLabel[locale],dates)+infoCell(c.people,count>0?String(count):'')+infoCell(c.total,total)+infoCell(c.per,per);
  const html=`<!doctype html><html lang="${locale}" dir="ltr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:0;background:#f5f6f9;color:#171a22;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f6f9"><tr><td align="center" style="padding:24px 12px"><table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:620px;background:#fff;border-radius:24px;overflow:hidden"><tr><td style="padding:28px 28px 14px"><img src="${base}/api/package/email-brand/logo.png" width="122" alt="iumrah" style="display:block;max-width:100%;height:auto"><div style="margin-top:30px;color:${statusColor};font-size:13px;font-weight:700">● ${esc(stepStatus)}</div><h1 style="font-size:28px;line-height:1.22;letter-spacing:-.5px;margin:12px 0 14px">${esc(heading)}</h1><p style="font-size:15px;color:#656a73;line-height:1.7;margin:0 0 18px">${esc(stage==='checking'?c.intro:notice)}</p>${stage==='checking'?`<div style="background:#edfaf1;padding:18px;border-radius:16px;color:#205c38;line-height:1.6;font-weight:650">✓ ${esc(c.noPay)}</div>`:''}<div style="background:#ecf7ff;border:1px solid #d6eeff;border-radius:17px;padding:19px;margin-top:22px">${blockTitle('✈ '+c.telegram)}<p style="font-size:14px;color:#51677b;line-height:1.65">${esc(c.telegramBody)}</p><a href="${url}" style="display:inline-block;background:#229ED9;color:white;text-decoration:none;font-weight:700;padding:12px 20px;border-radius:12px">${esc(c.connect)}</a></div><div style="padding:20px 0">${blockTitle(c.booking)}<table role="presentation" width="100%" style="font-size:14px;border-collapse:collapse">${rows}</table>${!snapshot.priceConfirmed&&total?`<p style="color:#8b8e97;font-size:12px">${esc(c.priceNote)}</p>`:''}</div>${hotelCard(c.hotelM,makkahName,snapshot.makkahImage)}${hotelCard(c.hotelD,madinahName,snapshot.madinahImage)}${flight?`<div style="border:1px solid #e8e9ee;border-radius:16px;padding:16px;margin-top:15px">${blockTitle(c.flight)}<div style="color:#5e6571">${esc(flight)}</div></div>`:''}<div style="border:1px solid #e8e9ee;border-radius:16px;padding:18px;margin-top:20px">${blockTitle(c.next)}<p style="font-size:14px;color:#676b76;line-height:1.65">${esc(stage==='checking'?c.nextBody:notice)}</p></div><div style="text-align:center;margin:28px 0"><a href="${url}" style="display:inline-block;background:#14171d;color:#fff;text-decoration:none;font-weight:700;padding:16px 30px;border-radius:14px">${esc(c.view)} →</a></div></td></tr><tr><td style="background:#f7f8fa;padding:25px 28px;color:#7d818a;font-size:12px;line-height:1.7"><b style="color:#24262b">iumrah</b><br>${esc(c.footer)}<br>${esc(c.support)}: <a href="mailto:support@iumrah.app" style="color:#5166a2">support@iumrah.app</a><br><a href="${base}" style="color:#5166a2">iumrah.app</a></td></tr></table></td></tr></table></body></html>`;
  const plain=[heading,stage==='checking'?c.intro:notice,c.noPay,`${c.booking}: ${displayNumber}`,`${c.guest}: ${name}`,`${c.package}: ${packageName}`,`${c.total}: ${total??'-'}`,`${c.per}: ${per??'-'}`,`${c.hotelM}: ${makkahName}`,`${c.hotelD}: ${madinahName}`,`${c.flight}: ${flight}`,c.telegramBody,`${c.view}: ${url}`,`support@iumrah.app`].filter(Boolean).join('\n\n');
  return { subject,html,text:plain };
}
function fromAddress(env:Env){return String(env.ACCOUNT_EMAIL_FROM||'security@iumrah.app').trim();}
export async function sendResend(env:Env,email:string,copy:{subject:string;html:string;text:string},key:string):Promise<void>{
  if(!env.RESEND_API_KEY)throw new Error('RESEND_API_KEY_MISSING');
  const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{authorization:`Bearer ${env.RESEND_API_KEY}`,'content-type':'application/json','Idempotency-Key':key.slice(0,255)},body:JSON.stringify({from:`iumrah <${fromAddress(env)}>`,to:[email],reply_to:env.ACCOUNT_EMAIL_REPLY_TO||'support@iumrah.app',...copy})});
  if(!response.ok) throw new Error(`EMAIL_SEND_${response.status}`);
}
export async function sendBookingEmailStatus(env:Env,bookingID:string):Promise<'sent'|'skipped'|'retry'> {
  if(!env.HOTELS_DB||!env.BOOKINGS_DB||!env.RESEND_API_KEY)return 'skipped';
  const db=env.HOTELS_DB;
  await ensureBookingMailSchema(db);
  const sub=await db.prepare('SELECT booking_id,email,locale,last_sent_status,lease_until FROM iumrah_booking_email_subscriptions WHERE booking_id=?1').bind(bookingID).first<{booking_id:string;email:string;locale:string;last_sent_status:string|null;lease_until:string|null}>();
  if(!sub)return 'skipped';
  const booking=await env.BOOKINGS_DB.prepare('SELECT id,status,payload_json FROM bookings WHERE id=?1 LIMIT 1').bind(bookingID).first<{id:string;status:string;payload_json:string}>();
  if(!booking){await db.prepare('DELETE FROM iumrah_booking_email_subscriptions WHERE booking_id=?1').bind(bookingID).run();return 'skipped';}
  const payload=obj(JSON.parse(booking.payload_json||'{}'));
  const operational=await db.prepare('SELECT * FROM pilgrim_trips WHERE booking_id=?1 LIMIT 1').bind(bookingID).first<{status:string;booking_number?:number|string;booking_display_number?:string}>().catch(()=>null);
  const status=resolveMailStage(operational?.status)||resolveMailStage(booking.status)||resolveMailStage(payload.status)||resolveMailStage(obj(payload.booking).status);
  if(!status||status===sub.last_sent_status)return 'skipped';
  const now=new Date().toISOString();const leaseUntil=new Date(Date.now()+3*60_000).toISOString();const lease=crypto.randomUUID();
  // Lease prevents concurrent cron and attach from sending the same status.
  const claim=await db.prepare(`UPDATE iumrah_booking_email_subscriptions SET lease_token=?1,lease_until=?2
    WHERE booking_id=?3 AND (lease_until IS NULL OR lease_until<?4) AND (last_sent_status IS NULL OR last_sent_status<>?5)`).bind(lease,leaseUntil,bookingID,now,status).run();
  if(Number(claim.meta?.changes??0)!==1)return 'skipped';
  try {
    const bookingNo=operational?.booking_display_number || (operational?.booking_number != null ? `#${String(operational.booking_number).padStart(4,'0')}` : undefined);
    const confirmed=Number((operational as Record<string,unknown>|null)?.confirmed_total_usd ?? (operational as Record<string,unknown>|null)?.final_total_usd ?? 0);
    const snapshot:BookingEmailSnapshot={bookingID,bookingNumber:bookingNo,status,payload,priceConfirmed:Number.isFinite(confirmed)&&confirmed>0};
    if(snapshot.priceConfirmed){
      const data=obj(payload.booking);
      const travelers=obj(obj(data.input).travelers);
      const count=Number(travelers.adults??0)+Number(travelers.children??0)+Number(travelers.infants??0);
      // Operational confirmed price takes priority over an earlier indicative quote.
      if(Object.keys(data).length){ data.totalUsd=confirmed;data.perPilgrimUsd=count>0?confirmed/count:data.perPilgrimUsd;payload.booking=data; }
      else { payload.totalUsd=confirmed;payload.perPilgrimUsd=count>0?confirmed/count:payload.perPilgrimUsd; }
    }
    const current=obj(payload.booking);
    const hotelIds=obj(current.selection??payload.selection);
    const primary=obj(current.hotelSelection??payload.hotelSelection);
    const secondary=obj(current.madinahHotelSelection??payload.madinahHotelSelection);
    snapshot.makkahImage=safeHttps(primary.coverImageURL)??await findHotelImage(db,hotelIds.makkahHotelId??primary.hotelId);
    snapshot.madinahImage=safeHttps(secondary.coverImageURL)??await findHotelImage(db,hotelIds.madinahHotelId??secondary.hotelId);
    // Resend idempotency key is stable per booking and status. No duplicate on retries.
    await sendResend(env,sub.email,renderBookingEmail(snapshot,mailLocale(sub.locale),status),`iumrah-${bookingID}-${status}-${sub.email}`);
    await db.prepare(`UPDATE iumrah_booking_email_subscriptions SET last_sent_status=?1,last_sent_at=?2,last_error=NULL,lease_until=NULL,lease_token=NULL
      WHERE booking_id=?3 AND lease_token=?4`).bind(status,new Date().toISOString(),bookingID,lease).run();
    return 'sent';
  }catch(e){
    const error=e instanceof Error?e.message:'EMAIL_ERROR';
    await db.prepare(`UPDATE iumrah_booking_email_subscriptions SET lease_until=NULL,lease_token=NULL,last_error=?1 WHERE booking_id=?2 AND lease_token=?3`).bind(error.slice(0,90),bookingID,lease).run();
    console.error('booking-email-retry',bookingID,error);return 'retry';
  }
}
async function findHotelImage(db:D1Like, id:unknown):Promise<string|null>{
  const hotelID=str(id,100);if(!hotelID)return null;
  try{
    const row=await db.prepare('SELECT * FROM hotels WHERE id=?1 LIMIT 1').bind(hotelID).first<Record<string,unknown>>();
    if(!row)return null;
    for(const k of ['cover_image_url','cover_photo_url','image_url','photo_url','hero_image','coverUrl','thumbnail_url']){const url=safeHttps(row[k]);if(url)return url;}
    for(const k of ['photos_json','images_json','photos','images']){
      let val=row[k];if(typeof val==='string'){try{val=JSON.parse(val);}catch{val=null;}}
      if(Array.isArray(val))for(const image of val.slice(0,5)) { const url=safeHttps(typeof image==='string'?image:obj(image).url||obj(image).src);if(url)return url; }
    }
  }catch(e){console.warn('booking-hotel-image-unavailable',hotelID);}
  return null;
}
export async function flushBookingStatusEmails(env:Env):Promise<void>{
  if(!env.HOTELS_DB||!env.BOOKINGS_DB||!env.RESEND_API_KEY)return;
  await ensureBookingMailSchema(env.HOTELS_DB);
  await env.HOTELS_DB.prepare('DELETE FROM iumrah_guest_booking_email_challenges WHERE expires_at<?1').bind(new Date(Date.now()-7*24*3600_000).toISOString()).run();
  const rows=await env.HOTELS_DB.prepare(`SELECT booking_id FROM iumrah_booking_email_subscriptions ORDER BY verified_at DESC LIMIT 3000`).all<{booking_id:string}>();
  for(const item of rows.results??[]){await sendBookingEmailStatus(env,item.booking_id);}
}
