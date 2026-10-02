import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import fs from 'node:fs';
const bundle=await build({stdin:{contents:'export * from "./lib/domain.ts";export * from "./lib/catalog.ts";export * from "./lib/backend.ts";export * from "./lib/stats.ts";',resolveDir:process.cwd(),loader:'ts'},bundle:true,write:false,format:'esm',platform:'node'});
const {addExperience,applyAction,SPECIES,ITEMS,payload,farmAction,emptyStats,earnedStatPoints,statLimit,statTotal,petStats,validAllocation}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const user=(id,role='student')=>({id,loginId:id,name:id,role,mustChangePassword:false,passwordHash:'',authVersion:1,claimedStarter:false,pets:[],inventory:[]});
const act=(d,a,action,args={})=>applyAction(d,a,{action,requestId:crypto.randomUUID(),...args});
test('browser cannot invoke internal commit, replay or legacy gateway commands',async()=>{for(const action of ['commit','request','legacy','state','unsupported'])await assert.rejects(farmAction('fake-session',{action,requestId:crypto.randomUUID(),data:{pets:[],inventory:[]}}),/지원하지 않는 작업/);});
test('12 species, two per existing type, 36 distinct forms and all 40 assets exist',()=>{assert.equal(SPECIES.length,12);assert.equal(new Set(SPECIES.map(s=>s.id)).size,12);assert.deepEqual(Object.fromEntries(["잎","물","불","바람","흙","빛"].map(t=>[t,SPECIES.filter(s=>s.type===t).length])),{"잎":2,"물":2,"불":2,"바람":2,"흙":2,"빛":2});assert.equal(new Set(SPECIES.flatMap(s=>s.forms)).size,36);for(const s of SPECIES)for(let n=1;n<=3;n++)assert.ok(fs.statSync(`public/assets/pets/${s.id}-${n}.webp`).size>10000);assert.equal(ITEMS.length,4);for(const i of ITEMS)assert.ok(fs.existsSync(`public${i.image}`));});
test('growth evolves at 10/20, carries XP, caps at 30',()=>{assert.deepEqual(addExperience(9,110,30),{level:10,xp:20,stage:2});assert.deepEqual(addExperience(19,210,30),{level:20,xp:20,stage:3});assert.deepEqual(addExperience(29,300,240),{level:30,xp:0,stage:3});assert.throws(()=>addExperience(0,0,20));});
test('starter, ownership, three species, finite food and corrections',()=>{const d={className:'test',users:[user('t','teacher'),user('s'),user('other')]};act(d,'s','choosePet',{speciesId:'seedfox'});assert.throws(()=>act(d,'other','representative',{petId:d.users[1].pets[0].id}));act(d,'t','grant',{studentId:'s',sku:'pet-choice-ticket',quantity:3,reference:'ticket'});const ticket=d.users[1].inventory[0];for(const speciesId of ['bubblepenguin','glowmoth'])act(d,'s','choosePet',{speciesId,grantId:ticket.id});assert.throws(()=>act(d,'s','choosePet',{speciesId:'pebblemole',grantId:ticket.id}));assert.equal(ticket.remaining,1);assert.throws(()=>act(d,'s','grant',{studentId:'s',sku:'food-s',quantity:2,reference:'no'}));const pet=d.users[1].pets[1];act(d,'t','grant',{studentId:'s',sku:'food-s',quantity:2,reference:'food'});const food=d.users[1].inventory[1];act(d,'s','useItem',{petId:pet.id,grantId:food.id,quantity:2});assert.equal(pet.level,2);assert.equal(d.users[1].pets[0].level,1);assert.equal(food.remaining,0);assert.throws(()=>act(d,'s','useItem',{petId:pet.id,grantId:food.id,quantity:1}));});
test('same-origin JSON boundary rejects foreign origins and oversized requests',async()=>{await assert.rejects(payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'https://evil.test','content-type':'application/json'},body:'{}'})));await assert.rejects(payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'http://localhost','content-type':'application/json'},body:JSON.stringify({x:'x'.repeat(17000)})})));assert.deepEqual(await payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'http://localhost','content-type':'application/json'},body:'{"action":"logout"}'})),{action:'logout'});});

test('new species can be chosen and learn all skills through evolution',()=>{for(const species of SPECIES.slice(6)){const d={className:'test',users:[user('t','teacher'),user('s')]};act(d,'s','choosePet',{speciesId:species.id});const pet=d.users[1].pets[0];assert.equal(pet.speciesId,species.id);assert.deepEqual(pet.skills,[species.skills[0]]);assert.throws(()=>act(d,'s','choosePet',{speciesId:species.id}),/이미 키우고 있는 종/);for(const [level,stage] of [[10,2],[20,3]]){act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level,note:'진화 확인'});assert.equal(pet.stage,stage);assert.deepEqual(pet.skills,species.skills.slice(0,stage));}}});
test('release removes only the owner pet and moves representative',()=>{const d={className:'test',users:[user('t','teacher'),user('s'),user('other')]};const s=d.users[1];s.inventory.push({id:'tk',sku:'pet-choice-ticket',quantity:1,remaining:1,reference:'r',note:'',createdAt:'',revoked:false});act(d,'s','choosePet',{speciesId:'seedfox'});act(d,'s','choosePet',{speciesId:'bubblepenguin',grantId:'tk'});const [a,b]=s.pets;assert.ok(a.representative);assert.throws(()=>act(d,'other','release',{petId:a.id}));assert.throws(()=>act(d,'t','release',{petId:a.id}));act(d,'s','release',{petId:a.id});assert.deepEqual(s.pets.map(p=>p.id),[b.id]);assert.ok(b.representative);act(d,'s','release',{petId:b.id});assert.equal(s.pets.length,0);assert.ok(s.claimedStarter);});

test('base stats total 120 and growth budgets include one first-evolution bonus',()=>{
 for(const species of SPECIES){assert.equal(statTotal(species.baseStats),120);assert.ok(Object.values(species.baseStats).every(n=>Number.isInteger(n)&&n>0));}
 for(const [level,points,cap] of [[1,0,0],[2,3,1],[3,6,2],[9,24,9],[10,34,13],[19,61,24],[20,64,25],[30,94,37]]){assert.equal(earnedStatPoints(level),points);assert.equal(statLimit(level),cap);}
 assert.equal(earnedStatPoints(10)-earnedStatPoints(9),10);
 assert.equal(earnedStatPoints(20)-earnedStatPoints(19),3);
});
test('allocation validates ownership, exact integer fields, budget and floored 40% cap',()=>{
 const d={className:'test',users:[user('t','teacher'),user('s'),user('other')]};act(d,'s','choosePet',{speciesId:'kitesquirrel'});const pet=d.users[1].pets[0];
 assert.deepEqual(petStats(pet),SPECIES.find(s=>s.id==='kitesquirrel').baseStats);
 act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:3,note:'test'});
 const allocation={...emptyStats(),hp:2,attack:2,speed:2};
 for(const actor of ['t','other'])assert.throws(()=>act(d,actor,'allocateStats',{petId:pet.id,allocation}));
 for(const bad of [null,[],{hp:1},{...allocation,extra:0},{...allocation,hp:'2'},{...allocation,hp:-1},{...allocation,hp:1.5},{...allocation,hp:NaN},{...allocation,hp:Infinity},{...allocation,hp:3},{...allocation,defense:1}]){assert.equal(validAllocation(bad,pet.level),false);assert.throws(()=>act(d,'s','allocateStats',{petId:pet.id,allocation:bad}));assert.equal(pet.statAllocation,undefined);}
 act(d,'s','allocateStats',{petId:pet.id,allocation});assert.deepEqual(pet.statAllocation,allocation);assert.equal(petStats(pet).speed,31);assert.equal(statTotal(petStats(pet)),126);
 act(d,'s','allocateStats',{petId:pet.id,allocation});assert.equal(statTotal(pet.statAllocation),6);
 act(d,'s','allocateStats',{petId:pet.id,allocation:emptyStats()});assert.equal(statTotal(pet.statAllocation),0);
});
test('legacy pets, multi-level feeding and downward corrections keep budgets consistent',()=>{
 const d={className:'test',users:[user('t','teacher'),user('s')]};act(d,'s','choosePet',{speciesId:'seedfox'});const pet=d.users[1].pets[0];
 act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:9,note:'test'});assert.equal(earnedStatPoints(pet.level),24);
 act(d,'t','grant',{studentId:'s',sku:'food-l',quantity:2,reference:'food'});
 act(d,'s','useItem',{petId:pet.id,grantId:d.users[1].inventory[0].id,quantity:2});assert.equal(pet.level,12);assert.equal(earnedStatPoints(pet.level),40);
 act(d,'s','allocateStats',{petId:pet.id,allocation:{...emptyStats(),hp:16,attack:16,speed:8}});
 const result=act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:9,note:'correction'});assert.equal(statTotal(pet.statAllocation),0);assert.match(result.message,/배분 초기화/);
 act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:10,note:'test'});assert.equal(earnedStatPoints(pet.level),34);
 act(d,'s','allocateStats',{petId:pet.id,allocation:{...emptyStats(),hp:1}});
 act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:9,note:'test'});assert.equal(pet.statAllocation.hp,1);
 act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level:10,note:'test'});assert.equal(earnedStatPoints(pet.level)-statTotal(pet.statAllocation),33);
});
test('allocation persists through the gateway and duplicate requests do not double-spend',async t=>{
 const before={key:process.env.PETCLASS_API_SECRET,url:process.env.NEXT_PUBLIC_SUPABASE_URL,anon:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY};
 process.env.PETCLASS_API_SECRET='test-secret';process.env.NEXT_PUBLIC_SUPABASE_URL='https://fixture.invalid';process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='test-key';
 const s=user('s');const d={className:'test',users:[s]};act(d,'s','choosePet',{speciesId:'seedfox'});s.pets[0].level=3;
 const state={user:s,pets:s.pets,inventory:[],claimedStarter:true,version:0,products:[]};let committed=0,replay=null;
 t.mock.method(globalThis,'fetch',async(_url,options)=>{const {p_action,p_body}=JSON.parse(options.body);if(p_action==='request')return Response.json(replay);if(p_action==='state')return Response.json(state);assert.equal(p_action,'commit');assert.equal(p_body.version,state.version);state.pets=JSON.parse(JSON.stringify(p_body.data.pets));state.version++;committed++;replay={state,message:p_body.message};return Response.json(replay);});
 try{const body={action:'allocateStats',petId:s.pets[0].id,allocation:{...emptyStats(),hp:2,speed:2},requestId:crypto.randomUUID()};const result=await farmAction('fixture',body);assert.equal(result.state.pets[0].statAllocation.speed,2);await farmAction('fixture',body);assert.equal(committed,1);assert.equal(statTotal(state.pets[0].statAllocation),4);}
 finally{for(const [name,value] of [['PETCLASS_API_SECRET',before.key],['NEXT_PUBLIC_SUPABASE_URL',before.url],['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',before.anon]]){if(value===undefined)delete process.env[name];else process.env[name]=value;}}
});
