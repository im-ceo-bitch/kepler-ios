import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
// The PackageEngine test command runs ordinary Node.js, not a TS loader.
const source = readFileSync(new URL('../src/booking-share.ts', import.meta.url), 'utf8');
const stripped = stripTypeScriptTypes(source, {mode:'strip'});
const {handleBookingShare, publicBookingProjection} = await import('data:text/javascript;base64,' + Buffer.from(stripped).toString('base64'));

const bookingId = 'IUM-2026-AB23456';
const ownerToken = 'owner-access-very-long-secret-token-0123456789';
const tokenHash = createHash('sha256').update(ownerToken).digest('hex');

function database() {
  const rows = new Map();
  let booking = {
    id: bookingId,
    access_token_hash: tokenHash,
    status: 'booking_confirmed',
    payload_json: JSON.stringify({
      booking: {
        input: { startDate: '2027-01-10', endDate: '2027-01-17',originCode:'TAS',travelers:[{name:'PRIVATE USER'}]},
        route: { originCode: 'TAS', outboundDestination: 'MED',returnOrigin:'JED' },
        hotelNames: { makkah: 'Makkah Hotel', madinah: 'Madinah Hotel' },
        generatorTrace: {outbound:{airline:'Airline',flightNumbers:'ABC 123',origin:'TAS',destination:'MED',departureAt:'2027-01-10T10:00:00Z'}, inbound:{airline:'Airline',flightNumbers:'ABC 456',origin:'JED',destination:'TAS',departureAt:'2027-01-17T10:00:00Z'}},
        documents: {visa:{status:'issued', type:'tourist_multiple', passportNumber:'D000000',fullName:'PRIVATE USER',downloadURL:'https://private'},flight:{status:'ticketed',pnr:'SECRET-PNR'}},
        firstName: 'PRIVATE USER', email:'private@example.com', phone:'+123', passportNumber:'D000000',
        payment: {card:'1234'}, accessToken: ownerToken, invoice: 'sensitive', totalUsd: 3000,
      },
    }),
  };
  const db = {
    rows,
    setBooking(next) { booking = next; },
    prepare(sql) {
      let args=[];
      return {
        bind(...values) {args=values; return this;},
        async run() {
          if (sql.startsWith('INSERT INTO booking_public_shares')) {
            rows.set(args[0], { token_hash:args[0],booking_id:args[1], created_at:args[2], expires_at:args[3], revoked_at:null });
          } else if (sql.startsWith('UPDATE booking_public_shares')) {
            for (const row of rows.values()) if(row.booking_id===args[1]&&!row.revoked_at) row.revoked_at=args[0];
          }
          return {success:true};
        },
        async first() {
          if (sql.includes('FROM booking_public_shares')) return rows.get(args[0])??null;
          if (sql.includes('FROM bookings')) {
            if(booking.id!==args[0]) return null;
            if(sql.includes('access_token_hash') && booking.access_token_hash!==args[1]) return null;
            return booking;
          }
          return null;
        },
      };
    },
  };
  return db;
}

function req(path,method='GET',secret) {
  const headers=secret?{'x-booking-token':secret}:{};
  return new Request(`https://iumrah.app${path}`,{method,headers});
}
const path=`/api/package/booking/${bookingId}/share`;

// D1 CRUD is tested with an isolated in-memory adapter; no production data.
test('owner-only creation, read-only projection, revoke of all links',async()=>{
  const db=database();const env={BOOKINGS_DB:db};
  assert.equal((await handleBookingShare(req(path,'POST'),env,new URL('https://iumrah.app'+path))).status,404);
  assert.equal((await handleBookingShare(req(path,'POST','wrong-token-value-with-correct-length'),env,new URL('https://iumrah.app'+path))).status,404);
  const make=await handleBookingShare(req(path,'POST',ownerToken),env,new URL('https://iumrah.app'+path));
  assert.equal(make.status,201);
  const payload=await make.json();
  assert.match(payload.shareURL,/^https:\/\/iumrah\.app\/s\/[A-Za-z0-9_-]{43}$/);
  const share=payload.shareURL.slice(payload.shareURL.lastIndexOf('/')+1);
  const endpoint=`/api/package/shares/${share}`;
  assert.equal((await handleBookingShare(req(endpoint,'POST'),env,new URL('https://iumrah.app'+endpoint))).status,405);
  const visible=await handleBookingShare(req(endpoint),env,new URL('https://iumrah.app'+endpoint));
  assert.equal(visible.status,200);
  const data=await visible.json();
  assert.equal(data.trip.flights.outbound.number,'ABC 123');
  assert.equal(data.trip.hotels[0].name,'Makkah Hotel');
  assert.equal(data.trip.documents.visa.type,'tourist_multiple');
  assert.equal(data.trip.documents.visa.status,'ready');
  assert.equal(data.trip.documents.flightTickets.status,'ready');
  assert.equal(data.trip.permissions.canManage,false);
  assert.equal(data.trip.permissions.canPay,false);
  const encoded=JSON.stringify(data);
  for(const sensitive of ['PRIVATE USER','private@example.com','SECRET-PNR','D000000',ownerToken,'1234','invoice','payment','passportNumber','access_token_hash']) {
    assert.equal(encoded.includes(sensitive),false,`leaked: ${sensitive}`);
  }
  const revoke=await handleBookingShare(req(path,'DELETE',ownerToken),env,new URL('https://iumrah.app'+path));
  assert.equal(revoke.status,200);
  assert.equal((await handleBookingShare(req(endpoint),env,new URL('https://iumrah.app'+endpoint))).status,404);
});

test('document readiness requires issued/ticketed operational status, never inferred',()=>{
 const value=publicBookingProjection({status:'paid',payload_json:JSON.stringify({booking:{
  hotelNames:{makkah:'Makkah'},generatorTrace:{outbound:{flightNumbers:'ZZ 777',origin:'TAS',destination:'JED'}},
  documents:{visa:{status:'processing'},tickets:{status:'pending'}},
  name:'Patient Private',passportPhoto:'not public',pnr:'SECRET',
 }})});
 assert.equal(value.status,'booking_confirmed');
 assert.equal(value.documents.visa.status,'not_confirmed');
 assert.equal(value.documents.flightTickets.status,'not_confirmed');
 assert.equal(value.documents.visa.type,null);
 assert.equal(JSON.stringify(value).includes('Patient Private'),false);
});

test('expired and revoked shares are unavailable',async()=>{
 const db=database(),env={BOOKINGS_DB:db};
 const made=await handleBookingShare(req(path,'POST',ownerToken),env,new URL('https://iumrah.app'+path));
 const {shareURL}=await made.json();
 const token=shareURL.split('/').pop();
 const key=createHash('sha256').update(token).digest('hex');
 db.rows.get(key).expires_at='2020-01-01T00:00:00Z';
 const endpoint=`/api/package/shares/${token}`;
 assert.equal((await handleBookingShare(req(endpoint),env,new URL('https://iumrah.app'+endpoint))).status,404);
});

test('account-linked owner requires a validated account session', async () => {
  const db=database(), env={BOOKINGS_DB:db};
  const originalFetch=globalThis.fetch;
  let checks=0;
  try {
    globalThis.fetch=async (url, init) => {
      checks++;
      assert.match(String(url), /\/api\/catalog\/hotels\/client\/trips\/IUM-2026-AB23456$/);
      assert.equal(init?.headers?.Authorization,'Bearer validated-owner-session-token');
      return Response.json({ok:true},{status:200});
    };
    const authorized = new Request('https://iumrah.app'+path,{method:'POST',headers:{Authorization:'Bearer validated-owner-session-token'}});
    assert.equal((await handleBookingShare(authorized,env,new URL(authorized.url))).status,201);
    assert.equal(checks,1);
    globalThis.fetch=async()=>new Response('Forbidden',{status:403});
    assert.equal((await handleBookingShare(authorized,env,new URL(authorized.url))).status,404);
    const unauthorized = new Request('https://iumrah.app'+path,{method:'POST',headers:{Authorization:'Bearer public-share-token-not-a-session'}});
    assert.equal((await handleBookingShare(unauthorized,env,new URL(unauthorized.url))).status,404);
  } finally { globalThis.fetch=originalFetch; }
});
