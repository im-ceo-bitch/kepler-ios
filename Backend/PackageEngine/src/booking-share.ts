/**
 * Public, read-only booking shares. No personal data or booking access token
 * is ever included in a share response. A public token is NOT an ownership grant.
 */
import type { Env } from "./env";

const BOOKING_ID = /^IUM-\d{4}-[A-Z2-9]{7}$/;
const SHARE_TOKEN = /^[A-Za-z0-9_-]{43}$/;
const VALID_STATES = new Set([
  "availability_check", "payment_pending", "booking_confirmed", "ready_to_travel",
  "in_trip", "completed", "cancelled",
]);
function publicStatus(raw: string) {
  const alias: Record<string, string> = {
    new: "availability_check", pending: "availability_check", requested: "availability_check",
    checking: "availability_check", availability_confirmed: "payment_pending",
    awaiting_payment: "payment_pending", pending_payment: "payment_pending",
    paid: "booking_confirmed", confirmed: "booking_confirmed", paid_confirmed: "booking_confirmed",
    payment_confirmed: "booking_confirmed", documents_ready: "ready_to_travel",
    ready: "ready_to_travel", traveling: "in_trip",
  };
  const value = alias[raw] ?? raw;
  return VALID_STATES.has(value) ? value : "unknown";
}
function publicVisaType(input: unknown): "tourist" | "tourist_multiple" | "umrah" | null {
  const value = text(input, 40).toLowerCase().replace(/[ -]/g,"_");
  if (["tourist_multiple", "multiple_entry_tourist", "tourist_multivisa"].includes(value)) return "tourist_multiple";
  if (["tourist", "tourism", "evisa"].includes(value)) return "tourist";
  if (["umrah", "umra"].includes(value)) return "umrah";
  return null;
}

interface ShareRow { booking_id: string; expires_at: string; revoked_at: string | null }
interface BookingRow { status: string; payload_json: string }
type Obj = Record<string, unknown>;
const isObj = (value: unknown): value is Obj => Boolean(value) && typeof value === "object" && !Array.isArray(value);
const object = (v: unknown): Obj => isObj(v) ? v : {};
const text = (v: unknown, cap = 130): string => typeof v === "string" ? v.trim().slice(0, cap) : "";
const isoDate = (v: unknown): string | null => typeof v === "string" && /^\d{4}-\d{2}-\d{2}(?:T[\d:.Z+-]+)?$/.test(v) ? v : null;
const positiveInt = (v: unknown): number | null => Number.isInteger(v) && Number(v) >= 0 && Number(v) <= 100 ? Number(v) : null;
const safeAirport = (v: unknown): string | null => /^[A-Z]{3}$/.test(text(v)) ? text(v) : null;
const safeFlightNumber = (v: unknown): string | null => /^[A-Z0-9 -]{2,18}$/i.test(text(v)) ? text(v) : null;
const safeName = (v: unknown): string | null => text(v, 100) || null;
function response(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" } });
}
function bytesHex(a: Uint8Array) { return Array.from(a, b => b.toString(16).padStart(2,"0")).join(""); }
async function sha256(value: string) { return bytesHex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))); }
function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  // base64url with no padding, exactly 43 characters.
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
}
async function ensureSchema(db: NonNullable<Env["BOOKINGS_DB"]>) {
  await db.prepare(`CREATE TABLE IF NOT EXISTS booking_public_shares (
    token_hash TEXT PRIMARY KEY NOT NULL,
    booking_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    revoked_at TEXT
  )`).run();
  await db.prepare("CREATE INDEX IF NOT EXISTS idx_booking_public_shares_booking ON booking_public_shares (booking_id)").run();
}
async function ownerBooking(request: Request, db: NonNullable<Env["BOOKINGS_DB"]>, bookingId: string): Promise<boolean> {
  if (!BOOKING_ID.test(bookingId)) return false;
  const token = request.headers.get("x-booking-token")?.trim() ?? "";
  if (token.length >= 24 && token.length <= 128) {
    const row = await db.prepare("SELECT id FROM bookings WHERE id=?1 AND access_token_hash=?2 LIMIT 1")
      .bind(bookingId, await sha256(token)).first<{ id: string }>();
    if (row) return true;
  }
  // The existing BookingControl authorization contract also accepts an
  // account-linked trip after its owner session is verified by HotelsWorker.
  // Share access is never granted from a booking ID or public share token.
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!/^Bearer\s+\S{16,}$/i.test(authorization)) return false;
  try {
    const ownerCheck = new URL(`/api/catalog/hotels/client/trips/${encodeURIComponent(bookingId)}`, request.url);
    const result = await fetch(ownerCheck, {
      method: "GET", headers: { Authorization: authorization, Accept: "application/json" }, redirect: "manual",
    });
    if (!result.ok) return false;
    const row = await db.prepare("SELECT id FROM bookings WHERE id=?1 LIMIT 1").bind(bookingId).first<{ id: string }>();
    return Boolean(row);
  } catch { return false; }
}

/** Only explicitly whitelisted, public itinerary fields. Never spread a booking payload. */
export function publicBookingProjection(row: BookingRow) {
  let parsed: Obj = {};
  try { parsed = object(JSON.parse(row.payload_json)); } catch { /* absent data */ }
  const booking = object(parsed.booking ?? parsed);
  const input = object(booking.input);
  const stay = object(booking.stay);
  const hotels = object(booking.hotelNames);
  const customization = object(booking.customization);
  const trace = object(booking.generatorTrace);
  const route = object(booking.route);
  const select = object(booking.selection);
  const legacyMakkah = object(booking.hotelSelection);
  const legacyMadinah = object(booking.madinahHotelSelection);
  const legacy = object(booking.selectionDetails);
  // A booked flight is not necessarily ticketed. Publish readiness only when
  // a dedicated recorded issuance flag/status exists, never from route presence.
  const documents = object(booking.documents);
  const visa = object(documents.visa);
  const ticket = object(documents.flight ?? documents.tickets);
  const visaState = text(visa.status || booking.visaStatus, 32).toLowerCase();
  const flightState = text(ticket.status || booking.flightTicketStatus, 32).toLowerCase();
  const visaReady = ["ready","issued","approved","completed"].includes(visaState);
  const ticketsReady = ["ready","issued","ticketed","completed"].includes(flightState);
  function leg(value: unknown) {
    const v = object(value);
    return {
      airline: safeName(v.airline), number: safeFlightNumber(v.flightNumbers ?? v.flightNumber),
      origin: safeAirport(v.origin), destination: safeAirport(v.destination),
      departureAt: isoDate(v.departureAt), arrivalAt: isoDate(v.arrivalAt),
    };
  }
  const rawStatus = text(row.status || booking.status, 50).toLowerCase();
  return {
    schemaVersion: 1,
    status: publicStatus(rawStatus),
    dates: { start: isoDate(input.startDate), end: isoDate(input.endDate) },
    route: { origin: safeAirport(route.originCode ?? input.originCode), arrival: safeAirport(route.outboundDestination), returnOrigin: safeAirport(route.returnOrigin) },
    hotels: [
      { city: "makkah", name: safeName(hotels.makkah || legacyMakkah.hotelName || object(trace.makkahHotel).hotelName || object(legacy.makkahHotel).name), room: safeName(object(trace.makkahHotel).roomName), checkin: isoDate(stay.makkahCheckIn), checkout: isoDate(stay.makkahCheckOut), nights: positiveInt(stay.makkahNights), hotelId: safeName(select.makkahHotelId) },
      { city: "madinah", name: safeName(hotels.madinah || legacyMadinah.hotelName || object(trace.madinahHotel).hotelName || object(legacy.madinahHotel).name), room: safeName(object(trace.madinahHotel).roomName), checkin: isoDate(stay.madinahCheckIn), checkout: isoDate(stay.madinahCheckOut), nights: positiveInt(stay.madinahNights), hotelId: safeName(select.madinahHotelId) },
    ].filter(h => h.name && h.nights !== 0),
    flights: { outbound: leg(trace.outbound), inbound: leg(trace.inbound) },
    services: {
      guide: customization.accompaniment === true,
      makkahZiyarat: customization.ziyaratMakkah === true,
      madinahZiyarat: customization.ziyaratMadinah === true,
      meals: customization.meals === true,
      esim: customization.esim === true,
    },
    documents: {
      visa: { status: visaReady ? "ready" : "not_confirmed", type: visaReady ? publicVisaType(visa.type ?? booking.visaType) : null, generalRulesOnly: true },
      flightTickets: { status: ticketsReady ? "ready" : "not_confirmed" },
    },
    permissions: { viewer: true, canManage: false, canPay: false, canEdit: false, canViewDocuments: false },
  };
}

/** POST owner-verified create; DELETE owner-verified revoke all; GET public by token. */
export async function handleBookingShare(request: Request, env: Env, url: URL): Promise<Response> {
  const db = env.BOOKINGS_DB;
  if (!db) return response({ ok: false, error: "SHARING_UNAVAILABLE" }, 503);
  const match = /^\/api\/package\/booking\/(IUM-\d{4}-[A-Z2-9]{7})\/share$/.exec(url.pathname);
  const publicMatch = /^\/api\/package\/shares\/([A-Za-z0-9_-]{43})$/.exec(url.pathname);
  if (!match && !publicMatch) return response({ ok: false, error: "NOT_FOUND" }, 404);
  if (publicMatch && request.method !== "GET") return response({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  if (match && !["POST","DELETE"].includes(request.method)) return response({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    await ensureSchema(db);
    if (publicMatch) {
      const token = publicMatch[1];
      if (!SHARE_TOKEN.test(token)) return response({ ok: false, error: "NOT_FOUND" }, 404);
      const share = await db.prepare("SELECT booking_id,expires_at,revoked_at FROM booking_public_shares WHERE token_hash=?1 LIMIT 1")
        .bind(await sha256(token)).first<ShareRow>();
      if (!share || share.revoked_at || Date.parse(share.expires_at) <= Date.now()) return response({ ok: false, error: "LINK_UNAVAILABLE" }, 404);
      const booking = await db.prepare("SELECT status,payload_json FROM bookings WHERE id=?1 LIMIT 1")
        .bind(share.booking_id).first<BookingRow>();
      if (!booking) return response({ ok: false, error: "LINK_UNAVAILABLE" }, 404);
      return response({ ok: true, trip: publicBookingProjection(booking) });
    }
    const id = match![1];
    if (!await ownerBooking(request, db, id)) return response({ ok: false, error: "NOT_FOUND" }, 404);
    if (request.method === "DELETE") {
      await db.prepare("UPDATE booking_public_shares SET revoked_at=?1 WHERE booking_id=?2 AND revoked_at IS NULL")
        .bind(new Date().toISOString(), id).run();
      return response({ ok: true, revoked: true });
    }
    const token = generateToken();
    const now = new Date();
    const expires = new Date(now.getTime() + 180 * 86400000);
    await db.prepare("INSERT INTO booking_public_shares (token_hash,booking_id,created_at,expires_at,revoked_at) VALUES (?1,?2,?3,?4,NULL)")
      .bind(await sha256(token), id, now.toISOString(), expires.toISOString()).run();
    return response({ ok: true, shareURL: `https://iumrah.app/s/${token}`, expiresAt: expires.toISOString(), permissions: "viewer" }, 201);
  } catch (err) {
    console.error("booking-public-share-failed", err);
    return response({ ok: false, error: "SHARING_UNAVAILABLE" }, 503);
  }
}
