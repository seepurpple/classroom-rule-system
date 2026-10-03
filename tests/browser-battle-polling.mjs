// Run with a Playwright module supplied by the browser tooling; no added app dependency.
// PLAYWRIGHT_MODULE=/path/to/playwright-core/index.mjs node tests/browser-battle-polling.mjs
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const user={id:'fixture',role:'student',name:'1번',studentNo:1};
const state={user,pets:[],inventory:[],students:[],products:[],logs:[],orders:[],ledger:[],balance:0,version:0,claimedStarter:false,className:'검증'};
const lobby={user,students:[],battles:[],tournaments:[]};
let calls=0,inFlight=0,maxInFlight=0;
try{
 const page=await browser.newPage();
 await page.route('**/api/farm',r=>r.fulfill({json:{state}}));
 await page.route('**/api/battle',async r=>{
  calls++;inFlight++;maxInFlight=Math.max(maxInFlight,inFlight);
  try{
   if(calls===1)await r.fulfill({status:400,json:{error:'지원하지 않는 작업입니다.'}});
   else{await new Promise(resolve=>setTimeout(resolve,4000));await r.fulfill({json:lobby});}
  }finally{inFlight--;}
 });
 await page.goto(process.env.BATTLE_TEST_URL||'http://localhost:3017');
 await page.getByRole('button',{name:'⚔ 모의 배틀',exact:true}).click();
 await page.getByRole('alert').waitFor();
 await new Promise(resolve=>setTimeout(resolve,7000));assert.equal(calls,1,'400 must stop automatic polling');
 await page.getByRole('button',{name:'다시 불러오기',exact:true}).click();
 await page.getByText('아직 개최된 대회가 없어요.',{exact:true}).waitFor();
 assert.equal(await page.getByRole('alert').count(),0);
 await new Promise(resolve=>setTimeout(resolve,7500));
 assert.ok(calls>=3,'manual retry must resume polling');assert.equal(maxInFlight,1,'slow requests must not overlap');
 console.log('PASS: 400 stops polling; manual retry recovers; slow requests never overlap');
}finally{await browser.close();}
