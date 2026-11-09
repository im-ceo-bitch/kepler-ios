import test from 'node:test';
import assert from 'node:assert/strict';
import { translateHotelText, hotelLanguage, uzbekCyrillic } from '../.runtime-dist/hotel-localization.js';
import { handleNuiteeHotelRequest } from '../.runtime-dist/nuitee-hotels.js';

test('translation changes descriptive text only, preserving rates and identifiers', async()=>{
 const old=globalThis.fetch;
 const source={id:'lp123',name:'Hilton',images:['https://example.com/photo.jpg'],description:'A hotel',amenities:['Pool'],rooms:[{id:'42',name:'Suite',description:'Sea view',amenities:['WiFi']}],policies:[{title:'Check in',description:'After 15:00'}],rates:[{offerId:'offer',roomName:'Suite',mealPlan:'Breakfast',cancellationDescription:'Non-refundable',price:245,currency:'USD',cancellationDeadlines:[{until:'2027-01-01',amount:45}]}]};
 globalThis.fetch=async(url,init)=>{assert.match(url,/translation.googleapis.com/);const body=JSON.parse(init.body);assert.equal(body.target,'ru');return Response.json({data:{translations:body.q.map(t=>({translatedText:'RU:'+t}))}});};
 try{const result=await translateHotelText({HOTEL_TRANSLATION_API_KEY:'fixture'},source,'ru');assert.equal(result.description,'RU:A hotel');assert.equal(result.rates[0].roomName,'RU:Suite');assert.equal(result.rates[0].price,245);assert.equal(result.rates[0].offerId,'offer');assert.deepEqual(result.rates[0].cancellationDeadlines,source.rates[0].cancellationDeadlines);assert.deepEqual(result.images,source.images);assert.equal(result.name,'Hilton');assert.equal(source.description,'A hotel');}
 finally{globalThis.fetch=old;}
});
test('unconfigured translation leaves the original text intact; invalid responses fail atomically',async()=>{
 const source={description:'Original'};assert.deepEqual(await translateHotelText({},source,'uz'),source);
 const old=globalThis.fetch;globalThis.fetch=async()=>Response.json({data:{translations:[]}});
 try{await assert.rejects(translateHotelText({HOTEL_TRANSLATION_API_KEY:'fixture'},source,'uz'),/INVALID/);assert.equal(source.description,'Original');}finally{globalThis.fetch=old;}
});
test('locale allowlist and Uzbek Cyrillic conversion',()=>{
 assert.equal(hotelLanguage('../../ru'),'en');assert.equal(hotelLanguage('uz-Cyrl'),'uz-cyrl');assert.equal(uzbekCyrillic("O‘zbekiston, g‘isht, xona"),'Ўзбекистон, ғишт, хона');
});
test('Nuitee detail requests use locale-specific caches',async()=>{
 const cache=new Map([['catalog:v1:makkah',{payload:JSON.stringify([{id:'lp123'}]),updated_at:Date.now(),expires_at:Date.now()+60000}]]);
 const env={NUITEE_API_KEY:'production-fixture',HOTELS_DB:{prepare(sql){let args=[];return {bind(...v){args=v;return this;},async first(){return cache.get(args[0])??null;},async run(){if(sql.includes('INSERT INTO'))cache.set(args[0],{payload:args[1],updated_at:args[2],expires_at:args[3]});return {};}};}}};
 const old=globalThis.fetch,calls=[];globalThis.fetch=async(url)=>{const locale=new URL(url).searchParams.get('language');calls.push(locale);return Response.json({data:{id:'lp123',name:'Hotel',city:'Makkah',hotelDescription:locale==='ru'?'Описание':'Description',hotelImages:[{url:'https://example.com/a.jpg'}]}});};
 try {for(const language of ['ru','en','ru']){const url=new URL('https://example.com/api/package/nuitee/hotel?hotelId=lp123&language='+language);const res=await handleNuiteeHotelRequest(new Request(url),env,url);assert.equal(res.status,200);const body=await res.json();assert.equal(body.hotel.description,language==='ru'?'Описание':'Description');}assert.deepEqual(calls,['ru','en']);}
 finally{globalThis.fetch=old;}
});
