/** Nuitee Hotels V1 — server-only supplier adapter. No supplier keys leave this worker. */
import type { Env } from './env';

type Json = Record<string, any>;
type Entry = { payload: string; expires_at: number; updated_at: number };
const BASE = 'https://api.liteapi.travel/v3.0';
const DAY = 86400;
const supportedCities: Record<string, string[]> = {
  makkah: ['Makkah', 'Mecca'],
  madinah: ['Medina', 'Madinah'],
};
const output = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
});
const error = (code: string, status = 400) => output({ ok: false, error: code }, status);
function apiKey(env: Env): string | null { return env.NUITEE_API_KEY?.trim() || null; }
function isSandbox(env: Env): boolean { return (apiKey(env) || '').startsWith('sand_'); }
function text(value: unknown): string { return typeof value === 'string' ? value.trim() : ''; }
function num(value: unknown): number | null {
  const n = typeof value === 'number' ? value : typeof value === 'string' && value.trim() ? Number(value) : NaN;
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function dateParam(value: string | null): string | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const d = new Date(value + 'T00:00:00Z');
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === value ? value : null;
}
function stayDates(inDate: string | null, outDate: string | null): boolean {
  if (!inDate || !outDate) return false;
  const a = Date.parse(inDate + 'T00:00:00Z'), b = Date.parse(outDate + 'T00:00:00Z');
  const today = Date.now() - DAY * 1000;
  return a >= today && b > a && b - a <= 28 * DAY * 1000 && a - Date.now() < 730 * DAY * 1000;
}
function defaultDates(): { checkin: string; checkout: string } {
  const today = new Date();
  const d1 = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() + 10));
  const d2 = new Date(d1.getTime() + DAY * 1000);
  return { checkin: d1.toISOString().slice(0, 10), checkout: d2.toISOString().slice(0, 10) };
}
function plain(value: unknown): string {
  return text(value).replace(/<\/?[^>]*>/g, ' ').replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&').replace(/&quot;/gi, '"').replace(/\s+/g, ' ').trim();
}
function safeImages(values: unknown): string[] {
  return Array.isArray(values) ? [...new Set(values.map(v => text(typeof v === 'string' ? v : v?.url)))]
    .filter(s => /^https:\/\//i.test(s)) : [];
}
function priceOf(v: any): number | null {
  if (Array.isArray(v)) return v.length ? priceOf(v[0]) : null;
  if (v && typeof v === 'object') return num(v.amount ?? v.value ?? v.total);
  return num(v);
}
async function provider(env: Env, path: string, params?: URLSearchParams, data?: unknown): Promise<Json> {
  const key = apiKey(env);
  if (!key) throw new Error('NUITEE_NOT_CONFIGURED');
  const url = `${BASE}${path}${params ? `?${params}` : ''}`;
  const response = await fetch(url, {
    method: data ? 'POST' : 'GET', headers: {
      'X-API-Key': key, 'accept': 'application/json', ...(data ? { 'content-type': 'application/json' } : {}),
    }, body: data ? JSON.stringify(data) : undefined,
    signal: AbortSignal.timeout(22000),
  });
  if (!response.ok) throw new Error(response.status === 429 ? 'NUITEE_RATE_LIMIT' : `NUITEE_HTTP_${response.status}`);
  const json: Json = await response.json();
  if (json?.error) throw new Error(`NUITEE_PROVIDER_ERROR`);
  return json;
}
async function ensure(env: Env): Promise<void> {
  if (!env.HOTELS_DB) throw new Error('HOTELS_DB_NOT_CONFIGURED');
  await env.HOTELS_DB.prepare(`CREATE TABLE IF NOT EXISTS nuitee_hotel_cache (
    key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL, expires_at INTEGER NOT NULL
  )`).run();
}
async function read(env: Env, key: string): Promise<{ data: any; fresh: boolean; updatedAt: number } | null> {
  if (!env.HOTELS_DB) return null;
  const r = await env.HOTELS_DB.prepare('SELECT payload, expires_at, updated_at FROM nuitee_hotel_cache WHERE key = ?1')
    .bind(key).first<Entry>();
  if (!r) return null;
  try { return { data: JSON.parse(r.payload), fresh: r.expires_at > Date.now(), updatedAt: r.updated_at }; }
  catch { return null; }
}
async function save(env: Env, key: string, data: unknown, ttl: number) {
  if (!env.HOTELS_DB) return;
  const now = Date.now();
  await env.HOTELS_DB.prepare(`INSERT INTO nuitee_hotel_cache (key,payload,updated_at,expires_at)
    VALUES (?1,?2,?3,?4) ON CONFLICT(key) DO UPDATE SET
    payload=excluded.payload, updated_at=excluded.updated_at, expires_at=excluded.expires_at`)
    .bind(key, JSON.stringify(data), now, now + ttl * 1000).run();
}
function hotelItem(raw: Json): Json | null {
  const id = text(raw.id), name = text(raw.name);
  if (!id || !name || raw.deletedAt) return null;
  const previewImages = safeImages(raw.hotelImages ?? raw.images);
  const cover = text(raw.thumbnail || raw.main_photo);
  if (cover.startsWith('https://') && !previewImages.includes(cover)) previewImages.unshift(cover);
  return {
    id, name, city: text(raw.city), address: text(raw.address), stars: num(raw.stars ?? raw.starRating),
    previewImages: previewImages.slice(0, 3),
    rating: num(raw.rating), reviewCount: num(raw.reviewCount),
    coverImageURL: cover || null,
    latitude: num(raw.latitude ?? raw.location?.latitude), longitude: num(raw.longitude ?? raw.location?.longitude),
  };
}
async function catalog(env: Env, city: 'makkah' | 'madinah') {
  const key = `catalog:v1:${city}`;
  const cached = await read(env, key);
  if (cached?.fresh) return { items: cached.data as Json[], stale: false };
  try {
    let selected: Json[] = [];
    for (const name of supportedCities[city]) {
      const p = new URLSearchParams({ countryCode: 'SA', cityName: name, limit: '350', offset: '0' });
      const result = await provider(env, '/data/hotels', p);
      const list = (Array.isArray(result.data) ? result.data : []).map(hotelItem).filter(Boolean) as Json[];
      if (list.length > selected.length) selected = list;
      if (selected.length >= 150) break;
    }
    // Explicit cap; exclude bare properties without a meaningful name. No fabricated entries.
    // Keep different star classes visible even when the provider returns more
    // luxury properties than the 150-card V1 limit.
    selected.sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0));
    const groups = [5, 4, 3, 2, 1].map(star => selected.filter(h =>
      Math.max(1, Math.min(5, Math.round(h.stars ?? 0))) === star));
    const balanced: Json[] = [];
    for (const group of groups) balanced.push(...group.slice(0, 30));
    const seen = new Set(balanced.map(h => h.id));
    const remaining = selected.filter(h => !seen.has(h.id));
    const items = [...balanced, ...remaining].slice(0, 150)
      .sort((a, b) => (b.stars ?? 0) - (a.stars ?? 0) || (b.rating ?? 0) - (a.rating ?? 0));
    if (!items.length) throw new Error('NUITEE_CATALOG_EMPTY');
    await save(env, key, items, 7 * DAY);
    return { items, stale: false };
  } catch (e) {
    if (cached) return { items: cached.data as Json[], stale: true };
    throw e;
  }
}
async function minimums(env: Env, city: 'makkah' | 'madinah', hotels: Json[], checkin: string, checkout: string, adults: number) {
  const key = `minimum:v1:${city}:${checkin}:${checkout}:${adults}:UZ:USD`;
  const cached = await read(env, key);
  if (cached?.fresh) return { values: cached.data as Json[], stale: false, updatedAt: cached.updatedAt };
  try {
    const ids = hotels.map(h => text(h.id)).filter(Boolean);
    if (!ids.length) return { values: [], stale: false, updatedAt: Date.now() };
    // Nuitee min-rates is a batch request. We never perform one request per card.
    const result = await provider(env, '/hotels/min-rates', undefined, {
      hotelIds: ids, checkin, checkout, currency: 'USD', guestNationality: 'UZ', occupancies: [{ adults }], timeout: 10,
    });
    const values = Array.isArray(result.data) ? result.data.map((r: Json) => ({
      hotelId: text(r.hotelId), price: priceOf(r.price), currency: 'USD', offerId: text(r.offerId),
    })).filter((r: Json) => r.hotelId && r.price !== null) : [];
    await save(env, key, values, 48 * 3600);
    return { values, stale: false, updatedAt: Date.now() };
  } catch (e) {
    if (cached) return { values: cached.data as Json[], stale: true, updatedAt: cached.updatedAt };
    throw e;
  }
}
function normalizedDetail(raw: Json, summary: Json) {
  const photos = safeImages(raw.hotelImages);
  const first = text(raw.main_photo);
  if (first.startsWith('https://') && !photos.includes(first)) photos.unshift(first);
  const rooms = Array.isArray(raw.rooms) ? raw.rooms.map((r: Json) => ({
    id: String(r.id ?? ''), name: plain(r.roomName ?? r.name), description: plain(r.description),
    maxOccupancy: num(r.maxOccupancy), images: safeImages(r.photos),
    amenities: Array.isArray(r.roomAmenities) ? r.roomAmenities.map((a: any) => plain(a.name ?? a)).filter(Boolean) : [],
  })) : [];
  return {
    ...summary, name: text(raw.name) || summary.name, address: text(raw.address) || summary.address,
    description: plain(raw.hotelDescription), importantInformation: plain(raw.hotelImportantInformation),
    images: photos, rooms,
    amenities: Array.isArray(raw.hotelFacilities) ? raw.hotelFacilities.map((x: any) => plain(typeof x === 'string' ? x : x.name)).filter(Boolean) : [],
    policies: Array.isArray(raw.policies) ? raw.policies.map((x: Json) => ({ title: plain(x.name), description: plain(x.description) })).filter((x: any) => x.title || x.description) : [],
    checkin: plain(raw.checkinCheckoutTimes?.checkin ?? raw.checkin),
    checkout: plain(raw.checkinCheckoutTimes?.checkout ?? raw.checkout),
    latitude: num(raw.latitude ?? raw.location?.latitude) ?? summary.latitude,
    longitude: num(raw.longitude ?? raw.location?.longitude) ?? summary.longitude,
  };
}
function normalizedRates(result: Json, hotelId: string) {
  const item = (Array.isArray(result.data) ? result.data : []).find((x: Json) => x.hotelId === hotelId);
  const offers: Json[] = [];
  for (const type of item?.roomTypes ?? []) {
    for (const rate of type.rates ?? []) {
      const cancellation = rate.cancellationPolicies || type.cancellationPolicies || {};
      const retail = rate.retailRate || {};
      const total = priceOf(retail.total);
      if (total === null || total <= 0) continue;
      const policyInfos = Array.isArray(cancellation.cancelPolicyInfos) ? cancellation.cancelPolicyInfos : [];
      const chargeOnArrival = Array.isArray(retail.taxesAndFees)
        ? retail.taxesAndFees.filter((t: Json) => t.included === false).map((t: Json) => ({ amount: priceOf(t.amount ?? t.total), currency: text(t.currency) || 'USD' })) : [];
      offers.push({
        offerId: text(type.offerId || rate.offerId), roomId: String(rate.mappedRoomId ?? ''),
        roomName: plain(rate.name || type.name || 'Room'), mealPlan: plain(rate.boardName || rate.boardType || ''),
        price: total, currency: text((Array.isArray(retail.total) ? retail.total[0]?.currency : retail.total?.currency)) || 'USD',
        refundable: text(cancellation.refundableTag) === 'RFN',
        cancellationTag: text(cancellation.refundableTag),
        cancellationDescription: plain(cancellation.description || cancellation.name),
        cancellationDeadlines: policyInfos.map((i: Json) => ({
          until: text(i.cancelTime), amount: priceOf(i.amount ?? i.fee ?? i.penaltyAmount),
        })), chargeOnArrival,
      });
    }
  }
  return offers.sort((a,b) => a.price - b.price);
}
async function listing(url: URL, env: Env) {
  const city = (url.searchParams.get('city') || '').toLowerCase();
  if (city !== 'makkah' && city !== 'madinah') return error('INVALID_CITY');
  const rawIn = url.searchParams.get('checkin'), rawOut = url.searchParams.get('checkout');
  if ((rawIn && !dateParam(rawIn)) || (rawOut && !dateParam(rawOut))) return error('INVALID_DATES');
  const inDate = dateParam(rawIn) || defaultDates().checkin;
  const outDate = dateParam(rawOut) || defaultDates().checkout;
  if (!stayDates(inDate, outDate)) return error('INVALID_DATES');
  const adults = Math.floor(Number(url.searchParams.get('adults') || 2));
  if (!Number.isInteger(adults) || adults < 1 || adults > 8) return error('INVALID_OCCUPANCY');
  const c = await catalog(env, city);
  let rates: Awaited<ReturnType<typeof minimums>> | undefined;
  let rateError: string | null = null;
  try { rates = await minimums(env, city, c.items, inDate, outDate, adults); }
  catch (e) { rateError = e instanceof Error ? e.message : 'RATES_UNAVAILABLE'; }
  const indexed = new Map<string, Json>((rates?.values ?? []).map((x: Json): [string, Json] => [x.hotelId, x]));
  return output({ ok: true, provider: 'nuitee', sandbox: isSandbox(env),
    city, checkin: inDate, checkout: outDate, adults, priceType: 'room_total', currency: 'USD',
    hotelCatalogStale: c.stale, pricesStale: Boolean(rates?.stale), pricesUpdatedAt: rates?.updatedAt ?? null, rateError,
    hotels: c.items.map(h => ({ ...h, minimumRate: indexed.get(h.id) ?? null })),
  });
}
async function isListedHotel(env: Env, id: string): Promise<boolean> {
  for (const city of ['makkah', 'madinah']) {
    const c = await read(env, `catalog:v1:${city}`);
    if (Array.isArray(c?.data) && c.data.some((h: Json) => h.id === id)) return true;
  }
  return false;
}

async function detail(url: URL, env: Env) {
  const id = text(url.searchParams.get('hotelId'));
  if (!/^lp[a-zA-Z0-9]{1,50}$/.test(id)) return error('INVALID_HOTEL_ID');
  // Prevent unrestricted scraping of supplier IDs outside our curated city list.
  if (!await isListedHotel(env, id)) return error('HOTEL_NOT_IN_CATALOG', 404);
  const cached = await read(env, `detail:v1:${id}`);
  if (cached?.fresh) return output({ ok: true, sandbox: isSandbox(env), hotel: cached.data });
  try {
    const raw = (await provider(env, '/data/hotel', new URLSearchParams({ hotelId: id }))).data;
    if (!raw || !raw.id) throw new Error('HOTEL_NOT_FOUND');
    const h = normalizedDetail(raw, hotelItem(raw) || { id, name: text(raw.name), city: text(raw.city) });
    await save(env, `detail:v1:${id}`, h, 7 * DAY);
    return output({ ok: true, sandbox: isSandbox(env), hotel: h });
  } catch (e) {
    if (cached) return output({ ok: true, sandbox: isSandbox(env), stale: true, hotel: cached.data });
    throw e;
  }
}
async function rates(request: Request, env: Env) {
  const body = await request.json().catch(() => null) as Json | null;
  if (!body || !/^lp[a-zA-Z0-9]{1,50}$/.test(text(body.hotelId))) return error('INVALID_HOTEL_ID');
  const checkin = dateParam(text(body.checkin)), checkout = dateParam(text(body.checkout));
  if (!stayDates(checkin, checkout)) return error('INVALID_DATES');
  const adults = Number(body.adults);
  if (!Number.isInteger(adults) || adults < 1 || adults > 8) return error('INVALID_OCCUPANCY');
  const id = text(body.hotelId);
  if (!await isListedHotel(env, id)) return error('HOTEL_NOT_IN_CATALOG', 404);
  const key = `rates:v1:${id}:${checkin}:${checkout}:${adults}:UZ:USD`;
  const cached = await read(env, key);
  // Detail prices are limited to 10 min. NEVER use a stale rate as a bookable offer.
  if (cached?.fresh) return output({ ok: true, sandbox: isSandbox(env), checkin, checkout, adults, rates: cached.data, cached: true });
  const response = await provider(env, '/hotels/rates', undefined, {
    hotelIds: [id], checkin, checkout, occupancies: [{ adults }],
    currency: 'USD', guestNationality: 'UZ', roomMapping: true,
    maxRatesPerHotel: 50, timeout: 10,
  });
  const offers = normalizedRates(response, id);
  await save(env, key, offers, 10 * 60);
  return output({ ok: true, sandbox: isSandbox(env), checkin, checkout, adults, rates: offers, cached: false });
}
export async function handleNuiteeHotelRequest(request: Request, env: Env, url: URL): Promise<Response> {
  if (!env.HOTELS_DB) return error('HOTELS_DB_NOT_CONFIGURED', 503);
  try {
    await ensure(env);
    if (url.pathname === '/api/package/nuitee/hotels' && request.method === 'GET') return await listing(url, env);
    if (url.pathname === '/api/package/nuitee/hotel' && request.method === 'GET') return await detail(url, env);
    if (url.pathname === '/api/package/nuitee/rates' && request.method === 'POST') return await rates(request, env);
    return error('NOT_FOUND', 404);
  } catch (e) {
    const code = e instanceof Error ? e.message : 'NUITEE_UNAVAILABLE';
    return error(code.startsWith('NUITEE_') ? code : 'NUITEE_UNAVAILABLE', code === 'NUITEE_NOT_CONFIGURED' ? 503 : code === 'NUITEE_RATE_LIMIT' ? 429 : 502);
  }
}

/** Scheduled two-city refresh; never clears a last-known-good cache on provider errors. */
export async function refreshNuiteeHotelCatalog(env: Env): Promise<void> {
  if (!env.HOTELS_DB || !apiKey(env)) return;
  await ensure(env);
  const { checkin, checkout } = defaultDates();
  for (const city of ['makkah', 'madinah'] as const) {
    try {
      const lastRefresh = await read(env, `scheduled:v1:${city}`);
      if (lastRefresh?.fresh) continue;
      const result = await catalog(env, city);
      await minimums(env, city, result.items, checkin, checkout, 2);
      await save(env, `scheduled:v1:${city}`, true, 48 * 3600);
    } catch {
      // The next scheduled run or an on-demand request will retry.
      // Existing hotel and price snapshots remain intact.
    }
  }
}
