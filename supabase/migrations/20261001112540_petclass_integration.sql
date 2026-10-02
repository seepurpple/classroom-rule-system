create table if not exists private.petclass_config(id boolean primary key default true check(id), key_hash text not null);
create table if not exists private.petclass_sessions(token_hash text primary key, student_id uuid references public.classroom_students(id), code_hash text, teacher_token uuid, expires_at timestamptz not null);
create table if not exists private.petclass_attempts(id text primary key, attempts int not null, expires_at timestamptz not null);
create table if not exists private.petclass_farms(student_id uuid primary key references public.classroom_students(id),version int not null default 0,data jsonb not null default '{"pets":[],"inventory":[],"claimedStarter":false}');
create table if not exists private.petclass_requests(id text primary key,fingerprint text not null,message text not null,created_at timestamptz not null default now());
create table if not exists private.petclass_logs(id uuid primary key default gen_random_uuid(),student_id uuid references public.classroom_students(id),actor text not null,message text not null,created_at timestamptz not null default now());
create index if not exists petclass_logs_student_time on private.petclass_logs(student_id,created_at desc);
create table if not exists private.petclass_orders(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id),sku text not null,quantity int not null check(quantity>0),unit_price int not null check(unit_price>0),point_entry_id uuid not null references public.point_entries(id),refund_entry_id uuid references public.point_entries(id),refunded_quantity int not null default 0,created_at timestamptz not null default now());
create index if not exists petclass_orders_student on private.petclass_orders(student_id);
create index if not exists petclass_orders_entry on private.petclass_orders(point_entry_id);
create table if not exists private.petclass_products(sku text primary key references public.classroom_shop_items(id),kind text not null,xp int);
insert into public.classroom_shop_items(id,name,price,note,icon) values
('food-s','별빛 한입',30,'경험치 +30','✦'),('food-m','숲속 도시락',80,'경험치 +90','▣'),('food-l','무지개 만찬',200,'경험치 +240','★'),('pet-choice-ticket','새 친구 초대권',1000,'새 펫 한 마리 · 최대 3마리','✉') on conflict(id) do nothing;
insert into private.petclass_products values('food-s','food',30),('food-m','food',90),('food-l','food',240),('pet-choice-ticket','ticket',null) on conflict do nothing;

do $$declare t text;begin foreach t in array array['petclass_config','petclass_sessions','petclass_attempts','petclass_farms','petclass_requests','petclass_logs','petclass_orders','petclass_products'] loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);end loop;end$$;

create or replace function private.pc_actor(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess private.petclass_sessions;s public.classroom_students;
begin
 select * into sess from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and expires_at>now();
 if not found then return null;end if;
 if sess.teacher_token is not null then
  if not exists(select 1 from public.teacher_sessions where token=sess.teacher_token and expires_at>now()) then return null;end if;
  return jsonb_build_object('id','teacher','role','teacher','name','선생님','loginId','teacher','mustChangePassword',false,'teacherToken',sess.teacher_token);
 end if;
 select * into s from public.classroom_students where id=sess.student_id and student_no>0;
 if not found or encode(extensions.digest(s.access_code,'sha256'),'hex')<>sess.code_hash then return null;end if;
 return jsonb_build_object('id',s.id,'role','student','name',lpad(s.student_no::text,2,'0')||'번 학생','loginId',s.student_no::text,'studentNo',s.student_no,'mustChangePassword',false);
end$$;
create or replace function private.pc_student(s public.classroom_students) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'studentNo',s.student_no,'name',lpad(s.student_no::text,2,'0')||'번 학생','loginId',s.student_no::text,'role','student','mustChangePassword',false,'balance',coalesce((select sum(delta) from public.point_entries where student_id=s.id),0),'version',coalesce((select version from private.petclass_farms where student_id=s.id),0)) || coalesce((select data from private.petclass_farms where student_id=s.id),'{"pets":[],"inventory":[],"claimedStarter":false}'::jsonb);
$$;
create or replace function private.pc_state(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb:=private.pc_actor(p_token);v jsonb:='{}';sid uuid;
begin
 if a->>'role'='student' then sid:=(a->>'id')::uuid;select private.pc_student(s) into v from public.classroom_students s where id=sid;end if;
 return jsonb_build_object('needsSetup',false,'className','1학년 3반','user',a-'teacherToken','balance',coalesce(v->'balance','0'),'version',coalesce(v->'version','0'),'claimedStarter',coalesce(v->'claimedStarter','false'),'pets',coalesce(v->'pets','[]'),'inventory',coalesce(v->'inventory','[]'),
 'students',case when a->>'role'='teacher' then coalesce((select jsonb_agg(private.pc_student(s) order by student_no) from public.classroom_students s where student_no>0),'[]') else '[]' end,
 'products',coalesce((select jsonb_agg(jsonb_build_object('sku',i.id,'name',i.name,'price',i.price,'description',i.note,'kind',coalesce(p.kind,'classroom'),'xp',p.xp) order by i.price) from public.classroom_shop_items i left join private.petclass_products p on p.sku=i.id),'[]'),
 'ledger',case when a is not null then coalesce((select jsonb_agg(to_jsonb(e) order by e."createdAt" desc) from (select p.id,s.student_no as "studentNo",p.delta,p.title,p.detail,p.created_at as "createdAt" from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.student_no>0 and (a->>'role'='teacher' or s.id=sid) order by p.created_at desc limit 300)e),'[]') else '[]' end,
 'orders',case when a is not null then coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from(select o.*,s.student_no from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where a->>'role'='teacher' or o.student_id=sid order by o.created_at desc limit 150)o),'[]') else '[]' end,
 'logs',case when a is not null then coalesce((select jsonb_agg(to_jsonb(l) order by l."createdAt" desc) from(select id,student_id as "studentId",actor as "actorName",message,created_at as "createdAt" from private.petclass_logs where a->>'role'='teacher' or student_id=sid order by created_at desc limit 150)l),'[]') else '[]' end,'updatedAt',now());
end$$;

create or replace function private.pc_point_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op in('UPDATE','DELETE') and exists(select 1 from private.petclass_orders where point_entry_id=old.id or refund_entry_id=old.id) then raise exception '펫 구매 기록은 수정·삭제 대신 구매 내역에서 환불해 주세요.';end if;
 if tg_op='DELETE' then perform 1 from public.classroom_students where id=old.student_id for update;return old;end if;
 perform 1 from public.classroom_students where id=new.student_id for update;return new;
end$$;
create trigger petclass_point_guard before insert or update or delete on public.point_entries for each row execute function private.pc_point_guard();
create or replace function private.pc_legacy(a jsonb,n text,x jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid:=(a->>'teacherToken')::uuid;c text;r jsonb;
begin
 if n='classroom_snapshot' then return public.classroom_snapshot()-'publicLedger'||jsonb_build_object('publicLedger','[]'::jsonb);end if;
 if n='consultation_snapshot' then return public.consultation_snapshot();end if;
 if a is null then raise exception '먼저 PetClass에서 로그인해 주세요.';end if;
 if n in('identify_student','submit_role_applications','submit_consultation_booking') then
  if a->>'role'<>'student' then raise exception '학생 계정으로 로그인해 주세요.';end if;
  select access_code into c from public.classroom_students where id=(a->>'id')::uuid;
  case n when 'identify_student' then return public.identify_student(c);
  when 'submit_role_applications' then return public.submit_role_applications(c,array(select jsonb_array_elements_text(x->'p_role_ids')));
  when 'submit_consultation_booking' then return public.submit_consultation_booking(c,(x->>'p_date')::date,(x->>'p_break_no')::smallint);end case;
 end if;
 if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
 case n
 when 'teacher_snapshot' then return public.teacher_snapshot(t);
 when 'teacher_assign_role' then return public.teacher_assign_role(t,(x->>'p_student_no')::smallint,x->>'p_role_id');
 when 'teacher_fill_unassigned_roles' then return public.teacher_fill_unassigned_roles(t);
 when 'teacher_update_role_salary' then return public.teacher_update_role_salary(t,x->>'p_role_id',(x->>'p_salary')::int);
 when 'teacher_record_class_points' then return public.teacher_record_class_points(t,(x->>'p_delta')::int,x->>'p_title',coalesce(x->>'p_detail',''));
 when 'teacher_record_point' then return public.teacher_record_point(t,(x->>'p_student_no')::smallint,(x->>'p_delta')::int,x->>'p_title',coalesce(x->>'p_detail',''));
 when 'teacher_run_payroll' then
  if x->>'p_period' !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' then raise exception '지급 월을 확인해 주세요.';end if;
  return public.teacher_run_payroll(t,x->>'p_period',coalesce(x->'p_adjustments','[]'));
 when 'teacher_record_reading_bonus' then return public.teacher_record_reading_bonus(t,(x->>'p_student_no')::smallint,(x->>'p_books')::smallint,x->>'p_period');
 when 'teacher_update_point_entry' then return public.teacher_update_point_entry(t,(x->>'p_entry_id')::uuid,(x->>'p_delta')::int,x->>'p_title',coalesce(x->>'p_detail',''));
 when 'teacher_delete_point_entry' then return public.teacher_delete_point_entry(t,(x->>'p_entry_id')::uuid);
 when 'teacher_lottery' then return public.teacher_lottery(t,x->>'p_role_id');
 when 'teacher_reset' then
  if x->>'p_scope'='ledger' then raise exception '운영 포인트 대장 전체 초기화는 비활성화했습니다.';end if;
  return public.teacher_reset(t,x->>'p_scope');
 when 'teacher_reset_code' then
  r:=public.teacher_reset_code(t,(x->>'p_student_no')::smallint);
  return jsonb_build_object('student',(select jsonb_build_object('code',access_code) from public.classroom_students where student_no=(x->>'p_student_no')::smallint));
 when 'teacher_update_code' then
  if x->>'p_code' !~ '^[0-9]{4}$' then raise exception '4자리 숫자를 입력해 주세요.';end if;
  update public.classroom_students set access_code=x->>'p_code' where student_no=(x->>'p_student_no')::smallint;
  return jsonb_build_object('student',jsonb_build_object('code',x->>'p_code'));
 when 'teacher_update_consultation_settings' then return public.teacher_update_consultation_settings(t,(x->>'p_start')::date,(x->>'p_end')::date,x->>'p_location',x->'p_breaks');
 when 'teacher_change_password' then
  r:=public.teacher_change_password(t,x->>'p_new_password');
  update private.petclass_sessions set teacher_token=(r->>'token')::uuid where teacher_token=t;
  return jsonb_build_object('token','session','state',r->'state');
 else raise exception '지원하지 않는 작업입니다.';
 end case;
end$$;

create or replace function public.petclass_gateway(p_key text,p_action text,p_token text,p_body jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;sid uuid;student public.classroom_students;tok text;th uuid;lim int;f private.petclass_farms;req text;fp text;previous private.petclass_requests;item public.classroom_shop_items;qty int;bal bigint;oid uuid;eid uuid;note text;lot jsonb;ord private.petclass_orders;remaining int;target jsonb;
begin
 if not exists(select 1 from private.petclass_config where key_hash=encode(extensions.digest(coalesce(p_key,''),'sha256'),'hex')) then raise exception '서버 인증 실패';end if;
 if p_body is null or jsonb_typeof(p_body)<>'object' then raise exception '요청 형식을 확인해 주세요.';end if;
 if p_action='login' then
  if p_body->>'code' !~ '^[0-9]{4}$' or p_body->>'role' not in('student','teacher') then return jsonb_build_object('error','고유 번호를 확인해 주세요.','status',400);end if;
  insert into private.petclass_attempts values(p_body->>'limiter',1,now()+interval '15 minutes') on conflict(id) do update set attempts=case when petclass_attempts.expires_at<=now() then 1 else petclass_attempts.attempts+1 end,expires_at=case when petclass_attempts.expires_at<=now() then now()+interval '15 minutes' else petclass_attempts.expires_at end returning attempts into lim;
  if lim>15 then return jsonb_build_object('error','로그인 시도가 많아요. 15분 뒤 다시 시도해 주세요.','status',429);end if;
  if p_body->>'role'='student' then
   select * into student from public.classroom_students where access_code=p_body->>'code' and student_no>0;
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
 if a is null then return jsonb_build_object('error','다시 로그인해 주세요.','status',401);end if;
 if p_action='price' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  if (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
  update public.classroom_shop_items set price=(p_body->>'price')::int where id=p_body->>'sku' and id in(select sku from private.petclass_products);
  if not found then raise exception '펫 상품을 확인해 주세요.';end if;
  return jsonb_build_object('state',private.pc_state(p_token),'message','상품 가격을 저장했어요.');
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
  perform 1 from public.classroom_students where id=sid and student_no>0 for update;
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
   if (p_body->>'expectedPrice')::int is distinct from item.price then raise exception '상품 가격이 바뀌었어요. 새로고침 후 다시 확인해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')=0 then raise exception '첫 무료 펫을 먼저 선택해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')+coalesce((select sum((g->>'remaining')::int) from jsonb_array_elements(f.data->'inventory')g where g->>'sku'='pet-choice-ticket' and not (g->>'revoked')::boolean),0)+qty>3 then raise exception '보유 펫과 미사용 선택권을 합해 최대 3마리예요.';end if;
   if item.id='seat' then
    if qty<>1 then raise exception '자리 선정권은 한 번에 1개 구매해 주세요.';end if;
    perform pg_advisory_xact_lock(734521);
    if (select count(*) from public.point_entries where title='학급 자리 선정권' and detail='학급 상점 구매' and created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')>=3 then raise exception '이번 달 자리 선정권은 모두 소진됐어요.';end if;
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
revoke all on function private.pc_actor(text),private.pc_state(text),private.pc_student(public.classroom_students),private.pc_legacy(jsonb,text,jsonb),private.pc_point_guard() from public,anon,authenticated;
