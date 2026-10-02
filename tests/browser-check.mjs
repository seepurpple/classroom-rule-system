// Run with AGENT_BROWSER_CLI=/path/to/agent-browser/bin/agent-browser.js node tests/browser-check.mjs.
// Synthetic browser-only responses; no production writes.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const cli=process.env.AGENT_BROWSER_CLI;
assert.ok(cli,'Set AGENT_BROWSER_CLI to the agent-browser JS entry point');
const session='petclass-ux-fixture';
function browser(...args){const r=spawnSync(process.execPath,[cli,'--session',session,...args],{encoding:'utf8',timeout:45000});assert.equal(r.status,0,r.stderr);return r.stdout;}
const now=new Date().toISOString();
const pet=(id,speciesId,level,stage,representative)=>({id,speciesId,level,stage,representative,xp:0,skills:[],createdAt:now});
const lot=(id,sku,n)=>({id,sku,quantity:n,remaining:n,reference:id,note:'UI fixture',revoked:false,createdAt:now});
const state={needsSetup:false,user:{id:'fixture-student',loginId:'07',name:'07번 학생',role:'student',mustChangePassword:false},className:'1학년 3반',balance:1200,version:0,claimedStarter:true,students:[],pets:[pet('fox','seedfox',10,2,true),pet('penguin','bubblepenguin',1,1,false)],inventory:[lot('a','food-s',2),lot('b','food-s',3),lot('t','pet-choice-ticket',1)],logs:[],orders:[],ledger:[],updatedAt:now,products:[{sku:'food-s',name:'별빛 한입',price:30,description:'경험치 +30',kind:'food'},{sku:'pet-choice-ticket',name:'새 친구 초대권',price:1000,description:'새 친구 만나기',kind:'ticket'}]};
try{
 browser('open',process.env.PETCLASS_URL||'http://localhost:3016');
 browser('network','route','**/api/farm','--body',JSON.stringify({state}));
 browser('reload');browser('wait','.pc-pet-card');
 browser('eval','document.querySelectorAll(".pc-pet-card .pc-primary")[1].click()');
 assert.equal(browser('eval','document.querySelector("dialog select").value').trim(),'"penguin"');
 assert.ok(browser('snapshot').includes('방울핀에게 1개 주기'));
 browser('screenshot',fileURLToPath(new URL('../docs/screenshots/feeding-desktop.png',import.meta.url)));
 browser('press','Escape');
 browser('find','role','button','click','--name','보관함','--exact');
 assert.equal(browser('eval','document.querySelectorAll(".pc-item-card").length').trim(),'2');
 assert.equal(browser('eval','document.querySelector(".pc-item-card .pc-pill").textContent.replace(/[^0-9]/g,"")').trim(),'"5"');
 browser('find','role','button','click','--name','새 친구 만나기','--exact');
 assert.ok(browser('snapshot').includes('함께하는 중'));
 browser('press','Escape');
 state.students=Array.from({length:25},(_,i)=>({id:`fixture-${i+1}`,loginId:String(i+1),name:`${String(i+1).padStart(2,'0')}번 학생`,studentNo:i+1,role:'student',balance:1000,pets:i===0?state.pets:[],inventory:[],mustChangePassword:false}));
 state.user={id:'fixture-teacher',loginId:'teacher',name:'선생님',role:'teacher',mustChangePassword:false};state.pets=[];state.inventory=[];
 browser('network','unroute','**/api/farm');browser('network','route','**/api/farm','--body',JSON.stringify({state}));browser('reload');browser('wait','.pc-student');
 assert.equal(browser('eval','document.querySelectorAll(".pc-student").length').trim(),'25');
 browser('eval','document.querySelector(".pc-student-select input").click()');
 browser('find','role','button','click','--name','1명 선택 · 내용 확인','--exact');
 assert.ok(browser('snapshot').includes('확인 · 포인트 기록'));
 browser('screenshot',fileURLToPath(new URL('../docs/screenshots/teacher-desktop.png',import.meta.url)));
 browser('set','viewport','390','844');
 assert.equal(browser('eval','document.documentElement.scrollWidth>innerWidth').trim(),'false');
 console.log('PASS: selected pet, grouped inventory, occupied species, 25-student teacher view, point confirmation, mobile width');
}finally{browser('network','unroute','**/api/farm');browser('close');}
