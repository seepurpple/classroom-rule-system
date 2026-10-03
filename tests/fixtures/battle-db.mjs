// Battle gateway + TypeScript engine integration, local PGlite only.
// Shared battle fixture: no network and no production data.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

const root = new URL("../../", import.meta.url);
const sql = p => readFileSync(new URL(p, root), "utf8");
const db = new PGlite();
await db.exec(sql("tests/db/pre-p1-schema.sql"));
await db.exec(`
alter table auth.users add column encrypted_password text, add column instance_id uuid, add column aud text, add column role text,
  add column email_confirmed_at timestamptz, add column raw_app_meta_data jsonb, add column updated_at timestamptz, add column confirmation_token text,
  add column recovery_token text, add column email_change_token_new text, add column email_change text, add column last_sign_in_at timestamptz, add column deleted_at timestamptz;
create table auth.identities(id uuid primary key default gen_random_uuid(),provider_id text not null,user_id uuid not null references auth.users on delete cascade,identity_data jsonb not null,provider text not null,last_sign_in_at timestamptz,created_at timestamptz,updated_at timestamptz);
create function extensions.gen_salt(t text,r int) returns text language sql as $$ select 'stub$' $$;
insert into auth.users(email,encrypted_password) values('seepurpple@gmail.com',extensions.crypt('admin-pass',extensions.gen_salt('bf'))),('202606@jeonnong.ms.kr',extensions.crypt('teacher-pass',extensions.gen_salt('bf')));
insert into private.petclass_config(key_hash) values(encode(extensions.digest('K','sha256'),'hex'));
insert into public.classroom_settings(id,application_deadline,teacher_password_hash) values(1,now()-interval '1 day',extensions.crypt('2456',extensions.gen_salt('bf')));
insert into public.classroom_roles values('leader','반장',2,900,1),('reading','다독이',2,350,4),('clean','깔끔이',3,400,5);
insert into public.classroom_students(student_no,access_code,role_id) select n,case when n=0 then '2456' else (1000+n*37)::text end,case n when 1 then 'leader' else null end from generate_series(0,25) n;
insert into public.point_entries(student_id,delta,title) select id,5000,'시작' from public.classroom_students;
insert into public.classroom_shop_items(id,name,price,note,icon,sort_order) values('food-s','별빛 한입',30,'','',1),('seat','학급 자리 선정권',1200,'','',2);
insert into private.petclass_products values('food-s','food',30);
insert into private.petclass_games(id,price,prizes) values('claw',700,'[{"name":"사탕","weight":100}]'),('gacha',1000,'[{"name":"사탕","weight":100}]'),('timing',500,'[]');
`);
await db.exec(sql("supabase/migrations/20261003130000_p1_class_scope.sql"));
await db.exec(sql("supabase/migrations/20261003150000_p2_accounts_classes.sql"));

await db.exec(sql("supabase/migrations/20261003160000_mock_battles_tournaments.sql"));
const g=async(action,token,body={})=>(await db.query("select public.petclass_gateway('K',$1,$2,$3::jsonb) r",[action,token,JSON.stringify(body)])).rows[0].r;
const one=async(q,p=[])=>(await db.query(q,p)).rows[0];
const cls=(await one("select id from private.classes")).id;
const login=async n=>(await g('login','',{code:String(1000+n*37),classId:cls,ip:'fixture'+n})).token;
const tokens=await Promise.all([1,2,3].map(login));
const actors=await Promise.all(tokens.map(async t=>(await g('battleLobby',t)).user));
const teacher=(await g('teacherLogin','',{email:'202606@jeonnong.ms.kr',password:'teacher-pass',ip:'fixture'})).token;
const pet=(id,speciesId,representative=false)=>({id,speciesId,level:20,stage:3,xp:0,skills:[],representative,createdAt:''});
for(let i=0;i<3;i++)await db.query("insert into private.petclass_farms(student_id,data) values($1,$2) on conflict(student_id) do update set data=excluded.data",[actors[i].id,JSON.stringify({pets:[pet(`p${i}a`,'seedfox',true),pet(`p${i}b`,'bubblepenguin')],inventory:[],claimedStarter:true})]);
const {build}=await import('esbuild');
const bundle=await build({stdin:{contents:'export * from "./lib/battle-backend.ts";export * from "./lib/duels.ts";',resolveDir:process.cwd(),loader:'ts'},bundle:true,write:false,format:'esm',platform:'node'});
const {battleAction,advanceDuel,startDuel}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
process.env.PETCLASS_API_SECRET='K';process.env.NEXT_PUBLIC_SUPABASE_URL='https://fixture.invalid';process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='fixture';
globalThis.fetch=async(url,options)=>{assert.equal(url,'https://fixture.invalid/rest/v1/rpc/petclass_gateway');const {p_action,p_token,p_body}=JSON.parse(options.body);try{return Response.json(await g(p_action,p_token,p_body));}catch(e){return Response.json({message:e.message},{status:400});}};
const action=(token,name,args={})=>battleAction(token,{action:name,requestId:crypto.randomUUID(),...args});

export { db,g,one,cls,tokens,actors,teacher,pet,action,battleAction,startDuel,advanceDuel };
