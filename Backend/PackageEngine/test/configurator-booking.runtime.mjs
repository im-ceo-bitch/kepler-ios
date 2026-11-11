import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveNuiteePackageHotels, packageTierForStars } from '../.runtime-dist/nuitee-hotels.js';
import { calculatePackageQuote } from '../.runtime-dist/pricing.js';
import { generatePackageQuote } from '../.runtime-dist/package-search.js';
import { unsealPricingSnapshot } from '../.runtime-dist/quote-audit.js';
const checkin=new Date(Date.now()+10*86400000).toISOString().slice(0,10);
const checkout=new Date(Date.now()+17*86400000).toISOString().slice(0,10);
function fixture({stars=4,sandbox=false}={}) {
 const cache=new Map();
 const put=(key,data)=>cache.set(key,{payload:JSON.stringify(data),updated_at:Date.now(),expires_at:Date.now()+600000});
 put('catalog:v1:makkah',[{id:'lp123',name:'Hotel',stars,city:'Makkah'}]);
 put(`rates:v2:lp123:${checkin}:${checkout}:2::UZ:USD`,[{offerId:'offer',roomId:'room',price:200,currency:'USD'}]);
 const env={cache,put,NUITEE_API_KEY:sandbox?'sand_fixture':'live_fixture',PACKAGE_QUOTE_SEAL_KEY:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',TRAVELPAYOUTS_API_TOKEN:'test',HOTELS_DB:{prepare(sql){let args=[];return{
 bind(...v){args=v;return this;},async first(){return cache.get(args[0])??null;},async run(){if(sql.includes('INSERT INTO'))cache.set(args[0],{payload:args[1],updated_at:args[2],expires_at:args[3]});return{success:true};}
 };}}};
 return env;
}
const room=(overrides={})=>({id:'makkah:0',city:'makkah',hotelId:'lp123',offerId:'offer',roomId:'room',checkin,checkout,adults:2,children:[],...overrides});
const party={adults:2,children:0,infants:0,rooms:1};
const prebook=(overrides={})=>({data:{hotelId:'lp123',prebookId:'prebook',currency:'USD',price:245,...overrides}});
async function mockFetch(callback,work){const old=globalThis.fetch;globalThis.fetch=callback;try{return await work();}finally{globalThis.fetch=old;}}
test('hotel categories: 1–2 Economy, 3–4 Standard, 5 Luxury; no unknown category',()=>{
 assert.deepEqual([1,2,3,4,5].map(packageTierForStars),['economy','economy','standard','standard','luxury']);
 for(const x of [0,6,NaN])assert.throws(()=>packageTierForStars(x),/HOTEL_STARS_REQUIRED/);
});
test('prebook validates exact server-bound offer; ignores caller price and tier',async()=>{
 await mockFetch(async(url,init)=>{
  assert.equal(url,'https://book.liteapi.travel/v3.0/rates/prebook');
  assert.deepEqual(JSON.parse(init.body),{offerId:'offer',usePaymentSdk:false});
  return Response.json(prebook());
 },async()=>{
  const result=await resolveNuiteePackageHotels(fixture(),[room({price:1,stars:1,prebookId:'forged'})],party,false);
  assert.equal(result.tier,'standard');assert.equal(result.makkah.amountUsd*7,245);
  assert.equal(result.rooms[0].prebookId,'prebook');assert.equal(result.bookingAllowed,true);
 });
});
test('sandbox tariffs never authorize a real booking',async()=>{
 await mockFetch(async()=>Response.json(prebook()),async()=>{
  assert.equal((await resolveNuiteePackageHotels(fixture({sandbox:true}),[room()],party,false)).bookingAllowed,false);
 });
});
test('expired/mismatched room identity is rejected before supplier call',async()=>{
 await mockFetch(async()=>{throw Error('unexpected supplier call');},async()=>{
  await assert.rejects(resolveNuiteePackageHotels(fixture(),[room({offerId:'forged'})],party,false),/NUITEE_SELECTED_RATE_EXPIRED/);
  await assert.rejects(resolveNuiteePackageHotels(fixture(),[room({adults:1})],party,false),/NUITEE_OCCUPANCY_MISMATCH/);
  await assert.rejects(resolveNuiteePackageHotels(fixture(),[room(),room()],{...party,rooms:2},false),/NUITEE_ROOM_SELECTION_INCOMPLETE/);
 });
});
test('changed cancellation terms, currency and supplier hotel cannot be silently accepted',async()=>{
 for(const values of [{cancellationChanged:true},{boardChanged:true},{currency:'EUR'},{hotelId:'lp999'},{price:0}]){
  await mockFetch(async()=>Response.json(prebook(values)),()=>assert.rejects(resolveNuiteePackageHotels(fixture(),[room()],party,false),/NUITEE_RATE_TERMS_CHANGED|NUITEE_RATE_RECHECK_FAILED/));
 }
});
test('multiple rooms use exact summed totals, one live recheck per repeated offer',async()=>{
 let calls=0;
 await mockFetch(async()=>{calls++;return Response.json(prebook());},async()=>{
  const result=await resolveNuiteePackageHotels(fixture(),[room(),room({id:'makkah:1'})],{...party,adults:4,rooms:2},false);
  assert.equal(result.makkah.amountUsd*7*2,490);assert.equal(calls,1);
 });
});
test('server quote seals Nuitee identities, uses existing package engine, and derives tier from catalogue',async()=>{
 const env=fixture({stars:3});
 await mockFetch(async(url)=>{
  if(String(url).includes('/rates/prebook'))return Response.json(prebook());
  const u=new URL(url);const reverse=u.searchParams.get('origin')==='JED';
  return Response.json({success:true,currency:'usd',data:[{origin:reverse?'JED':'TAS',destination:reverse?'TAS':'JED',airline:'HY',flight_number:reverse?'336':'335',departure_at:`${reverse?checkout:checkin}T12:00:00${reverse?'+03:00':'+05:00'}`,duration:360,price:300}]});
 },async()=>{
  const provider=`aviasales:pair:TAS:JED:${checkin}:${checkout}:HY:335:HY:336:JED:TAS`;
  const response=await generatePackageQuote(new Request('https://fixture/api/package/quote',{method:'POST',body:JSON.stringify({tier:'luxury',tripType:'roundTrip',includeMadinah:false,travelers:party,hotels:{makkah:{hotelId:'lp123',roomId:'room',nights:7}},flight:{providerItineraryId:provider,cabinClass:'economy',legs:[{origin:'TAS',destination:'JED',departureDate:checkin},{origin:'JED',destination:'TAS',departureDate:checkout}]},nuiteeRooms:[room()]})}),env);
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));
  assert.equal(body.quote.resolvedTier,'standard');assert.equal(body.quote.bookingAllowed,true);assert.match(body.quote.quoteId,/^server-/);
  const snapshot=await unsealPricingSnapshot(body.quote.quoteProof,env);
  assert.equal(snapshot.nuiteeRooms[0].prebookId,'prebook');assert.equal(snapshot.context.tier,'standard');
  assert.equal(snapshot.components.find(x=>x.code==='hotel_makkah')?.supplierCostUsd ?? snapshot.components.find(x=>/makkah/i.test(x.code))?.supplierCostUsd,245);
  assert.equal(body.quote.stayPlan.makkahCheckIn,checkin);assert.equal(body.quote.stayPlan.makkahCheckOut,checkout);
 });
});

test('Aviasales accepts legacy, extended and open-jaw identities without changing return airports', async () => {
 const { resolveAviasalesSelection } = await import('../.runtime-dist/package-search.js');
 for (const suffix of ['', ':JED:TAS', ':MED:TAS']) {
  const routes=[];
  await mockFetch(async(raw)=>{
   const url=new URL(raw);const origin=url.searchParams.get('origin'),destination=url.searchParams.get('destination');
   routes.push(`${origin}-${destination}`);
   const reverse=origin!=='TAS';
   return Response.json({success:true,currency:'usd',data:[{origin,destination,airline:'HY',flight_number:reverse?'336':'335',departure_at:`${reverse?checkout:checkin}T12:00:00+03:00`,duration:360,price:reverse?320:300}]});
  },async()=>{
   const result=await resolveAviasalesSelection(`aviasales:pair:TAS:JED:${checkin}:${checkout}:HY:335:HY:336${suffix}`,{TRAVELPAYOUTS_API_TOKEN:'test'});
   const airport=suffix.startsWith(':MED')?'MED':'JED';
   assert.deepEqual(routes,['TAS-JED',`${airport}-TAS`]);
   assert.equal(result.inbound.origin,airport);
   assert.equal(result.perTravelerUsd,620);
  });
 }
});
test('Aviasales rejects malformed identities before sending supplier requests',async()=>{
 const { resolveAviasalesSelection } = await import('../.runtime-dist/package-search.js');
 await mockFetch(async()=>{throw Error('Unexpected supplier request');},async()=>{
  for(const value of [`aviasales:pair:TAS:JED:${checkin}:${checkout}:HY:335:HY:336:MED`, `aviasales:pair:TAS:JED:${checkin}:${checkout}:HY:335:HY:336:MED:SKD`]) {
   await assert.rejects(resolveAviasalesSelection(value,{TRAVELPAYOUTS_API_TOKEN:'test'}),/AVIASALES_IDENTITY_INVALID/);
  }
 });
});
