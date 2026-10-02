-- Shop mini games: claw machine, gacha, timing challenge.
create table if not exists private.petclass_games(id text primary key check(id in('claw','gacha','timing')),price int not null check(price between 1 and 100000),prizes jsonb not null default '[]',item text,total int,remaining int,seconds numeric(5,2),precision numeric(3,2),active boolean not null default false);
insert into private.petclass_games(id,price,prizes) values
('claw',700,'[{"name":"간식 1개","weight":50},{"name":"간식 2개","weight":30},{"name":"간식 3개","weight":15},{"name":"Big 간식","weight":5}]'),
('gacha',1000,'[{"name":"간식 1개","weight":60},{"name":"간식 2개","weight":30},{"name":"Big 간식","weight":10}]'),
('timing',500,'[]') on conflict(id) do nothing;
create table if not exists private.petclass_game_plays(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id),game text not null,price int not null,point_entry_id uuid not null references public.point_entries(id),request_id text unique,status text not null default 'pending',result text,target numeric(5,2),precision numeric(3,2),started_at timestamptz,elapsed numeric(8,3),created_at timestamptz not null default now());
create index if not exists petclass_game_plays_student on private.petclass_game_plays(student_id,created_at desc);
alter table private.petclass_games enable row level security;
alter table private.petclass_game_plays enable row level security;
revoke all on private.petclass_games,private.petclass_game_plays from public,anon,authenticated;


-- Test student (student_no 0): hidden from students, not counted in class stats, starts at 100,000P, no role.
insert into public.classroom_students(student_no,access_code,role_id)
select 0,(select lpad(n::text,4,'0') from generate_series(1000,9999) n where lpad(n::text,4,'0') not in(select access_code from public.classroom_students where access_code is not null) order by random() limit 1),null
where not exists(select 1 from public.classroom_students where student_no=0);
update public.classroom_students set role_id=null where student_no=0;
insert into public.point_entries(student_id,delta,title,detail)
select s.id,100000-coalesce(sum(p.delta),0),'테스트 계정 포인트 맞춤','테스트 계정 전용'
from public.classroom_students s left join public.point_entries p on p.student_id=s.id
where s.student_no=0 group by s.id having coalesce(sum(p.delta),0)<>100000;

create or replace function private.pc_actor(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess private.petclass_sessions;s public.classroom_students;
begin
 select * into sess from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and expires_at>now();
 if not found then return null;end if;
 if sess.teacher_token is not null then
  if not exists(select 1 from public.teacher_sessions where token=sess.teacher_token and expires_at>now()) then return null;end if;
  return jsonb_build_object('id','teacher','role','teacher','name','선생님','loginId','teacher','mustChangePassword',false,'teacherToken',sess.teacher_token);
 end if;
 select * into s from public.classroom_students where id=sess.student_id and student_no>=0;
 if not found or encode(extensions.digest(s.access_code,'sha256'),'hex')<>sess.code_hash then return null;end if;
 return jsonb_build_object('id',s.id,'role','student','name',case when s.student_no=0 then '테스트 학생' else lpad(s.student_no::text,2,'0')||'번 학생' end,'loginId',s.student_no::text,'studentNo',s.student_no,'mustChangePassword',false);
end$$;
create or replace function private.pc_student(s public.classroom_students) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'studentNo',s.student_no,'name',case when s.student_no=0 then '테스트 학생' else lpad(s.student_no::text,2,'0')||'번 학생' end,'loginId',s.student_no::text,'role','student','mustChangePassword',false,'balance',coalesce((select sum(delta) from public.point_entries where student_id=s.id),0),'version',coalesce((select version from private.petclass_farms where student_id=s.id),0)) || coalesce((select data from private.petclass_farms where student_id=s.id),'{"pets":[],"inventory":[],"claimedStarter":false}'::jsonb);
$$;
revoke all on function private.pc_actor(text),private.pc_student(public.classroom_students) from public,anon,authenticated;

create or replace function private.pc_roll(p jsonb) returns text language plpgsql set search_path='' as $$
declare r numeric:=random()*100;acc numeric:=0;e jsonb;
begin
 for e in select value from jsonb_array_elements(p) loop acc:=acc+(e->>'weight')::numeric;if r<acc then return e->>'name';end if;end loop;
 return p->-1->>'name';
end$$;
revoke all on function private.pc_roll(jsonb) from public,anon,authenticated;

create or replace function private.pc_state(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb:=private.pc_actor(p_token);v jsonb:='{}';sid uuid;
begin
 if a->>'role'='student' then sid:=(a->>'id')::uuid;select private.pc_student(s) into v from public.classroom_students s where id=sid;end if;
 return jsonb_build_object('needsSetup',false,'className','1학년 3반','user',a-'teacherToken','balance',coalesce(v->'balance','0'),'version',coalesce(v->'version','0'),'claimedStarter',coalesce(v->'claimedStarter','false'),'pets',coalesce(v->'pets','[]'),'inventory',coalesce(v->'inventory','[]'),
 'students',case when a->>'role'='teacher' then coalesce((select jsonb_agg(private.pc_student(s) order by student_no=0,student_no) from public.classroom_students s where student_no>=0),'[]') else '[]' end,
 'products',coalesce((select jsonb_agg(jsonb_build_object('sku',i.id,'name',i.name,'price',i.price,'description',i.note,'kind',coalesce(p.kind,'classroom'),'xp',p.xp,'archived',i.archived,'image',case when i.image is null then null else '/api/shop-image?sku='||i.id||'&v='||left(md5(i.image),10) end) order by i.sort_order nulls last,i.price) from public.classroom_shop_items i left join private.petclass_products p on p.sku=i.id),'[]'),
 'ledger',case when a is not null then coalesce((select jsonb_agg(to_jsonb(e) order by e."createdAt" desc) from (select p.id,s.student_no as "studentNo",p.delta,p.title,p.detail,p.created_at as "createdAt" from public.point_entries p join public.classroom_students s on s.id=p.student_id where (s.student_no>0 or s.id=sid) and (a->>'role'='teacher' or s.id=sid) order by p.created_at desc limit 300)e),'[]') else '[]' end,
 'orders',case when a is not null then coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from(select o.*,s.student_no from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where a->>'role'='teacher' or o.student_id=sid order by o.created_at desc limit 150)o),'[]') else '[]' end,
 'logs',case when a is not null then coalesce((select jsonb_agg(to_jsonb(l) order by l."createdAt" desc) from(select id,student_id as "studentId",actor as "actorName",message,created_at as "createdAt" from private.petclass_logs where a->>'role'='teacher' or student_id=sid order by created_at desc limit 150)l),'[]') else '[]' end,'games',(select jsonb_object_agg(id,jsonb_build_object('price',price,'prizes',prizes,'item',item,'total',total,'remaining',remaining,'seconds',seconds,'precision',precision,'active',active and coalesce(remaining,0)>0)) from private.petclass_games),
 'gamePlays',case when a is not null then coalesce((select jsonb_agg(to_jsonb(g) order by g."createdAt" desc) from(select gp.id,s.student_no as "studentNo",gp.game,gp.price,gp.status,gp.result,gp.elapsed,gp.target,gp.created_at as "createdAt" from private.petclass_game_plays gp join public.classroom_students s on s.id=gp.student_id where a->>'role'='teacher' or gp.student_id=sid order by gp.created_at desc limit 150)g),'[]') else '[]' end,'updatedAt',now());
end$$;

create or replace function public.petclass_gateway(p_key text,p_action text,p_token text,p_body jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare gm private.petclass_games;gp private.petclass_game_plays;secs numeric;won boolean;a jsonb;sid uuid;student public.classroom_students;tok text;th uuid;lim int;f private.petclass_farms;req text;fp text;previous private.petclass_requests;item public.classroom_shop_items;qty int;bal bigint;oid uuid;eid uuid;note text;lot jsonb;ord private.petclass_orders;remaining int;target jsonb;
begin
 if not exists(select 1 from private.petclass_config where key_hash=encode(extensions.digest(coalesce(p_key,''),'sha256'),'hex')) then raise exception '서버 인증 실패';end if;
 if p_body is null or jsonb_typeof(p_body)<>'object' then raise exception '요청 형식을 확인해 주세요.';end if;
 if p_action='login' then
  if p_body->>'code' !~ '^[0-9]{4}$' or p_body->>'role' not in('student','teacher') then return jsonb_build_object('error','고유 번호를 확인해 주세요.','status',400);end if;
  insert into private.petclass_attempts values(p_body->>'limiter',1,now()+interval '15 minutes') on conflict(id) do update set attempts=case when petclass_attempts.expires_at<=now() then 1 else petclass_attempts.attempts+1 end,expires_at=case when petclass_attempts.expires_at<=now() then now()+interval '15 minutes' else petclass_attempts.expires_at end returning attempts into lim;
  if lim>15 then return jsonb_build_object('error','로그인 시도가 많아요. 15분 뒤 다시 시도해 주세요.','status',429);end if;
  if p_body->>'role'='student' then
   select * into student from public.classroom_students where access_code=p_body->>'code' and student_no>=0;
   if not found then return jsonb_build_object('error','고유 번호를 다시 확인해 주세요.','status',401);end if;
   sid:=student.id;
  else
   begin target:=public.teacher_login(p_body->>'code');th:=(target->>'token')::uuid;
   exception when others then return jsonb_build_object('error','교사 비밀번호를 다시 확인해 주세요.','status',401);end;
  end if;
  tok:=gen_random_uuid()::text||gen_random_uuid()::text;
  delete from private.petclass_sessions where expires_at<=now();
  insert into private.petclass_sessions values(encode(extensions.digest(tok,'sha256'),'hex'),sid,case when sid is not null then encode(extensions.digest(student.access_code,'sha256'),'hex') end,th,now()+interval '2 hours');
  delete from private.petclass_attempts where id=p_body->>'limiter';
  return jsonb_build_object('token',tok,'state',private.pc_state(tok));
 end if;
 a:=private.pc_actor(p_token);
 if p_action='state' then return private.pc_state(p_token);end if;
 if p_action='logout' then
  delete from public.teacher_sessions where token=(a->>'teacherToken')::uuid;
  delete from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');return '{}'::jsonb;
 end if;
 if p_action='legacy' then return private.pc_legacy(a,p_body->>'name',coalesce(p_body->'args','{}'));end if;
 if p_action='productImage' then return jsonb_build_object('image',(select image from public.classroom_shop_items where id=p_body->>'sku'));end if;
 if a is null then return jsonb_build_object('error','다시 로그인해 주세요.','status',401);end if;
 if p_action='price' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  if (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
  update public.classroom_shop_items set price=(p_body->>'price')::int where id=p_body->>'sku' and not archived;
  if not found then raise exception '상품을 확인해 주세요.';end if;
  return jsonb_build_object('state',private.pc_state(p_token),'message','상품 가격을 저장했어요.');
 end if;
 if p_action in('addProduct','removeProduct','reorderProducts') then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  if p_action='addProduct' then
   if length(btrim(coalesce(p_body->>'name',''))) not between 1 and 40 then raise exception '상품 이름은 1~40자로 입력해 주세요.';end if;
   if length(coalesce(p_body->>'description',''))>80 then raise exception '설명은 80자까지 입력할 수 있어요.';end if;
   if coalesce(p_body->>'price','') !~ '^[0-9]{1,6}$' or (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
   if coalesce(p_body->>'category','') not in('pet','classroom') then raise exception '상품 종류를 확인해 주세요.';end if;
   if p_body->>'category'='pet' and (coalesce(p_body->>'xp','') !~ '^[0-9]{1,5}$' or (p_body->>'xp')::int not between 1 and 10000) then raise exception '경험치는 1~10,000 사이로 입력해 주세요.';end if;
   if p_body->>'image' is not null and (length(p_body->>'image')>400000 or p_body->>'image' !~ '^data:image/(webp|png|jpeg);base64,[A-Za-z0-9+/=]+$') then raise exception '이미지를 확인해 주세요.';end if;
   note:='custom-'||left(replace(gen_random_uuid()::text,'-',''),12);
   insert into public.classroom_shop_items(id,name,price,note,icon,image,sort_order) values(note,btrim(p_body->>'name'),(p_body->>'price')::int,coalesce(btrim(p_body->>'description'),''),'✦',p_body->>'image',(select coalesce(max(sort_order),0)+1 from public.classroom_shop_items));
   if p_body->>'category'='pet' then insert into private.petclass_products(sku,kind,xp) values(note,'food',(p_body->>'xp')::int);end if;
   note:=btrim(p_body->>'name')||' 상품을 추가했어요.';
  elsif p_action='removeProduct' then
   update public.classroom_shop_items set archived=true where id=p_body->>'sku' and not archived returning name into note;
   if not found then raise exception '상품을 찾을 수 없어요.';end if;
   note:=note||' 상품을 삭제했어요.';
  else
   if jsonb_typeof(p_body->'skus')<>'array' then raise exception '순서를 확인해 주세요.';end if;
   update public.classroom_shop_items i set sort_order=o.n from jsonb_array_elements_text(p_body->'skus') with ordinality o(sku,n) where i.id=o.sku;
   note:='상품 순서를 저장했어요.';
  end if;
  insert into private.petclass_logs(student_id,actor,message) values(null,a->>'name',note);
  return jsonb_build_object('state',private.pc_state(p_token),'message',note);
 end if;
 if p_action in('gameConfig','gameTiming','gamePlay','gameResult','timingStart','timingStop') then
  if p_action in('gameConfig','gameTiming') then
   if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
   if p_action='gameConfig' then
    if coalesce(p_body->>'game','') not in('claw','gacha') then raise exception '게임을 확인해 주세요.';end if;
    if p_body ? 'price' then
     if coalesce(p_body->>'price','') !~ '^[0-9]{1,6}$' or (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
     update private.petclass_games set price=(p_body->>'price')::int where id=p_body->>'game';note:='가격을 저장했어요.';
    end if;
    if p_body ? 'prizes' then
     if jsonb_typeof(p_body->'prizes')<>'array' or jsonb_array_length(p_body->'prizes') not between 1 and 20 then raise exception '등장할 아이템을 1~20개로 정해 주세요.';end if;
     if exists(select 1 from jsonb_array_elements(p_body->'prizes') e where length(btrim(coalesce(e->>'name',''))) not between 1 and 30 or coalesce(e->>'weight','') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (e->>'weight')::numeric<=0) then raise exception '아이템 이름과 확률을 확인해 주세요.';end if;
     if (select sum((e->>'weight')::numeric) from jsonb_array_elements(p_body->'prizes') e)<>100 then raise exception '확률 합계가 100%%가 되어야 해요.';end if;
     update private.petclass_games set prizes=(select jsonb_agg(jsonb_build_object('name',btrim(e->>'name'),'weight',(e->>'weight')::numeric) order by n) from jsonb_array_elements(p_body->'prizes') with ordinality x(e,n)) where id=p_body->>'game';note:='확률을 저장했어요.';
    end if;
    if note is null then raise exception '변경할 내용을 확인해 주세요.';end if;
   elsif coalesce(p_body->>'active','true')='false' then
    update private.petclass_games set active=false where id='timing';note:='시간 맞추기를 내렸어요.';
   else
    if length(btrim(coalesce(p_body->>'item',''))) not between 1 and 30 then raise exception '상품 이름은 1~30자로 입력해 주세요.';end if;
    if coalesce(p_body->>'total','') !~ '^[0-9]{1,3}$' or (p_body->>'total')::int not between 1 and 100 then raise exception '갯수는 1~100개로 입력해 주세요.';end if;
    if coalesce(p_body->>'price','') !~ '^[0-9]{1,6}$' or (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
    if coalesce(p_body->>'precision','') not in('0.1','0.01') then raise exception '판정 단위를 확인해 주세요.';end if;
    if coalesce(p_body->>'seconds','') !~ '^[0-9]{1,2}([.][0-9]{1,2})?$' or (p_body->>'seconds')::numeric not between 1 and 60 then raise exception '시간은 1~60초로 입력해 주세요.';end if;
    if (p_body->>'precision')='0.1' and (p_body->>'seconds')::numeric<>round((p_body->>'seconds')::numeric,1) then raise exception '0.1초 단위면 시간도 소수 첫째 자리까지 입력해 주세요.';end if;
    update private.petclass_games set item=btrim(p_body->>'item'),total=(p_body->>'total')::int,remaining=(p_body->>'total')::int,price=(p_body->>'price')::int,seconds=(p_body->>'seconds')::numeric,precision=(p_body->>'precision')::numeric,active=true where id='timing';
    note:='시간 맞추기를 등록했어요.';
   end if;
   insert into private.petclass_logs(student_id,actor,message) values(null,a->>'name',note);
   return jsonb_build_object('state',private.pc_state(p_token),'message',note);
  end if;
  if a->>'role'<>'student' then raise exception '학생 계정으로 참여해 주세요.';end if;
  sid:=(a->>'id')::uuid;
  perform 1 from public.classroom_students where id=sid and student_no>=0 for update;
  if not found then raise exception '학생을 찾을 수 없어요.';end if;
  if p_action='gamePlay' then
   if coalesce(p_body->>'requestId','') !~ '^[a-zA-Z0-9-]{12,80}$' then raise exception '요청 번호를 확인해 주세요.';end if;
   select * into gp from private.petclass_game_plays where request_id=(a->>'id')||':'||(p_body->>'requestId');
   if not found and p_body->>'game' in('claw','timing') then
    select * into gp from private.petclass_game_plays where student_id=sid and game=p_body->>'game' and status='pending' and created_at>now()-interval '10 minutes' order by created_at desc limit 1;
   end if;
   if found then return jsonb_build_object('state',private.pc_state(p_token),'play',to_jsonb(gp),'message','이어서 진행해요.');end if;
   select * into gm from private.petclass_games where id=p_body->>'game' for update;
   if not found then raise exception '게임을 찾을 수 없어요.';end if;
   if gm.id='timing' and not (gm.active and gm.remaining>0) then raise exception '지금은 시간 맞추기 상품이 없어요.';end if;
   if (p_body->>'expectedPrice')::int is distinct from gm.price then raise exception '가격이 바뀌었어요. 새로고침 후 다시 확인해 주세요.';end if;
   select coalesce(sum(delta),0) into bal from public.point_entries where student_id=sid;
   if bal<gm.price then raise exception '포인트가 부족해요.';end if;
   insert into public.point_entries(student_id,delta,title,detail) values(sid,-gm.price,case gm.id when 'claw' then '뽑기' when 'gacha' then '랜덤박스' else '시간 맞추기' end,'미니게임 참여') returning id into eid;
   insert into private.petclass_game_plays(student_id,game,price,point_entry_id,request_id,target,precision) values(sid,gm.id,gm.price,eid,(a->>'id')||':'||(p_body->>'requestId'),case when gm.id='timing' then gm.seconds end,case when gm.id='timing' then gm.precision end) returning * into gp;
   if gm.id='gacha' then update private.petclass_game_plays set status='won',result=private.pc_roll(gm.prizes) where id=gp.id returning * into gp;end if;
   note:=case gm.id when 'claw' then '뽑기' when 'gacha' then '랜덤박스' else '시간 맞추기' end||' 참여 · '||gm.price||'P'||case when gp.result is not null then ' · '||gp.result else '' end;
  else
   select * into gp from private.petclass_game_plays where id=(p_body->>'playId')::uuid and student_id=sid and status='pending' for update;
   if not found then raise exception '이미 끝난 게임이에요.';end if;
   if p_action='gameResult' then
    if gp.game<>'claw' then raise exception '게임을 확인해 주세요.';end if;
    if coalesce(p_body->>'grabbed','')='true' then
     select * into gm from private.petclass_games where id='claw';
     update private.petclass_game_plays set status='won',result=private.pc_roll(gm.prizes) where id=gp.id returning * into gp;
    else update private.petclass_game_plays set status='lost',result='놓침' where id=gp.id returning * into gp;end if;
    note:='뽑기 결과 · '||gp.result;
   elsif p_action='timingStart' then
    if gp.game<>'timing' or gp.started_at is not null then raise exception '이미 시작한 게임이에요.';end if;
    update private.petclass_game_plays set started_at=clock_timestamp() where id=gp.id returning * into gp;
    return jsonb_build_object('state',private.pc_state(p_token),'play',to_jsonb(gp));
   else
    if gp.game<>'timing' or gp.started_at is null then raise exception '먼저 시작해 주세요.';end if;
    secs:=extract(epoch from clock_timestamp()-gp.started_at);
    won:=round(secs/gp.precision)=round(gp.target/gp.precision);
    if won and exists(select 1 from public.classroom_students where id=sid and student_no=0) then
     select * into gm from private.petclass_games where id='timing';
    elsif won then
     update private.petclass_games g set remaining=g.remaining-1,active=g.remaining-1>0 where g.id='timing' and g.active and g.remaining>0 returning g.* into gm;
     if not found then won:=false;end if;
    end if;
    update private.petclass_game_plays set status=case when won then 'won' else 'lost' end,result=case when won then gm.item else '실패' end,elapsed=round(secs,3) where id=gp.id returning * into gp;
    note:='시간 맞추기 '||to_char(gp.elapsed,'FM990.00')||'초 · '||gp.result;
   end if;
  end if;
  insert into private.petclass_logs(student_id,actor,message) values(sid,a->>'name',note);
  return jsonb_build_object('state',private.pc_state(p_token),'play',to_jsonb(gp),'message',note);
 end if;
 if p_action='request' then
  select * into previous from private.petclass_requests where id=(a->>'id')||':'||(p_body->>'requestId');
  if not found then return 'null'::jsonb;end if;
  if previous.fingerprint<>p_body->>'fingerprint' then raise exception '같은 요청 번호로 다른 작업을 보낼 수 없어요.';end if;
  return jsonb_build_object('state',private.pc_state(p_token),'message',previous.message);
 end if;
 if p_action in('commit','purchase','refund','points') then
  if coalesce(p_body->>'requestId','') !~ '^[a-zA-Z0-9-]{12,80}$' then raise exception '요청 번호를 확인해 주세요.';end if;
  req:=(a->>'id')||':'||(p_body->>'requestId');
  fp:=case when p_action='commit' then p_body->>'fingerprint' else encode(extensions.digest((p_body-'requestId')::text||p_action,'sha256'),'hex') end;
  perform pg_advisory_xact_lock(hashtextextended(req,0));
  select * into previous from private.petclass_requests where id=req;
  if found then
   if previous.fingerprint<>fp then raise exception '같은 요청 번호로 다른 작업을 보낼 수 없어요.';end if;
   return jsonb_build_object('state',private.pc_state(p_token),'message',previous.message);
  end if;
 end if;
 if p_action='points' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  if (p_body->>'delta')::int=0 or abs((p_body->>'delta')::bigint)>100000 or length(btrim(coalesce(p_body->>'title','')))=0 then raise exception '포인트와 사유를 확인해 주세요.';end if;
  if jsonb_array_length(p_body->'studentIds') not between 1 and 100 then raise exception '학생을 선택해 주세요.';end if;
  for sid in select id from public.classroom_students where student_no>0 and id in(select value::uuid from jsonb_array_elements_text(p_body->'studentIds')) order by id for update loop
   insert into public.point_entries(student_id,delta,title,detail) values(sid,(p_body->>'delta')::int,left(p_body->>'title',40),'교사 포인트 지급·차감');
  end loop;
  note:='선택 학생 포인트를 기록했어요.';
 elsif p_action='refund' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  select * into ord from private.petclass_orders where id=(p_body->>'orderId')::uuid;
  if not found then raise exception '구매 기록을 확인해 주세요.';end if;
  sid:=ord.student_id;perform 1 from public.classroom_students where id=sid for update;
  select * into f from private.petclass_farms where student_id=sid;
  select value into lot from jsonb_array_elements(f.data->'inventory') where value->>'id'=ord.id::text;
  remaining:=coalesce((lot->>'remaining')::int,0);
  if remaining<1 or ord.refunded_quantity>0 then raise exception '환불 가능한 미사용 아이템이 없어요.';end if;
  if length(btrim(coalesce(p_body->>'note','')))<2 then raise exception '환불 사유를 입력해 주세요.';end if;
  insert into public.point_entries(student_id,delta,title,detail) values(sid,remaining*ord.unit_price,'펫 아이템 환불',left(p_body->>'note',80)) returning id into eid;
  update private.petclass_orders set refund_entry_id=eid,refunded_quantity=remaining where id=ord.id;
  update private.petclass_farms set data=jsonb_set(data,'{inventory}',(select jsonb_agg(case when value->>'id'=ord.id::text then value||'{"remaining":0,"revoked":true}'::jsonb else value end) from jsonb_array_elements(data->'inventory'))),version=version+1 where student_id=sid;
  note:='미사용 '||remaining||'개 환불 · '||(remaining*ord.unit_price)||'P 반환';
 elsif p_action in('commit','purchase') then
  if p_action='purchase' and a->>'role'<>'student' then raise exception '학생 계정으로 구매해 주세요.';end if;
  sid:=case when a->>'role'='student' then (a->>'id')::uuid else (p_body->>'studentId')::uuid end;
  perform 1 from public.classroom_students where id=sid and student_no>=0 for update;
  if not found then raise exception '학생을 찾을 수 없어요.';end if;
  insert into private.petclass_farms(student_id) values(sid) on conflict do nothing;
  select * into f from private.petclass_farms where student_id=sid;
  if p_action='commit' then
   if f.version<>(p_body->>'version')::int then return jsonb_build_object('error','상태가 변경됐어요. 다시 시도해 주세요.','status',409);end if;
   if jsonb_typeof(p_body->'data'->'pets')<>'array' or jsonb_array_length(p_body->'data'->'pets')>3 or jsonb_typeof(p_body->'data'->'inventory')<>'array' then raise exception '펫 저장 내용을 확인해 주세요.';end if;
   update private.petclass_farms set data=p_body->'data',version=version+1 where student_id=sid;note:=p_body->>'message';
  else
   qty:=(p_body->>'quantity')::int;if qty is null or qty not between 1 and 99 then raise exception '수량은 1~99개로 입력해 주세요.';end if;
   select * into item from public.classroom_shop_items where id=p_body->>'sku' for share;
   if not found then raise exception '상품을 찾을 수 없어요.';end if;
   if item.archived then raise exception '판매가 끝난 상품이에요.';end if;
   if (p_body->>'expectedPrice')::int is distinct from item.price then raise exception '상품 가격이 바뀌었어요. 새로고침 후 다시 확인해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')=0 then raise exception '첫 무료 펫을 먼저 선택해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')+coalesce((select sum((g->>'remaining')::int) from jsonb_array_elements(f.data->'inventory')g where g->>'sku'='pet-choice-ticket' and not (g->>'revoked')::boolean),0)+qty>3 then raise exception '보유 펫과 미사용 선택권을 합해 최대 3마리예요.';end if;
   if item.id='seat' then
    if qty<>1 then raise exception '자리 선정권은 한 번에 1개 구매해 주세요.';end if;
    perform pg_advisory_xact_lock(734521);
    if (select count(*) from public.point_entries where title='학급 자리 선정권' and detail='학급 상점 구매' and student_id not in(select id from public.classroom_students where student_no=0) and created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')>=3 then raise exception '이번 달 자리 선정권은 모두 소진됐어요.';end if;
   end if;
   select coalesce(sum(delta),0) into bal from public.point_entries where student_id=sid;
   if bal<item.price::bigint*qty then raise exception '포인트가 부족해요.';end if;
   insert into public.point_entries(student_id,delta,title,detail) values(sid,-item.price*qty,item.name,'학급 상점 구매') returning id into eid;
   insert into private.petclass_orders(student_id,sku,quantity,unit_price,point_entry_id) values(sid,item.id,qty,item.price,eid) returning id into oid;
   if exists(select 1 from private.petclass_products where sku=item.id) then
    lot:=jsonb_build_object('id',oid,'sku',item.id,'quantity',qty,'remaining',qty,'reference',oid,'note','포인트 구매','createdAt',now(),'revoked',false);
    update private.petclass_farms set data=jsonb_set(data,'{inventory}',(data->'inventory')||jsonb_build_array(lot)),version=version+1 where student_id=sid;
   end if;
   note:=item.name||' '||qty||'개 구매 완료';
  end if;
 else raise exception '지원하지 않는 작업입니다.';
 end if;
 insert into private.petclass_requests(id,fingerprint,message) values(req,fp,note);
 insert into private.petclass_logs(student_id,actor,message) values(sid,a->>'name',note);
 return jsonb_build_object('state',private.pc_state(p_token),'message',note);
end$$;

revoke all on function public.petclass_gateway(text,text,text,jsonb) from public;
grant execute on function public.petclass_gateway(text,text,text,jsonb) to anon;
revoke all on function private.pc_state(text) from public,anon,authenticated;
select access_code as "테스트 계정 번호", (select sum(delta) from public.point_entries where student_id=s.id) as "포인트" from public.classroom_students s where student_no=0;
