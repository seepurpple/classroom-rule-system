import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import fs from 'node:fs';
const bundle=await build({stdin:{contents:'export * from "./lib/domain.ts";export * from "./lib/catalog.ts";export * from "./lib/backend.ts";export * from "./lib/stats.ts";export * from "./lib/skills.ts";export * from "./lib/battle.ts";',resolveDir:process.cwd(),loader:'ts'},bundle:true,write:false,format:'esm',platform:'node'});
const {addExperience,applyAction,SPECIES,ITEMS,payload,farmAction,emptyStats,earnedStatPoints,statLimit,statTotal,petStats,validAllocation,petTypes,learnedSkills,SPECIES_SKILLS,PET_TYPES,TYPE_CHART,rankMultiplier,typeMultiplier,createFighter,changeRanks,calculateDamage,resolveTurn}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const user=(id,role='student')=>({id,loginId:id,name:id,role,mustChangePassword:false,passwordHash:'',authVersion:1,claimedStarter:false,pets:[],inventory:[]});
const act=(d,a,action,args={})=>applyAction(d,a,{action,requestId:crypto.randomUUID(),...args});
test('browser cannot invoke internal commit, replay or legacy gateway commands',async()=>{for(const action of ['commit','request','legacy','state','unsupported'])await assert.rejects(farmAction('fake-session',{action,requestId:crypto.randomUUID(),data:{pets:[],inventory:[]}}),/지원하지 않는 작업/);});
test('12 species, two per existing type, 36 distinct forms and all 40 assets exist',()=>{assert.equal(SPECIES.length,12);assert.equal(new Set(SPECIES.map(s=>s.id)).size,12);assert.deepEqual(Object.fromEntries(["풀","물","불","비행","땅","빛"].map(t=>[t,SPECIES.filter(s=>s.type===t).length])),{"풀":2,"물":2,"불":2,"비행":2,"땅":2,"빛":2});assert.equal(new Set(SPECIES.flatMap(s=>s.forms)).size,36);for(const s of SPECIES)for(let n=1;n<=3;n++)assert.ok(fs.statSync(`public/assets/pets/${s.id}-${n}.webp`).size>10000);assert.equal(ITEMS.length,4);for(const i of ITEMS)assert.ok(fs.existsSync(`public${i.image}`));});
test('growth evolves at 10/20, carries XP, caps at 30',()=>{assert.deepEqual(addExperience(9,110,30),{level:10,xp:20,stage:2});assert.deepEqual(addExperience(19,210,30),{level:20,xp:20,stage:3});assert.deepEqual(addExperience(29,300,240),{level:30,xp:0,stage:3});assert.throws(()=>addExperience(0,0,20));});
test('starter, ownership, three species, finite food and corrections',()=>{const d={className:'test',users:[user('t','teacher'),user('s'),user('other')]};act(d,'s','choosePet',{speciesId:'seedfox'});assert.throws(()=>act(d,'other','representative',{petId:d.users[1].pets[0].id}));act(d,'t','grant',{studentId:'s',sku:'pet-choice-ticket',quantity:3,reference:'ticket'});const ticket=d.users[1].inventory[0];for(const speciesId of ['bubblepenguin','glowmoth'])act(d,'s','choosePet',{speciesId,grantId:ticket.id});assert.throws(()=>act(d,'s','choosePet',{speciesId:'pebblemole',grantId:ticket.id}));assert.equal(ticket.remaining,1);assert.throws(()=>act(d,'s','grant',{studentId:'s',sku:'food-s',quantity:2,reference:'no'}));const pet=d.users[1].pets[1];act(d,'t','grant',{studentId:'s',sku:'food-s',quantity:2,reference:'food'});const food=d.users[1].inventory[1];act(d,'s','useItem',{petId:pet.id,grantId:food.id,quantity:2});assert.equal(pet.level,2);assert.equal(d.users[1].pets[0].level,1);assert.equal(food.remaining,0);assert.throws(()=>act(d,'s','useItem',{petId:pet.id,grantId:food.id,quantity:1}));});
test('same-origin JSON boundary rejects foreign origins and oversized requests',async()=>{await assert.rejects(payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'https://evil.test','content-type':'application/json'},body:'{}'})));await assert.rejects(payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'http://localhost','content-type':'application/json'},body:JSON.stringify({x:'x'.repeat(17000)})})));assert.deepEqual(await payload(new Request('http://localhost/api/farm',{method:'POST',headers:{origin:'http://localhost','content-type':'application/json'},body:'{"action":"logout"}'})),{action:'logout'});});

test('new species can be chosen and learn all skills through evolution',()=>{for(const species of SPECIES.slice(6)){const d={className:'test',users:[user('t','teacher'),user('s')]};act(d,'s','choosePet',{speciesId:species.id});const pet=d.users[1].pets[0];assert.equal(pet.speciesId,species.id);assert.deepEqual(pet.skills,[species.skills[0]]);assert.throws(()=>act(d,'s','choosePet',{speciesId:species.id}),/이미 키우고 있는 종/);for(const [level,stage] of [[10,2],[20,3]]){act(d,'t','adjustLevel',{studentId:'s',petId:pet.id,level,note:'진화 확인'});assert.equal(pet.stage,stage);assert.deepEqual(pet.skills,species.skills.slice(0,stage));}}});
test('release removes only the owner pet and moves representative',()=>{const d={className:'test',users:[user('t','teacher'),user('s'),user('other')]};const s=d.users[1];s.inventory.push({id:'tk',sku:'pet-choice-ticket',quantity:1,remaining:1,reference:'r',note:'',createdAt:'',revoked:false});act(d,'s','choosePet',{speciesId:'seedfox'});act(d,'s','choosePet',{speciesId:'bubblepenguin',grantId:'tk'});const [a,b]=s.pets;assert.ok(a.representative);assert.throws(()=>act(d,'other','release',{petId:a.id}));assert.throws(()=>act(d,'t','release',{petId:a.id}));act(d,'s','release',{petId:a.id});assert.deepEqual(s.pets.map(p=>p.id),[b.id]);assert.ok(b.representative);act(d,'s','release',{petId:b.id});assert.equal(s.pets.length,0);assert.ok(s.claimedStarter);});

test('base stats total 120 and growth budgets include a bonus for each evolution',()=>{
 for(const species of SPECIES){assert.equal(statTotal(species.baseStats),120);assert.ok(Object.values(species.baseStats).every(n=>Number.isInteger(n)&&n>0));}
 for(const [level,points,cap] of [[1,0,0],[2,3,1],[3,6,2],[9,24,9],[10,34,13],[19,61,24],[20,71,28],[30,101,40]]){assert.equal(earnedStatPoints(level),points);assert.equal(statLimit(level),cap);}
 assert.equal(earnedStatPoints(10)-earnedStatPoints(9),10);
 assert.equal(earnedStatPoints(20)-earnedStatPoints(19),10);
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

const fighter=(speciesId,id=speciesId,level=20)=>createFighter({id,speciesId,level,stage:level>=20?3:level>=10?2:1,skills:[],xp:0,createdAt:'',representative:false});
const skill=name=>Object.values(SPECIES_SKILLS).flat().find(s=>s.name===name);
const draws=(...values)=>()=>{assert.ok(values.length,'unexpected random draw');return values.shift();};
const inert=f=>{f.skills=[{name:'대기',type:'빛',category:'변화기',powers:[],accuracy:[100],description:''}];return f;};
test('36 skills, evolution types, old names and exact damage formula',()=>{
 assert.equal(Object.values(SPECIES_SKILLS).flat().length,36);
 for(const s of SPECIES){const list=SPECIES_SKILLS[s.id];assert.equal(list.length,3);for(const move of list){assert.ok(PET_TYPES.includes(move.type));assert.equal(move.accuracy.length,Math.max(1,move.powers.length));}
 const old={id:s.id,speciesId:s.id,level:20,stage:3,skills:[...s.legacySkills]};assert.deepEqual(learnedSkills(old),s.skills);assert.equal(createFighter(old).maxHp,s.baseStats.hp*3);}
 assert.deepEqual(petTypes('seedfox',3),['풀','땅']);assert.deepEqual(petTypes('bubblepenguin',2),['물','비행']);assert.deepEqual(petTypes('tidalray',3),['물','빛']);
 for(const row of Object.values(TYPE_CHART)){assert.equal(row.length,6);assert.ok(row.every(n=>[.5,1,2].includes(n)));}
 assert.equal(typeMultiplier('불',['물','불']),.25);
 assert.deepEqual(Array.from({length:9},(_,i)=>rankMultiplier(i-4)),[.1,.25,.5,.75,1,1.5,2,3,4.5]);
 const a=fighter('seedfox'),b=fighter('bubblepenguin');a.types=['풀'];b.types=['물'];a.stats.specialAttack=22;a.ranks.specialAttack=3;b.stats.specialDefense=17;
 const result=calculateDamage(a,b,{...skill('숲의 맥박'),powers:[50]},50,draws(.9,0,0));
 assert.deepEqual(result,{damage:45.2,critical:false,absoluteDefense:true,attack:79.2,defense:34});
 a.stats.attack=14;a.ranks.attack=2;a.types=['불'];b.types=['물','불'];b.stats.defense=0;
 assert.equal(calculateDamage(a,b,skill('화염 채찍'),40,draws(0,.9)).attack,10.08);
 b.stats.defense=999;assert.equal(calculateDamage(a,b,skill('화염 채찍'),40,()=>.9).damage,0);
 changeRanks(a,{attack:99,speed:-99});assert.equal(a.ranks.attack,4);assert.equal(a.ranks.speed,-4);
});
test('legacy skills rename during saves without duplicates',()=>{
 const d={className:'test',users:[user('s')]};act(d,'s','choosePet',{speciesId:'seedfox'});const p=d.users[0].pets[0];p.skills=['씨앗 찌르기'];act(d,'s','allocateStats',{petId:p.id,allocation:emptyStats()});assert.deepEqual(p.skills,['씨뱉기']);
});
test('each skill resolves with immutable inputs and finite bounded health',()=>{
 for(const s of SPECIES)for(const move of SPECIES_SKILLS[s.id]){
 const a=fighter(s.id),b=inert(fighter('pebblemole','target'));const before=structuredClone(a);
 const r=resolveTurn([a,b],[move.name,'대기'],()=>.4);assert.deepEqual(a,before);
 assert.ok(r.events.some(e=>e.skill===move.name));for(const f of r.fighters)assert.ok(Number.isFinite(f.hp)&&f.hp>=0&&f.hp<=f.maxHp);
 }
});
test('multi-hit stops on a miss, critical uses 60 percent for water gun, and recoil on a miss',()=>{
 const a=fighter('seedfox'),b=inert(fighter('pebblemole','target'));a.stats.speed=100;
 let r=resolveTurn([a,b],['씨뱉기','대기'],draws(0,.9,.5,.9,.95,0));assert.equal(r.events.filter(e=>e.kind==='hit').length,1);assert.equal(r.events.filter(e=>e.kind==='miss').length,1);
 const c=fighter('bubblepenguin');assert.equal(calculateDamage(c,b,skill('물총'),35,draws(.59,.9)).critical,true);
 const f=fighter('kitesquirrel');r=resolveTurn([f,b],['고공낙하','대기'],()=>.9);assert.equal(r.fighters[0].hp,f.hp-20);
});
test('guard has priority, lowers speed, and ignition ignores only absolute defense',()=>{
 const a=fighter('tidalray'),b=fighter('kilncrab');a.stats.speed=1;b.stats.speed=100;
 const r=resolveTurn([a,b],['물너울','불집기'],()=>.4);assert.equal(r.events[0].skill,'물너울');assert.equal(r.fighters[1].ranks.speed,-2);assert.equal(r.fighters[0].guard,false);
 a.guard=true;const damage=calculateDamage(b,a,skill('점화'),40,draws(.9,.5));assert.equal(damage.absoluteDefense,false);assert.equal(damage.defense,a.stats.specialDefense);
});
test('reflection blocks all hits, cannot repeat, and never recurses',()=>{
 const a=fighter('prismtortoise'),b=fighter('reedstork');b.stats.specialAttack=200;b.hp=b.maxHp=1000;
 let r=resolveTurn([a,b],['만화경','천계의 빛'],()=>.4);assert.equal(r.fighters[0].hp,a.hp);assert.ok(r.fighters[1].hp<b.hp);assert.ok(r.events.filter(e=>e.kind==='hit').every(e=>e.reflected));
 r=resolveTurn(r.fighters,['만화경','활공'],()=>.4);assert.ok(r.events.some(e=>e.skill==='만화경'&&e.kind==='failed'));
});
test('dot lasts three turn ends, refreshes, and battle stops after a knockout',()=>{
 const a=fighter('tidalray'),b=inert(fighter('pebblemole','target'));b.hp=b.maxHp=1000;
 let r=resolveTurn([a,b],['낙조','대기'],()=>.4);assert.equal(r.fighters[1].dot.turns,2);
 r=resolveTurn(r.fighters,['물너울','대기'],()=>.4);assert.equal(r.fighters[1].dot.turns,1);
 r=resolveTurn(r.fighters,['물너울','대기'],()=>.4);assert.equal(r.fighters[1].dot,undefined);
 b.hp=1;b.stats.specialDefense=0;r=resolveTurn([a,b],['낙조','대기'],()=>.4);assert.equal(r.winner,a.id);assert.equal(r.events.some(e=>e.kind==='dot'),false);assert.throws(()=>resolveTurn(r.fighters,['낙조','대기']));
});
test('recharge skips one turn, consecutive moves fail, rank clearing preserves debuffs',()=>{
 const a=fighter('mossmushroom'),b=inert(fighter('pebblemole','target'));b.hp=b.maxHp=1000;
 let r=resolveTurn([a,b],['생명의 샘','대기'],()=>.4);assert.equal(r.fighters[0].recharge,true);
 r=resolveTurn(r.fighters,['홀씨','대기'],()=>.4);assert.ok(r.events.some(e=>e.kind==='recharge'));assert.equal(r.fighters[0].recharge,false);
 const c=fighter('pebblemole');r=resolveTurn([c,b],['주상절리','대기'],()=>.4);r=resolveTurn(r.fighters,['주상절리','대기'],()=>.4);assert.equal(r.fighters[0].ranks.defense,2);assert.ok(r.events.some(e=>e.kind==='failed'));
 b.ranks.attack=3;b.ranks.speed=-2;r=resolveTurn([fighter('claygolem'),b],['재어넣기','대기'],()=>.4);assert.equal(r.fighters[1].ranks.attack,0);assert.equal(r.fighters[1].ranks.speed,-2);
});
test('drain uses actual lost HP, defense ranks count, type bypass keeps STAB',()=>{
 const a=fighter('seedfox'),b=inert(fighter('pebblemole','target'));a.hp=1;a.stats.speed=100;a.stats.specialAttack=1000;b.hp=5;
 const r=resolveTurn([a,b],['숲의 맥박','대기'],()=>.4);assert.equal(r.fighters[0].hp,2.5);
 b.ranks.defense=2;const d=calculateDamage(a,b,skill('염무'),90,()=>.9);assert.equal(d.defense,b.stats.defense*2);
 const c=fighter('embersalamander');const x=calculateDamage(c,b,skill('염무'),90,()=>.5);assert.equal(x.attack,c.stats.attack*.9*1.5);
 assert.throws(()=>resolveTurn([a,b],['미등록','대기']),/배우지 않은/);
});
