import type { Env } from './env';

type Obj = Record<string, unknown>;
const obj = (value: unknown): Obj => value && typeof value === 'object' && !Array.isArray(value) ? value as Obj : {};
const text = (value: unknown): string | undefined => typeof value === 'string' && value.trim() ? value.trim().slice(0, 200) : undefined;
const number = (value: unknown): number | undefined => typeof value === 'number' && Number.isFinite(value) ? value : undefined;
const canonical = (value: unknown) => (text(value) ?? '').toUpperCase().replace(/[\s-]/g, '');
const response = (detail: unknown = null, status = 200) => new Response(JSON.stringify({ detail }), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
const clock = (value: unknown) => text(obj(value).local);
const utc = (value: unknown) => text(obj(value).utc);

// Never select a different flight solely because a number or date matches.
export function matchingFlightDetail(payload: unknown, flight: string, day: string, origin: string, destination: string, localTime: string, now = Date.now()) {
  if (!Array.isArray(payload)) return null;
  const matches = payload.map(obj).filter(row => {
    const dep = obj(row.departure), arr = obj(row.arrival);
    const scheduled = clock(dep.scheduledTime);
    return canonical(row.number) === flight && obj(dep.airport).iata === origin && obj(arr.airport).iata === destination && scheduled?.slice(0, 10) === day;
  });
  // Multiple same-number flights on the same route/day are ambiguous unless
  // the scheduled local minute identifies exactly one of them.
  const exact = matches.filter(row => clock(obj(row.departure).scheduledTime)?.slice(11, 16) === localTime);
  const selected = exact.length === 1 ? exact[0] : exact.length === 0 && matches.length === 1 && !localTime ? matches[0] : undefined;
  if (!selected) return null;
  const dep = obj(selected.departure), arr = obj(selected.arrival), aircraft = obj(selected.aircraft), location = obj(selected.location);
  const status = text(selected.status);
  const reportedAt = text(location.reportedAtUtc);
  const age = reportedAt ? now - Date.parse(reportedAt) : Infinity;
  const lat = number(location.lat), lon = number(location.lon);
  const live = ['EnRoute', 'Approaching', 'Departed'].includes(status ?? '') && age >= -60_000 && age <= 15 * 60_000 && lat !== undefined && Math.abs(lat) <= 90 && lon !== undefined && Math.abs(lon) <= 180;
  return {
    status, updatedAt: text(selected.lastUpdatedUtc),
    departureTerminal: text(dep.terminal), departureGate: text(dep.gate),
    arrivalTerminal: text(arr.terminal), arrivalGate: text(arr.gate), baggageBelt: text(arr.baggageBelt),
    departureScheduled: clock(dep.scheduledTime), arrivalScheduled: clock(arr.scheduledTime),
    departureRevised: clock(dep.revisedTime), arrivalRevised: clock(arr.revisedTime),
    departureActual: clock(dep.runwayTime), arrivalActual: clock(arr.runwayTime),
    arrivalEstimatedUTC: utc(arr.revisedTime),
    aircraft: text(aircraft.model), registration: text(aircraft.reg),
    position: live ? { latitude: lat, longitude: lon, reportedAt, altitudeFeet: number(obj(location.altitude).feet), speedKmh: number(obj(location.groundSpeed).kmPerHour) } : undefined,
  };
}

// Optional, opt-in on the existing PackageEngine. Atomic daily reservation
// bounds paid upstream calls even under concurrent public requests. No cron.
export async function flightDetailResponse(url: URL, env: Env): Promise<Response> {
  const flight = canonical(url.searchParams.get('number'));
  const day = url.searchParams.get('date') ?? '', origin = canonical(url.searchParams.get('origin')), destination = canonical(url.searchParams.get('destination'));
  const localTime = url.searchParams.get('time') ?? '';
  const parsed = Date.parse(day + 'T00:00:00Z');
  if (!/^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$/.test(flight) || !/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(parsed) || new Date(parsed).toISOString().slice(0,10) !== day || !/^[A-Z]{3}$/.test(origin) || !/^[A-Z]{3}$/.test(destination) || origin === destination || (localTime && !/^([01]\d|2[0-3]):[0-5]\d$/.test(localTime))) return response(null, 400);
  const key = env.AERODATABOX_RAPIDAPI_KEY?.trim();
  const limit = Number(env.AERODATABOX_DAILY_REQUEST_LIMIT ?? 0);
  if (!key || !env.HOTELS_DB || !Number.isInteger(limit) || limit < 1 || limit > 100000) return response();
  try {
    await env.HOTELS_DB.prepare('CREATE TABLE IF NOT EXISTS aerodatabox_daily_usage (day TEXT PRIMARY KEY, requests INTEGER NOT NULL)').run();
    const reserved = await env.HOTELS_DB.prepare(`INSERT INTO aerodatabox_daily_usage(day, requests) VALUES (?1, 1)
      ON CONFLICT(day) DO UPDATE SET requests = requests + 1 WHERE requests < ?2 RETURNING requests`).bind(new Date().toISOString().slice(0,10), limit).first<{requests: number}>();
    if (!reserved) return response();
    const upstream = new URL(`https://aerodatabox.p.rapidapi.com/flights/number/${flight}/${day}`);
    upstream.searchParams.set('dateLocalRole', 'Departure');
    upstream.searchParams.set('withLocation', 'true');
    const result = await fetch(upstream, { headers: { 'X-RapidAPI-Key': key, 'X-RapidAPI-Host': 'aerodatabox.p.rapidapi.com', Accept: 'application/json' }, signal: AbortSignal.timeout(9000) });
    if (!result.ok || result.status === 204) return response();
    return response(matchingFlightDetail(await result.json(), flight, day, origin, destination, localTime));
  } catch { return response(); }
}
