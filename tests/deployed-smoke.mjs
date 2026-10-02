// Read-only checks apart from creating/revoking a login session. Never purchases.
import assert from 'node:assert/strict';
import fs from 'node:fs';
const base=process.env.PETCLASS_URL||'https://classroom-rule-system.vercel.app';
const code=process.env.PETCLASS_SMOKE_CODE||JSON.parse(fs.readFileSync(new URL('../data/pre-integration-backup.json',import.meta.url))).students.find(s=>s.student_no===1).access_code;
let cookie='';
async function call(path,body,origin=base){const response=await fetch(base+path,{method:body?'POST':'GET',headers:{...(body?{'Content-Type':'application/json',Origin:origin}:{}),...(cookie?{Cookie:cookie}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(20000)});const cookies=response.headers.getSetCookie();if(cookies[0])cookie=cookies[0].split(';')[0];return {response,data:await response.json(),cookies};}
try{
 let r=await call('/api/farm');assert.equal(r.data.state.user,null);assert.deepEqual(r.data.state.ledger,[]);
 r=await call('/api/farm',{action:'login',role:'student',code});assert.equal(r.response.status,200);assert.equal(r.data.state.user.role,'student');assert.match(r.cookies.join(';'),/HttpOnly/i);assert.match(r.cookies.join(';'),/Secure/i);
 r=await call('/api/classroom',{name:'identify_student',args:{}});assert.equal(r.response.status,200);assert.ok(r.data.data.studentNo>0);
 r=await call('/api/farm',{action:'price',sku:'food-s',price:1});assert.notEqual(r.response.status,200);
 r=await call('/api/farm',{action:'commit',requestId:crypto.randomUUID()});assert.equal(r.response.status,400);assert.match(r.data.error,/지원하지 않는 작업/);
 r=await call('/api/farm',{action:'logout'},'https://foreign.invalid');assert.equal(r.response.status,403);
 r=await call('/api/farm');assert.equal(r.data.state.user.role,'student');assert.deepEqual(r.data.state.students,[]);
 console.log('PASS: production guest privacy, student login, Secure/HttpOnly cookie, legacy identity, teacher-only price, foreign origin rejected');
}finally{if(cookie){const r=await call('/api/farm',{action:'logout'});assert.equal(r.data.state.user,null);console.log('PASS: logout');}}
