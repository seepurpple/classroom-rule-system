-- P2–P5: teacher accounts (email/password in auth.users, checked here — no e-mail, no service key),
-- admin approval, class picker for students, class creation/editing, per-class point presets and
-- global payroll rules. The legacy 2456 teacher password is retired.

-- 1. Tables
create table private.admin_audit(
  id uuid primary key default gen_random_uuid(),
  admin_id uuid,
  action text not null,
  target text,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now());

create table private.class_point_presets(
  class_id uuid not null references private.classes(id) on delete cascade,
  id text not null default left(replace(gen_random_uuid()::text,'-',''),10),
  kind text not null check (kind in ('earn','spend')),
  title text not null check (char_length(btrim(title)) between 1 and 40),
  amount int not null default 0 check (amount between 0 and 100000),
  all_students boolean not null default false,
  sort_order int not null default 0,
  primary key(class_id,id));

-- Shared by every class; only the operator edits it (SQL). applies_to: all | shared (capacity>=2) | comma-separated rule_keys.
create table private.payroll_rules(
  id text primary key,
  label text not null,
  effect text not null check (effect in ('cut','pct','fixed','confiscate','reading_off')),
  value int not null default 0,
  applies_to text not null default 'all',
  sort_order int not null default 0);
insert into private.payroll_rules values
 ('performance30','수행 수준 미달 · 최대 30% 삭감','cut',30,'all',1),
 ('shared20','공동 역할 업무 미수행 · 월급 20% 지급','pct',20,'shared',2),
 ('leader90','친분 차별 · 누적 월급 90% 몰수','confiscate',90,'leader',3),
 ('leader80','관리 소홀·분위기 훼손 · 누적 월급 80% 몰수','confiscate',80,'leader',4),
 ('readingBonusOff','수행 미달 · 추천 도서 추가금 공제','reading_off',0,'reading',5),
 ('bank40','기록 누락 · 월급 200P 지급','fixed',200,'bank',6),
 ('bank0','명세서 분실 · 월급 0P','fixed',0,'bank',7),
 ('audit0','기록 누락 미발견 · 월급 0P','fixed',0,'audit',8),
 ('audit300','다음 달 조정 · 월급 300P','fixed',300,'audit',9),
 ('audit2zero','2개월 연속 누락 · 월급 0P','fixed',0,'audit',10),
 ('collude100','통장이·지킴이 담합 · 누적 월급 전액 몰수','confiscate',100,'bank,audit',11),
 ('device50','디벗 보관함 비밀번호 유출 · 누적 월급 50% 몰수','confiscate',50,'device',12);

alter table private.petclass_attempts add column last_at timestamptz not null default now();

-- 2. Helpers
create function private.pc_norm(t text) returns text language sql immutable set search_path='' as $$ select lower(regexp_replace(coalesce(t,''),'\s','','g')) $$;

create function private.pc_seed_presets(p_class uuid) returns void language sql security definer set search_path='' as $$
 insert into private.class_point_presets(class_id,id,kind,title,amount,all_students,sort_order) values
 (p_class,'praise','earn','교과 담당 개인 칭찬',200,false,1),(p_class,'class-praise','earn','학급 전체 칭찬',250,true,2),
 (p_class,'good','earn','학급 내 선행',60,false,3),(p_class,'substitute','earn','자발적 역할 대행',0,false,4),
 (p_class,'teacher','earn','담임 재량 추가 지급',0,false,5),(p_class,'ask-praise','spend','교과 담당 칭찬 요구',300,false,6),
 (p_class,'poor-role','spend','역할 수행 부족·직무유기',0,false,7),(p_class,'bad-report','spend','교과 담당 안 좋은 전달',300,false,8),
 (p_class,'misdeed','spend','학급 내 악행',120,false,9),(p_class,'late','spend','학급 지각',100,false,10),
 (p_class,'rights','spend','타인 권리 유린',1000,false,11),(p_class,'harm-class','spend','우리 반 학생 피해',1000,false,12),
 (p_class,'harm-other','spend','타반 학생 피해',1000,false,13),(p_class,'atmosphere','spend','학급·수업 분위기 훼손',1000,false,14)
$$;

-- New class: students 0..N (0 = hidden test student), pet shop, mini games, point presets.
create function private.pc_seed_class(p_class uuid,p_count int) returns void language plpgsql security definer set search_path='' as $$
begin
 insert into public.classroom_students(class_id,student_no,access_code)
 select p_class,r-1,c from (select lpad(x::text,4,'0') c,row_number() over(order by random()) r from generate_series(1000,9999) x) s where r<=p_count+1;
 insert into public.point_entries(student_id,delta,title,detail)
 select id,100000,'테스트 계정 지급','테스트 학생 전용' from public.classroom_students where class_id=p_class and student_no=0;
 insert into public.classroom_shop_items(class_id,id,name,price,note,icon,sort_order) values
  (p_class,'food-s','별빛 한입',30,'경험치 +30','✦',1),(p_class,'food-m','숲속 도시락',80,'경험치 +90','▣',2),
  (p_class,'food-l','무지개 만찬',200,'경험치 +240','★',3),(p_class,'pet-choice-ticket','새 친구 초대권',1000,'새 펫 한 마리 · 최대 3마리','✉',4);
 insert into private.petclass_products(class_id,sku,kind,xp) values
  (p_class,'food-s','food',30),(p_class,'food-m','food',90),(p_class,'food-l','food',240),(p_class,'pet-choice-ticket','ticket',null);
 insert into private.petclass_games(class_id,id,price,prizes) values
  (p_class,'claw',700,'[{"name":"간식 1개","weight":50},{"name":"간식 2개","weight":30},{"name":"간식 3개","weight":15},{"name":"Big 간식","weight":5}]'),
  (p_class,'gacha',1000,'[{"name":"간식 1개","weight":60},{"name":"간식 2개","weight":30},{"name":"Big 간식","weight":10}]'),
  (p_class,'timing',500,'[]');
 perform private.pc_seed_presets(p_class);
end$$;

-- Failed sign-ins: from the 5th failure on the same key the caller waits 1, 2, 4 … 30 s (no lockout);
-- one IP may fail 300 times per 15 minutes in total (a school shares one IP).
create function private.pc_throttle(p_key text,p_ip text) returns text language plpgsql security definer set search_path='' as $$
declare r private.petclass_attempts;w interval;
begin
 select * into r from private.petclass_attempts where id='ip:'||p_ip and expires_at>now();
 if found and r.attempts>=300 then return '시도가 너무 많아요. 잠시 후 다시 시도해 주세요.';end if;
 select * into r from private.petclass_attempts where id=p_key and expires_at>now();
 if found and r.attempts>=5 then
  w:=least(30,power(2,r.attempts-5))*interval '1 second';
  if now()<r.last_at+w then return ceil(extract(epoch from r.last_at+w-now()))::int||'초 뒤에 다시 시도해 주세요.';end if;
 end if;
 return null;
end$$;

create function private.pc_fail(p_key text,p_ip text) returns void language sql security definer set search_path='' as $$
 insert into private.petclass_attempts(id,attempts,expires_at,last_at) values(p_key,1,now()+interval '15 minutes',now()),('ip:'||p_ip,1,now()+interval '15 minutes',now())
 on conflict(id) do update set attempts=case when petclass_attempts.expires_at<=now() then 1 else petclass_attempts.attempts+1 end,
  expires_at=case when petclass_attempts.expires_at<=now() then now()+interval '15 minutes' else petclass_attempts.expires_at end,last_at=now()
$$;

create function private.pc_teacher_token(p_class uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare t uuid;
begin
 delete from public.teacher_sessions where expires_at<=now();
 insert into public.teacher_sessions(expires_at,class_id) values(now()+interval '8 hours',p_class) returning token into t;
 return t;
end$$;

create function private.pc_open_session(p_student uuid,p_code text,p_teacher_token uuid,p_teacher uuid,p_class uuid) returns text language plpgsql security definer set search_path='' as $$
declare tok text:=gen_random_uuid()::text||gen_random_uuid()::text;
begin
 delete from private.petclass_sessions where expires_at<=now();
 insert into private.petclass_sessions(token_hash,student_id,code_hash,teacher_token,teacher_id,class_id,expires_at)
 values(encode(extensions.digest(tok,'sha256'),'hex'),p_student,case when p_code is not null then encode(extensions.digest(p_code,'sha256'),'hex') end,p_teacher_token,p_teacher,p_class,now()+interval '2 hours');
 return tok;
end$$;

-- Removes a class's activity. p_all also removes the class itself (students, roles, shop, settings).
create function private.pc_clear_class(p_class uuid,p_all boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 delete from private.petclass_game_plays g using public.classroom_students s where s.id=g.student_id and s.class_id=p_class;
 delete from private.petclass_orders o using public.classroom_students s where s.id=o.student_id and s.class_id=p_class;
 delete from public.point_entries e using public.classroom_students s where s.id=e.student_id and s.class_id=p_class;
 delete from private.petclass_farms f using public.classroom_students s where s.id=f.student_id and s.class_id=p_class;
 delete from public.role_applications where class_id=p_class;
 delete from public.role_lottery_audit where class_id=p_class;
 delete from private.petclass_logs where class_id=p_class or student_id in(select id from public.classroom_students where class_id=p_class);
 delete from private.petclass_sessions where student_id in(select id from public.classroom_students where class_id=p_class);
 delete from private.petclass_requests where id like 'teacher:'||p_class||':%' or split_part(id,':',1) in(select id::text from public.classroom_students where class_id=p_class);
 if p_all then delete from private.classes where id=p_class;return;end if;
 update public.classroom_students set role_id=null where class_id=p_class;
 insert into public.point_entries(student_id,delta,title,detail)
 select id,100000,'테스트 계정 지급','테스트 학생 전용' from public.classroom_students where class_id=p_class and student_no=0;
end$$;

create function private.pc_export(p_class uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('exportedAt',now(),'class',to_jsonb(c)-'features',
  'roles',(select jsonb_agg(to_jsonb(r)) from public.classroom_roles r where r.class_id=c.id),
  'students',(select jsonb_agg(jsonb_build_object('no',s.student_no,'code',s.access_code,'active',s.active,'roleId',s.role_id) order by s.student_no) from public.classroom_students s where s.class_id=c.id),
  'ledger',(select jsonb_agg(jsonb_build_object('no',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'at',p.created_at) order by p.created_at) from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.class_id=c.id),
  'pets',(select jsonb_agg(jsonb_build_object('no',s.student_no,'data',f.data)) from private.petclass_farms f join public.classroom_students s on s.id=f.student_id where s.class_id=c.id),
  'orders',(select jsonb_agg(jsonb_build_object('no',s.student_no,'sku',o.sku,'quantity',o.quantity,'unitPrice',o.unit_price,'refunded',o.refunded_quantity,'at',o.created_at)) from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where s.class_id=c.id),
  'shop',(select jsonb_agg(to_jsonb(i)-'image') from public.classroom_shop_items i where i.class_id=c.id),
  'presets',(select jsonb_agg(to_jsonb(p)) from private.class_point_presets p where p.class_id=c.id))
 from private.classes c where c.id=p_class
$$;

-- 3. Actor: teacher/admin sessions are re-checked against the profile on every request.
create or replace function private.pc_actor(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess private.petclass_sessions;s public.classroom_students;v uuid;pr private.profiles;
begin
 select * into sess from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and expires_at>now();
 if not found then return null;end if;
 if sess.teacher_id is not null then
  select * into pr from private.profiles where id=sess.teacher_id and approval_status='approved';
  if not found then return null;end if;
  if pr.role='admin' then return jsonb_build_object('id','admin:'||pr.id,'role','admin','name',coalesce(nullif(pr.display_name,''),'관리자'),'loginId',pr.email,'mustChangePassword',false,'teacherId',pr.id);end if;
  if sess.teacher_token is null then
   select id into v from private.classes where teacher_id=pr.id and archived_at is null;
   if v is null then return jsonb_build_object('id','teacher:'||pr.id,'role','teacher','name',coalesce(nullif(pr.display_name,''),'선생님'),'loginId',pr.email,'mustChangePassword',false,'teacherId',pr.id,'needsClass',true,'requestedClassName',pr.requested_class_name);end if;
   sess.teacher_token:=private.pc_teacher_token(v);
   update private.petclass_sessions set teacher_token=sess.teacher_token,class_id=v where token_hash=sess.token_hash;
  end if;
  select class_id into v from public.teacher_sessions where token=sess.teacher_token and expires_at>now();
  if v is null then return null;end if;
  return jsonb_build_object('id','teacher:'||v,'role','teacher','name',coalesce(nullif(pr.display_name,''),'선생님'),'loginId',pr.email,'mustChangePassword',false,'teacherToken',sess.teacher_token,'classId',v,'teacherId',pr.id);
 end if;
 if sess.teacher_token is not null then return null;end if;
 select * into s from public.classroom_students where id=sess.student_id and student_no>=0 and active;
 if not found or encode(extensions.digest(s.access_code,'sha256'),'hex')<>sess.code_hash then return null;end if;
 return jsonb_build_object('id',s.id,'role','student','name',case when s.student_no=0 then '테스트 학생' else lpad(s.student_no::text,2,'0')||'번 학생' end,'loginId',s.student_no::text,'studentNo',s.student_no,'mustChangePassword',false,'classId',s.class_id);
end$$;

create or replace function public.classroom_snapshot(p_class uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'className',c.name,
  'studentCount',c.student_count,
  'deadline',c.application_deadline,
  'applicationsOpen',coalesce(now()<=c.application_deadline,false),
  'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'capacity',r.capacity,'salary',r.salary,'ruleKey',r.rule_key) order by r.display_order,r.id) from public.classroom_roles r where r.class_id=c.id),'[]'::jsonb),
  'students',coalesce((select jsonb_agg(jsonb_build_object('number',s.student_no,'roleId',s.role_id) order by s.student_no) from public.classroom_students s where s.class_id=c.id and s.student_no>0 and s.active),'[]'::jsonb),
  'applicationCounts',coalesce((select jsonb_object_agg(x.role_id,x.n) from (select a.role_id,count(*)::int n from public.role_applications a where a.class_id=c.id and a.status<>'withdrawn' group by a.role_id) x),'{}'::jsonb),
  'applicationStudentCount',(select count(distinct a.student_id)::int from public.role_applications a where a.class_id=c.id and a.status<>'withdrawn'),
  'presets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'title',p.title,'amount',p.amount,'all',p.all_students) order by p.sort_order,p.title) from private.class_point_presets p where p.class_id=c.id),'[]'::jsonb),
  'payrollRules',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'label',r.label,'effect',r.effect,'value',r.value,'appliesTo',r.applies_to) order by r.sort_order) from private.payroll_rules r),'[]'::jsonb),
  'shopItems','[]'::jsonb,
  'publicLedger','[]'::jsonb)
 from private.classes c where c.id=p_class
$$;

create or replace function private.pc_state(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb:=private.pc_actor(p_token);v jsonb:='{}';sid uuid;cls uuid:=(a->>'classId')::uuid;
begin
 if a->>'role'='student' then sid:=(a->>'id')::uuid;select private.pc_student(s) into v from public.classroom_students s where id=sid and class_id=cls;end if;
 return jsonb_build_object('needsSetup',false,'className',(select name from private.classes where id=cls),'user',a-'teacherToken','balance',coalesce(v->'balance','0'),'version',coalesce(v->'version','0'),'claimedStarter',coalesce(v->'claimedStarter','false'),'pets',coalesce(v->'pets','[]'),'inventory',coalesce(v->'inventory','[]'),
 'students',case when a->>'role'='teacher' then coalesce((select jsonb_agg(private.pc_student(s) order by student_no=0,student_no) from public.classroom_students s where s.class_id=cls and s.student_no>=0 and s.active),'[]') else '[]' end,
 'products',coalesce((select jsonb_agg(jsonb_build_object('sku',i.id,'name',i.name,'price',i.price,'description',i.note,'kind',coalesce(p.kind,'classroom'),'xp',p.xp,'archived',i.archived,'monthlyLimit',i.monthly_limit,'image',case when i.image is null then null else '/api/shop-image?c='||i.class_id||'&sku='||i.id||'&v='||left(md5(i.image),10) end) order by i.sort_order nulls last,i.price) from public.classroom_shop_items i left join private.petclass_products p on p.class_id=i.class_id and p.sku=i.id where i.class_id=cls),'[]'),
 'ledger',case when a is not null then coalesce((select jsonb_agg(to_jsonb(e) order by e."createdAt" desc) from (select p.id,s.student_no as "studentNo",p.delta,p.title,p.detail,p.created_at as "createdAt" from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.class_id=cls and (s.student_no>0 or s.id=sid) and (a->>'role'='teacher' or s.id=sid) order by p.created_at desc limit 300)e),'[]') else '[]' end,
 'orders',case when a is not null then coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from(select o.*,s.student_no from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where s.class_id=cls and (a->>'role'='teacher' or o.student_id=sid) order by o.created_at desc limit 150)o),'[]') else '[]' end,
 'logs',case when a is not null then coalesce((select jsonb_agg(to_jsonb(l) order by l."createdAt" desc) from(select id,student_id as "studentId",actor as "actorName",message,created_at as "createdAt" from private.petclass_logs where class_id=cls and (a->>'role'='teacher' or student_id=sid) order by created_at desc limit 150)l),'[]') else '[]' end,'games',(select jsonb_object_agg(id,jsonb_build_object('price',price,'prizes',prizes,'item',item,'total',total,'remaining',remaining,'seconds',seconds,'precision',precision,'active',active and coalesce(remaining,0)>0)) from private.petclass_games where class_id=cls),
 'gamePlays',case when a is not null then coalesce((select jsonb_agg(to_jsonb(g) order by g."createdAt" desc) from(select gp.id,s.student_no as "studentNo",gp.game,gp.price,gp.status,gp.result,gp.elapsed,gp.target,gp.created_at as "createdAt" from private.petclass_game_plays gp join public.classroom_students s on s.id=gp.student_id where s.class_id=cls and (a->>'role'='teacher' or gp.student_id=sid) order by gp.created_at desc limit 150)g),'[]') else '[]' end,'updatedAt',now());
end$$;

-- 4. Sign-up: the account goes straight into auth.users (confirmed, no mail) and waits for approval.
create function private.pc_signup(b jsonb,p_ip text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text:=lower(btrim(coalesce(b->>'email','')));v_pw text:=coalesce(b->>'password','');v_dn text:=btrim(coalesce(b->>'displayName',''));v_cn text:=btrim(coalesce(b->>'className',''));uid uuid:=gen_random_uuid();n int;
begin
 if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email)>254 then return jsonb_build_object('error','이메일 주소를 확인해 주세요.','status',400);end if;
 if length(v_pw) not between 8 and 72 then return jsonb_build_object('error','비밀번호는 8~72자로 정해 주세요.','status',400);end if;
 if char_length(v_dn) not between 1 and 30 then return jsonb_build_object('error','이름은 1~30자로 입력해 주세요.','status',400);end if;
 if char_length(v_cn) not between 1 and 20 then return jsonb_build_object('error','반 이름은 1~20자로 입력해 주세요.','status',400);end if;
 select attempts into n from private.petclass_attempts where id='signup:'||p_ip and expires_at>now();
 if coalesce(n,0)>=5 then return jsonb_build_object('error','가입 신청이 많아요. 15분 뒤 다시 시도해 주세요.','status',429);end if;
 insert into private.petclass_attempts(id,attempts,expires_at,last_at) values('signup:'||p_ip,1,now()+interval '15 minutes',now())
 on conflict(id) do update set attempts=case when petclass_attempts.expires_at<=now() then 1 else petclass_attempts.attempts+1 end,
  expires_at=case when petclass_attempts.expires_at<=now() then now()+interval '15 minutes' else petclass_attempts.expires_at end,last_at=now();
 if exists(select 1 from auth.users u where lower(u.email)=v_email) then return jsonb_build_object('error','이미 가입된 이메일이에요. 비밀번호를 잊었다면 관리자에게 문의해 주세요.','status',409);end if;
 if exists(select 1 from private.classes c where private.pc_norm(c.name)=private.pc_norm(v_cn))
  or exists(select 1 from private.profiles p where p.approval_status='pending' and private.pc_norm(p.requested_class_name)=private.pc_norm(v_cn))
 then return jsonb_build_object('error','이미 있는 반 이름이에요. 다른 이름을 정해 주세요.','status',409);end if;
 insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
 values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',v_email,extensions.crypt(v_pw,extensions.gen_salt('bf',10)),now(),'{"provider":"email","providers":["email"]}',jsonb_build_object('display_name',v_dn,'class_name',v_cn),now(),now(),'','','','');
 insert into auth.identities(provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
 values(uid::text,uid,jsonb_build_object('sub',uid::text,'email',v_email,'email_verified',true,'phone_verified',false),'email',now(),now(),now());
 return jsonb_build_object('message','가입 신청을 보냈어요. 관리자가 승인하면 로그인할 수 있어요.');
end$$;

-- 5. Teacher class setup and account actions (class always from the session).
create function private.pc_teacher_action(a jsonb,act text,p_token text,b jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid:=(a->>'teacherId')::uuid;v uuid:=(a->>'classId')::uuid;h text;note text;v_role public.classroom_roles;n int;i int:=0;rj jsonb;
begin
 if a is null then return jsonb_build_object('error','다시 로그인해 주세요.','status',401);end if;
 if act='changePassword' then
  if tid is null then raise exception '선생님 계정으로 로그인해 주세요.';end if;
  select encrypted_password into h from auth.users where id=tid;
  if h is null or extensions.crypt(coalesce(b->>'current',''),h) is distinct from h then raise exception '현재 비밀번호가 맞지 않아요.';end if;
  if length(coalesce(b->>'next','')) not between 8 and 72 then raise exception '새 비밀번호는 8~72자로 정해 주세요.';end if;
  update auth.users set encrypted_password=extensions.crypt(b->>'next',extensions.gen_salt('bf',10)),updated_at=now() where id=tid;
  return jsonb_build_object('state',private.pc_state(p_token),'message','비밀번호를 바꿨어요.');
 end if;
 if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
 if act='classCreate' then
  if v is not null or exists(select 1 from private.classes where teacher_id=tid) then raise exception '이미 학급이 있어요.';end if;
  if char_length(btrim(coalesce(b->>'name',''))) not between 1 and 20 then raise exception '반 이름은 1~20자로 입력해 주세요.';end if;
  if coalesce(b->>'studentCount','') !~ '^[0-9]{1,2}$' or (b->>'studentCount')::int not between 1 and 40 then raise exception '학생 수는 1~40명으로 입력해 주세요.';end if;
  if jsonb_typeof(b->'roles')<>'array' or jsonb_array_length(b->'roles')>30 then raise exception '역할 목록을 확인해 주세요.';end if;
  begin
   insert into private.classes(teacher_id,name,student_count,application_deadline) values(tid,btrim(b->>'name'),(b->>'studentCount')::int,nullif(b->>'deadline','')::timestamptz) returning id into v;
  exception when unique_violation then raise exception '이미 있는 반 이름이에요. 다른 이름을 정해 주세요.';end;
  perform private.pc_seed_class(v,(b->>'studentCount')::int);
  begin
   for rj in select value from jsonb_array_elements(b->'roles') loop
    i:=i+1;
    if char_length(btrim(coalesce(rj->>'name',''))) not between 1 and 20 or coalesce(rj->>'capacity','') !~ '^[0-9]{1,2}$' or (rj->>'capacity')::int not between 1 and 40
     or coalesce(rj->>'salary','') !~ '^[0-9]{1,5}$' or (rj->>'salary')::int>10000 or coalesce(rj->>'ruleKey','') not in('','leader','audit','bank','reading','device')
    then raise exception '%번째 역할의 이름·정원·월급을 확인해 주세요.',i;end if;
    insert into public.classroom_roles(class_id,id,name,capacity,salary,display_order,rule_key)
    values(v,coalesce(nullif(rj->>'ruleKey',''),'r'||substr(md5(random()::text),1,8)),btrim(rj->>'name'),(rj->>'capacity')::int,(rj->>'salary')::int,i,nullif(rj->>'ruleKey',''));
   end loop;
  exception when unique_violation then raise exception '역할 이름이 겹쳐요. 이름을 다르게 정해 주세요.';end;
  update private.petclass_sessions set teacher_token=private.pc_teacher_token(v),class_id=v where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  insert into private.petclass_logs(class_id,student_id,actor,message) values(v,null,a->>'name',btrim(b->>'name')||' 학급을 만들었어요.');
  return jsonb_build_object('state',private.pc_state(p_token),'message','학급을 만들었어요.');
 end if;
 if v is null then raise exception '먼저 학급을 만들어 주세요.';end if;
 if act='classUpdate' then
  if b ? 'name' then
   if char_length(btrim(coalesce(b->>'name',''))) not between 1 and 20 then raise exception '반 이름은 1~20자로 입력해 주세요.';end if;
   begin update private.classes set name=btrim(b->>'name') where id=v;
   exception when unique_violation then raise exception '이미 있는 반 이름이에요. 다른 이름을 정해 주세요.';end;
  end if;
  if b ? 'deadline' then update private.classes set application_deadline=nullif(b->>'deadline','')::timestamptz where id=v;end if;
  if b ? 'studentCount' then
   if coalesce(b->>'studentCount','') !~ '^[0-9]{1,2}$' or (b->>'studentCount')::int not between 1 and 40 then raise exception '학생 수는 1~40명으로 입력해 주세요.';end if;
   n:=(b->>'studentCount')::int;
   -- Fewer students: trailing numbers become inactive (records kept, role seat freed). More: reactivate, then add.
   update public.classroom_students set active=student_no<=n,role_id=case when student_no<=n then role_id end where class_id=v and student_no>0;
   insert into public.classroom_students(class_id,student_no,access_code)
   select v,m.sno,k.code from
    (select sno,row_number() over(order by sno) rn from generate_series(1,n) sno where not exists(select 1 from public.classroom_students s where s.class_id=v and s.student_no=sno)) m
    join (select lpad(x::text,4,'0') code,row_number() over(order by random()) rn from generate_series(1000,9999) x where not exists(select 1 from public.classroom_students s where s.class_id=v and s.access_code=lpad(x::text,4,'0'))) k using(rn);
   update private.classes set student_count=n where id=v;
  end if;
  note:='학급 설정을 저장했어요.';
 elsif act='roleSave' then
  if char_length(btrim(coalesce(b->>'name',''))) not between 1 and 20 or coalesce(b->>'capacity','') !~ '^[0-9]{1,2}$' or (b->>'capacity')::int not between 1 and 40
   or coalesce(b->>'salary','') !~ '^[0-9]{1,5}$' or (b->>'salary')::int>10000 then raise exception '역할 이름(1~20자)·정원(1~40)·월급(0~10,000P)을 확인해 주세요.';end if;
  begin
   if coalesce(b->>'id','')='' then
    if (select count(*) from public.classroom_roles where class_id=v)>=30 then raise exception '역할은 30개까지 만들 수 있어요.';end if;
    insert into public.classroom_roles(class_id,id,name,capacity,salary,display_order)
    values(v,'r'||substr(md5(random()::text),1,8),btrim(b->>'name'),(b->>'capacity')::int,(b->>'salary')::int,(select coalesce(max(display_order),0)+1 from public.classroom_roles where class_id=v));
   else
    select * into v_role from public.classroom_roles where class_id=v and id=b->>'id';
    if not found then raise exception '역할을 찾을 수 없어요.';end if;
    if v_role.rule_key is not null and btrim(b->>'name')<>v_role.name then raise exception '특별 규칙 역할은 이름을 바꿀 수 없어요.';end if;
    if (select count(*) from public.classroom_students where class_id=v and role_id=v_role.id)>(b->>'capacity')::int then raise exception '이미 배정된 학생 수보다 정원을 줄일 수 없어요.';end if;
    update public.classroom_roles set name=btrim(b->>'name'),capacity=(b->>'capacity')::int,salary=(b->>'salary')::int where class_id=v and id=v_role.id;
   end if;
  exception when unique_violation then raise exception '같은 이름의 역할이 이미 있어요.';end;
  note:=btrim(b->>'name')||' 역할을 저장했어요.';
 elsif act='roleDelete' then
  delete from public.classroom_roles where class_id=v and id=b->>'id' returning name into note;
  if not found then raise exception '역할을 찾을 수 없어요.';end if;
  note:=note||' 역할을 삭제했어요.';
 elsif act='roleOrder' then
  if jsonb_typeof(b->'ids')<>'array' then raise exception '순서를 확인해 주세요.';end if;
  update public.classroom_roles r set display_order=o.n from jsonb_array_elements_text(b->'ids') with ordinality o(id,n) where r.class_id=v and r.id=o.id;
  note:='역할 순서를 저장했어요.';
 elsif act='presetSave' then
  if coalesce(b->>'kind','') not in('earn','spend') or char_length(btrim(coalesce(b->>'title',''))) not between 1 and 40
   or coalesce(b->>'amount','') !~ '^[0-9]{1,6}$' or (b->>'amount')::int>100000 then raise exception '포인트 사유(1~40자)와 금액(0~100,000P)을 확인해 주세요.';end if;
  if coalesce(b->>'id','')='' then
   if (select count(*) from private.class_point_presets where class_id=v)>=50 then raise exception '포인트 사유는 50개까지 만들 수 있어요.';end if;
   insert into private.class_point_presets(class_id,kind,title,amount,all_students,sort_order)
   values(v,b->>'kind',btrim(b->>'title'),(b->>'amount')::int,coalesce((b->>'all')::boolean,false),(select coalesce(max(sort_order),0)+1 from private.class_point_presets where class_id=v));
  else
   update private.class_point_presets set kind=b->>'kind',title=btrim(b->>'title'),amount=(b->>'amount')::int,all_students=coalesce((b->>'all')::boolean,false) where class_id=v and id=b->>'id';
   if not found then raise exception '포인트 사유를 찾을 수 없어요.';end if;
  end if;
  note:='포인트 사유를 저장했어요.';
 elsif act='presetDelete' then
  delete from private.class_point_presets where class_id=v and id=b->>'id';
  if not found then raise exception '포인트 사유를 찾을 수 없어요.';end if;
  note:='포인트 사유를 삭제했어요.';
 elsif act='productLimit' then
  if coalesce(b->>'monthlyLimit','')<>'' and (b->>'monthlyLimit' !~ '^[0-9]{1,4}$' or (b->>'monthlyLimit')::int not between 1 and 1000) then raise exception '월 판매 한도는 1~1,000개로 입력하거나 비워 두세요.';end if;
  update public.classroom_shop_items set monthly_limit=nullif(b->>'monthlyLimit','')::int where class_id=v and id=b->>'sku';
  if not found then raise exception '상품을 확인해 주세요.';end if;
  note:='월 판매 한도를 저장했어요.';
 else raise exception '지원하지 않는 작업입니다.';
 end if;
 insert into private.petclass_logs(class_id,student_id,actor,message) values(v,null,a->>'name',note);
 return jsonb_build_object('state',private.pc_state(p_token),'message',note);
end$$;

-- 6. Admin: approve/reject, temporary password, reset class activity, delete account. No class data reads.
create function private.pc_admin_action(a jsonb,act text,b jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare me uuid:=(a->>'teacherId')::uuid;tp private.profiles;tc private.classes;note text;ok boolean;
begin
 if a is null or a->>'role'<>'admin' then raise exception '관리자만 할 수 있어요.';end if;
 if act='adminList' then
  return jsonb_build_object('accounts',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'email',p.email,'displayName',p.display_name,'status',p.approval_status,'requestedClassName',p.requested_class_name,'note',p.review_note,'createdAt',p.created_at,'className',c.name,'studentCount',c.student_count) order by p.approval_status<>'pending',p.created_at desc) from private.profiles p left join private.classes c on c.teacher_id=p.id where p.role='teacher'),'[]'));
 end if;
 if coalesce(b->>'id','') !~ '^[0-9a-f-]{36}$' then raise exception '계정을 선택해 주세요.';end if;
 select * into tp from private.profiles where id=(b->>'id')::uuid and role='teacher';
 if not found then raise exception '선생님 계정을 찾을 수 없어요.';end if;
 select * into tc from private.classes where teacher_id=tp.id;
 if act='adminReview' then
  if coalesce(b->>'approve','') not in('true','false') then raise exception '승인 여부를 확인해 주세요.';end if;
  ok:=(b->>'approve')::boolean;
  update private.profiles set approval_status=case when ok then 'approved' else 'rejected' end,review_note=case when ok then null else nullif(left(btrim(coalesce(b->>'note','')),200),'') end,reviewed_at=now() where id=tp.id;
  if not ok then delete from private.petclass_sessions where teacher_id=tp.id;end if;
  note:=case when ok then '승인' else '거절' end;
 elsif act='adminSetPassword' then
  if length(coalesce(b->>'password','')) not between 8 and 72 then raise exception '임시 비밀번호는 8~72자로 정해 주세요.';end if;
  update auth.users set encrypted_password=extensions.crypt(b->>'password',extensions.gen_salt('bf',10)),updated_at=now() where id=tp.id;
  delete from private.petclass_sessions where teacher_id=tp.id;
  note:='임시 비밀번호 지정';
 elsif act='adminExport' then
  if tc.id is null then raise exception '아직 학급이 없는 계정이에요.';end if;
  insert into private.admin_audit(admin_id,action,target,detail) values(me,act,tp.email,jsonb_build_object('className',tc.name));
  return jsonb_build_object('export',private.pc_export(tc.id));
 elsif act in('adminResetClass','adminDeleteAccount') then
  if btrim(coalesce(b->>'confirm','')) is distinct from coalesce(tc.name,tp.email) then raise exception '확인 문구가 맞지 않아요. "%"을(를) 정확히 입력해 주세요.',coalesce(tc.name,tp.email);end if;
  if tc.id is not null then perform private.pc_clear_class(tc.id,act='adminDeleteAccount');end if;
  if act='adminDeleteAccount' then delete from auth.users where id=tp.id;note:='계정 삭제';else note:='학급 데이터 초기화';end if;
 else raise exception '지원하지 않는 작업입니다.';
 end if;
 insert into private.admin_audit(admin_id,action,target,detail) values(me,act,tp.email,jsonb_build_object('className',tc.name));
 return jsonb_build_object('message',tp.email||' · '||note||' 완료','accounts',private.pc_admin_action(a,'adminList','{}')->'accounts');
end$$;

-- 7. Gateway: sign-in, sign-up and class list here; everything else goes to the existing core.
alter function public.petclass_gateway(text,text,text,jsonb) rename to pc_core;
alter function public.pc_core(text,text,text,jsonb) set schema private;

create function public.petclass_gateway(p_key text,p_action text,p_token text,p_body jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;cls uuid;ip text:=left(coalesce(p_body->>'ip',''),80);k text;msg text;st public.classroom_students;uid uuid;h text;pr private.profiles;th uuid;tok text;v_email text;v_pw text;
begin
 if not exists(select 1 from private.petclass_config where key_hash=encode(extensions.digest(coalesce(p_key,''),'sha256'),'hex')) then raise exception '서버 인증 실패';end if;
 if p_body is null or jsonb_typeof(p_body)<>'object' then raise exception '요청 형식을 확인해 주세요.';end if;
 if p_action='classList' then
  return jsonb_build_object('classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from private.classes c join private.profiles p on p.id=c.teacher_id where p.approval_status='approved' and c.archived_at is null),'[]'));
 end if;
 if p_action='login' then
  if coalesce(p_body->>'code','') !~ '^[0-9]{4}$' or coalesce(p_body->>'classId','') !~ '^[0-9a-f-]{36}$' then return jsonb_build_object('error','반을 고르고 고유 번호 4자리를 입력해 주세요.','status',400);end if;
  cls:=(p_body->>'classId')::uuid;k:='s:'||ip||':'||cls;
  msg:=private.pc_throttle(k,ip);if msg is not null then return jsonb_build_object('error',msg,'status',429);end if;
  select s.* into st from public.classroom_students s join private.classes c on c.id=s.class_id join private.profiles p on p.id=c.teacher_id
  where s.class_id=cls and s.access_code=p_body->>'code' and s.student_no>=0 and s.active and p.approval_status='approved' and c.archived_at is null;
  if not found then perform private.pc_fail(k,ip);return jsonb_build_object('error','고유 번호를 다시 확인해 주세요.','status',401);end if;
  delete from private.petclass_attempts where id=k;
  tok:=private.pc_open_session(st.id,st.access_code,null,null,cls);
  return jsonb_build_object('token',tok,'state',private.pc_state(tok));
 end if;
 if p_action='teacherLogin' then
  v_email:=lower(btrim(coalesce(p_body->>'email','')));v_pw:=coalesce(p_body->>'password','');k:='t:'||ip||':'||v_email;
  msg:=private.pc_throttle(k,ip);if msg is not null then return jsonb_build_object('error',msg,'status',429);end if;
  select u.id,u.encrypted_password into uid,h from auth.users u where lower(u.email)=v_email and u.deleted_at is null limit 1;
  if uid is null or h is null or v_pw='' or extensions.crypt(v_pw,h) is distinct from h then
   perform private.pc_fail(k,ip);return jsonb_build_object('error','이메일 또는 비밀번호를 확인해 주세요.','status',401);
  end if;
  delete from private.petclass_attempts where id=k;
  select * into pr from private.profiles where id=uid;
  if not found then return jsonb_build_object('error','계정 정보를 찾을 수 없어요. 관리자에게 문의해 주세요.','status',403);end if;
  if pr.approval_status='pending' then return jsonb_build_object('error','관리자 승인을 기다리고 있어요. 승인되면 바로 로그인할 수 있어요.','status',403);end if;
  if pr.approval_status='rejected' then return jsonb_build_object('error','가입이 승인되지 않았어요.'||coalesce(' 사유: '||pr.review_note,''),'status',403);end if;
  if pr.role='teacher' then
   select id into cls from private.classes where teacher_id=pr.id and archived_at is null;
   if cls is not null then th:=private.pc_teacher_token(cls);end if;
  end if;
  update auth.users set last_sign_in_at=now() where id=uid;
  tok:=private.pc_open_session(null,null,th,pr.id,cls);
  return jsonb_build_object('token',tok,'state',private.pc_state(tok));
 end if;
 if p_action='signup' then return private.pc_signup(p_body,ip);end if;
 a:=private.pc_actor(p_token);
 if p_action in('changePassword','classCreate','classUpdate','roleSave','roleDelete','roleOrder','presetSave','presetDelete','productLimit') then return private.pc_teacher_action(a,p_action,p_token,p_body);end if;
 if p_action in('adminList','adminReview','adminSetPassword','adminExport','adminResetClass','adminDeleteAccount') then return private.pc_admin_action(a,p_action,p_body);end if;
 -- ponytail: pc_core still holds the retired password/code login branch; 'login' never reaches it (handled above).
 return private.pc_core(p_key,p_action,p_token,p_body);
end$$;

-- 8. Existing data: presets for the legacy class, old 2456 sessions out, password login retired.
select private.pc_seed_presets(id) from private.classes;
update private.class_point_presets set title='3반 학생 피해' where id='harm-class' and class_id=(select id from private.classes where name='1학년 3반');
delete from private.petclass_sessions where teacher_token is not null and teacher_id is null;
delete from public.teacher_sessions;
drop function public.teacher_login(text);
drop function public.teacher_change_password(uuid,text);
drop function private.pc_legacy_class();
drop table public.classroom_settings;

-- 9. Least privilege: only the gateway is callable from outside; private tables stay closed.
alter table private.admin_audit enable row level security;
alter table private.class_point_presets enable row level security;
alter table private.payroll_rules enable row level security;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.petclass_gateway(text,text,text,jsonb) to anon;
