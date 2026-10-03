-- P1: teacher profiles, classes, and class scoping for every table and function.
-- The existing class keeps working unchanged: teachers still sign in with the legacy
-- password and students with their 4-digit code; both land in the legacy class.

-- 1. Teacher/admin profiles (Supabase Auth users)
create table private.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null default '',
  role text not null default 'teacher' check (role in ('admin','teacher')),
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','rejected')),
  requested_class_name text,
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz);

create function private.pc_new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if coalesce(new.is_anonymous,false) then return new;end if;
 insert into private.profiles(id,email,display_name,requested_class_name)
 values(new.id,coalesce(new.email,''),left(btrim(coalesce(new.raw_user_meta_data->>'display_name','')),30),nullif(left(btrim(coalesce(new.raw_user_meta_data->>'class_name','')),20),''))
 on conflict(id) do nothing;
 return new;
end$$;
create trigger pc_on_auth_user_created after insert on auth.users for each row execute function private.pc_new_profile();

-- Accounts the operator already created in the dashboard (2026-10-03).
insert into private.profiles(id,email,display_name,role,approval_status,reviewed_at)
select id,email,
  case when email='seepurpple@gmail.com' then '관리자' else '1학년 3반 담임' end,
  case when email='seepurpple@gmail.com' then 'admin' else 'teacher' end,
  'approved',now()
from auth.users where email in('seepurpple@gmail.com','202606@jeonnong.ms.kr')
on conflict(id) do nothing;

-- 2. Classes (one per teacher for now)
create table private.classes(
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references private.profiles(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 20),
  student_count smallint not null check (student_count between 1 and 40),
  application_deadline timestamptz,
  features jsonb not null default '{}',
  created_at timestamptz not null default now(),
  archived_at timestamptz);
create unique index classes_name_key on private.classes(lower(regexp_replace(name,'\s','','g')));
create unique index classes_teacher_key on private.classes(teacher_id);

insert into private.classes(teacher_id,name,student_count,application_deadline)
select p.id,'1학년 3반',25,(select application_deadline from public.classroom_settings where id=1)
from private.profiles p where p.email='202606@jeonnong.ms.kr';
do $$begin if (select count(*) from private.classes)<>1 then raise exception 'legacy class was not created';end if;end$$;

-- ponytail: single legacy class for password/code-only sign-in; removed in P2/P3.
create function private.pc_legacy_class() returns uuid language sql stable security definer set search_path='' as $$
 select id from private.classes order by created_at,id limit 1
$$;

-- 3. Students
alter table public.classroom_students add column class_id uuid references private.classes(id) on delete cascade, add column active boolean not null default true;
update public.classroom_students set class_id=private.pc_legacy_class();
alter table public.classroom_students alter column class_id set not null;
alter table public.classroom_students drop constraint classroom_students_student_no_key, drop constraint classroom_students_access_code_key, drop constraint classroom_students_student_no_check;
alter table public.classroom_students
  add constraint classroom_students_class_no_key unique(class_id,student_no),
  add constraint classroom_students_class_code_key unique(class_id,access_code),
  add constraint classroom_students_class_id_key unique(class_id,id),
  add constraint classroom_students_student_no_check check (student_no between 0 and 40);

-- 4. Roles: composite key (class_id, id) so nothing can point at another class's role
alter table public.classroom_roles add column class_id uuid references private.classes(id) on delete cascade, add column rule_key text check (rule_key in ('leader','audit','bank','reading','device'));
update public.classroom_roles set class_id=private.pc_legacy_class(), rule_key=case when id in('leader','audit','bank','reading','device') then id end;
alter table public.classroom_roles alter column class_id set not null;
alter table public.classroom_students drop constraint classroom_students_role_id_fkey;
alter table public.role_applications drop constraint role_applications_role_id_fkey;
alter table public.role_lottery_audit drop constraint role_lottery_audit_role_id_fkey;
alter table public.classroom_roles drop constraint classroom_roles_pkey, drop constraint classroom_roles_name_key;
alter table public.classroom_roles add primary key(class_id,id), add constraint classroom_roles_class_name_key unique(class_id,name);
alter table public.classroom_students add constraint classroom_students_role_fkey foreign key(class_id,role_id) references public.classroom_roles(class_id,id) on delete set null(role_id);

alter table public.role_applications add column class_id uuid;
update public.role_applications a set class_id=s.class_id from public.classroom_students s where s.id=a.student_id;
alter table public.role_applications alter column class_id set not null,
  add constraint role_applications_student_fkey foreign key(class_id,student_id) references public.classroom_students(class_id,id) on delete cascade,
  add constraint role_applications_role_fkey foreign key(class_id,role_id) references public.classroom_roles(class_id,id) on delete cascade;
drop index if exists public.role_applications_role_status_idx;
create index role_applications_role_status_idx on public.role_applications(class_id,role_id,status,preference);

alter table public.role_lottery_audit add column class_id uuid;
update public.role_lottery_audit set class_id=private.pc_legacy_class();
alter table public.role_lottery_audit alter column class_id set not null,
  add constraint role_lottery_audit_role_fkey foreign key(class_id,role_id) references public.classroom_roles(class_id,id) on delete cascade;

-- 5. Shop items, pet products, mini games
alter table public.classroom_shop_items add column class_id uuid references private.classes(id) on delete cascade, add column monthly_limit int check (monthly_limit>0);
update public.classroom_shop_items set class_id=private.pc_legacy_class(), monthly_limit=case when id='seat' then 3 end;
alter table public.classroom_shop_items alter column class_id set not null;
alter table private.petclass_products drop constraint petclass_products_sku_fkey, drop constraint petclass_products_pkey;
alter table public.classroom_shop_items drop constraint classroom_shop_items_pkey, add primary key(class_id,id);
alter table private.petclass_products add column class_id uuid;
update private.petclass_products set class_id=private.pc_legacy_class();
alter table private.petclass_products alter column class_id set not null, add primary key(class_id,sku),
  add constraint petclass_products_item_fkey foreign key(class_id,sku) references public.classroom_shop_items(class_id,id) on delete cascade;

alter table private.petclass_games add column class_id uuid references private.classes(id) on delete cascade;
update private.petclass_games set class_id=private.pc_legacy_class();
alter table private.petclass_games alter column class_id set not null, drop constraint petclass_games_pkey, add primary key(class_id,id);

-- 6. Logs and sessions
alter table private.petclass_logs add column class_id uuid references private.classes(id) on delete cascade;
update private.petclass_logs set class_id=private.pc_legacy_class();
alter table private.petclass_logs alter column class_id set not null;
create index petclass_logs_class_time on private.petclass_logs(class_id,created_at desc);

alter table public.teacher_sessions add column class_id uuid references private.classes(id) on delete cascade;
update public.teacher_sessions set class_id=private.pc_legacy_class();
alter table public.teacher_sessions alter column class_id set not null;

alter table private.petclass_sessions add column class_id uuid references private.classes(id) on delete cascade, add column teacher_id uuid references private.profiles(id) on delete cascade;
update private.petclass_sessions set class_id=private.pc_legacy_class();

alter table private.profiles enable row level security;
alter table private.classes enable row level security;
revoke all on private.profiles, private.classes from public, anon, authenticated;

-- 7. Retired functions
drop function if exists private.auto_assign_roles();
drop function if exists public.student_purchase(text,text);
drop function if exists public.teacher_run_payroll(uuid,text);
drop function if exists public.classroom_snapshot();
drop function if exists public.identify_student(text);
drop function if exists public.submit_role_applications(text,text[]);
drop function if exists private.require_teacher(uuid);

-- 8. Class-scoped legacy functions
create function private.require_teacher(p_token uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 select class_id into v from public.teacher_sessions where token=p_token and expires_at>now();
 if v is null then raise exception '교사 인증이 필요합니다.';end if;
 return v;
end$$;

create function public.classroom_snapshot(p_class uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'className',c.name,
  'deadline',c.application_deadline,
  'applicationsOpen',coalesce(now()<=c.application_deadline,false),
  'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'capacity',r.capacity,'salary',r.salary,'ruleKey',r.rule_key) order by r.display_order,r.id) from public.classroom_roles r where r.class_id=c.id),'[]'::jsonb),
  'students',coalesce((select jsonb_agg(jsonb_build_object('number',s.student_no,'roleId',s.role_id) order by s.student_no) from public.classroom_students s where s.class_id=c.id and s.student_no>0 and s.active),'[]'::jsonb),
  'applicationCounts',coalesce((select jsonb_object_agg(x.role_id,x.n) from (select a.role_id,count(*)::int n from public.role_applications a where a.class_id=c.id and a.status<>'withdrawn' group by a.role_id) x),'{}'::jsonb),
  'applicationStudentCount',(select count(distinct a.student_id)::int from public.role_applications a where a.class_id=c.id and a.status<>'withdrawn'),
  'shopItems','[]'::jsonb,
  'publicLedger','[]'::jsonb)
 from private.classes c where c.id=p_class
$$;

create function public.identify_student(p_class uuid,p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.classroom_students;
begin
 select * into s from public.classroom_students where class_id=p_class and access_code=p_code and active;
 if not found then raise exception '고유난수 4자리를 다시 확인하세요.';end if;
 if s.student_no=0 then raise exception '테스트 계정은 역할을 신청할 수 없어요.';end if;
 return jsonb_build_object('studentNo',s.student_no,'assigned',s.role_id is not null,'roleIds',coalesce((select jsonb_agg(role_id order by preference) from public.role_applications where student_id=s.id and status='pending'),'[]'::jsonb));
end$$;

create function public.submit_role_applications(p_class uuid,p_code text,p_role_ids text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student public.classroom_students;
begin
 if now()>(select application_deadline from private.classes where id=p_class) then raise exception '역할 지원 기간이 마감되었습니다.';end if;
 if cardinality(p_role_ids)<>1 then raise exception '희망 역할은 1개만 선택하세요.';end if;
 if not exists(select 1 from public.classroom_roles where class_id=p_class and id=p_role_ids[1]) then raise exception '지원 역할을 확인하세요.';end if;
 select * into v_student from public.classroom_students where class_id=p_class and access_code=p_code and active;
 if not found or v_student.student_no=0 then raise exception '고유난수 4자리를 다시 확인하세요.';end if;
 if v_student.role_id is not null then raise exception '이미 역할이 배정되었습니다.';end if;
 delete from public.role_applications where student_id=v_student.id;
 insert into public.role_applications(class_id,student_id,role_id,preference) values(p_class,v_student.id,p_role_ids[1],1);
 return jsonb_build_object('studentNo',v_student.student_no,'snapshot',public.classroom_snapshot(p_class));
end$$;

create or replace function public.teacher_snapshot(p_token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 return jsonb_build_object(
  'base',public.classroom_snapshot(v),
  'students',coalesce((select jsonb_agg(jsonb_build_object('number',s.student_no,'roleId',s.role_id,'code',s.access_code,'balance',(select coalesce(sum(delta),0) from public.point_entries p where p.student_id=s.id)) order by s.student_no) from public.classroom_students s where s.class_id=v and s.student_no>0 and s.active),'[]'::jsonb),
  'applications',coalesce((select jsonb_agg(jsonb_build_object('studentNo',s.student_no,'roleId',a.role_id,'preference',a.preference,'status',a.status) order by s.student_no,a.preference) from public.role_applications a join public.classroom_students s on s.id=a.student_id where a.class_id=v and s.student_no>0),'[]'::jsonb),
  'ledger',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'studentNo',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'createdAt',p.created_at) order by p.created_at desc) from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.class_id=v and s.student_no>0),'[]'::jsonb));
end$$;

create or replace function public.teacher_login(p_password text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_token uuid;
begin
 if not exists(select 1 from public.classroom_settings where id=1 and extensions.crypt(p_password,teacher_password_hash)=teacher_password_hash) then raise exception '비밀번호가 맞지 않습니다.';end if;
 delete from public.teacher_sessions where expires_at<=now();
 insert into public.teacher_sessions(expires_at,class_id) values(now()+interval '8 hours',private.pc_legacy_class()) returning token into v_token;
 return jsonb_build_object('token',v_token,'state',public.teacher_snapshot(v_token));
end$$;

create or replace function public.teacher_change_password(p_token uuid,p_new_password text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_new uuid:=gen_random_uuid();
begin
 if p_new_password !~ '^[0-9]{4}$' then raise exception '비밀번호는 숫자 4자리로 설정하세요.';end if;
 update public.classroom_settings set teacher_password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf')) where id=1;
 delete from public.teacher_sessions where class_id=v;
 insert into public.teacher_sessions(token,expires_at,class_id) values(v_new,now()+interval '8 hours',v);
 return jsonb_build_object('token',v_new,'state',public.teacher_snapshot(v_new));
end$$;

create or replace function public.teacher_assign_role(p_token uuid,p_student_no smallint,p_role_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_role public.classroom_roles;v_sid uuid;v_n int;
begin
 select id into v_sid from public.classroom_students where class_id=v and student_no=p_student_no and student_no>0 and active;
 if not found then raise exception '학생 번호를 확인하세요.';end if;
 if coalesce(p_role_id,'')='' then
  update public.classroom_students set role_id=null where id=v_sid;
  return public.teacher_snapshot(p_token);
 end if;
 select * into v_role from public.classroom_roles where class_id=v and id=p_role_id;
 if not found then raise exception '존재하지 않는 역할입니다.';end if;
 select count(*) into v_n from public.classroom_students where class_id=v and role_id=p_role_id and id<>v_sid;
 if v_n>=v_role.capacity then raise exception '% 역할 정원이 가득 찼습니다.',v_role.name;end if;
 update public.classroom_students set role_id=p_role_id where id=v_sid;
 update public.role_applications set status='withdrawn' where student_id=v_sid and status='pending';
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_delete_point_entry(p_token uuid,p_entry_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 delete from public.point_entries e using public.classroom_students s where e.id=p_entry_id and s.id=e.student_id and s.class_id=v;
 if not found then raise exception '포인트 기록을 찾을 수 없습니다.';end if;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_update_point_entry(p_token uuid,p_entry_id uuid,p_delta integer,p_title text,p_detail text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 if p_delta=0 or btrim(coalesce(p_title,''))='' then raise exception '포인트와 내역을 확인하세요.';end if;
 update public.point_entries e set delta=p_delta,title=left(btrim(p_title),40),detail=left(coalesce(p_detail,''),80) from public.classroom_students s where e.id=p_entry_id and s.id=e.student_id and s.class_id=v;
 if not found then raise exception '포인트 기록을 찾을 수 없습니다.';end if;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_fill_unassigned_roles(p_token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_student_nos jsonb;
begin
 if now()<=(select application_deadline from private.classes where id=v) then raise exception '지원 마감 후 배정할 수 있습니다.';end if;
 with openings as (
  select r.id as role_id,r.capacity-count(s.id)::int as slots
  from public.classroom_roles r left join public.classroom_students s on s.class_id=r.class_id and s.role_id=r.id
  where r.class_id=v group by r.id,r.capacity
 ), eligible as (
  select a.student_id,a.role_id from public.role_applications a join openings o on o.role_id=a.role_id
  where a.class_id=v and a.status='pending' and o.slots>0
   and (select count(*) from public.role_applications x where x.class_id=v and x.role_id=a.role_id and x.status in('pending','assigned'))<=o.slots
 ) update public.classroom_students s set role_id=e.role_id from eligible e where s.id=e.student_id and s.class_id=v and s.role_id is null;
 update public.role_applications a set status='assigned' from public.classroom_students s
 where a.class_id=v and a.student_id=s.id and a.status='pending' and a.role_id=s.role_id;
 -- One distinct open seat per unassigned student (test student and inactive students excluded).
 with seats as (
  select x.role_id,row_number() over(order by random()) as n from (
   select r.id as role_id,generate_series(1,greatest(r.capacity-count(s.id)::int,0)) from public.classroom_roles r
   left join public.classroom_students s on s.class_id=r.class_id and s.role_id=r.id where r.class_id=v group by r.id,r.capacity) x
 ), candidates as (
  select id,row_number() over(order by random()) as n from public.classroom_students where class_id=v and role_id is null and student_no>0 and active
 ), assigned as (
  update public.classroom_students s set role_id=seats.role_id from seats join candidates c using(n) where s.id=c.id returning s.student_no
 ) select coalesce(jsonb_agg(student_no order by student_no),'[]'::jsonb) into v_student_nos from assigned;
 return jsonb_build_object('studentNos',v_student_nos,'state',public.teacher_snapshot(p_token));
end$$;

create or replace function public.teacher_lottery(p_token uuid,p_role_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_capacity int;v_candidate_ids uuid[];v_winner_ids uuid[];v_student_nos jsonb;v_candidate_nos smallint[];v_winner_nos smallint[];
begin
 if now()<=(select application_deadline from private.classes where id=v) then raise exception '지원 마감 후 추첨할 수 있습니다.';end if;
 select capacity into v_capacity from public.classroom_roles where class_id=v and id=p_role_id;
 if not found then raise exception '존재하지 않는 역할입니다.';end if;
 if exists(select 1 from public.role_applications where class_id=v and role_id=p_role_id and status='unassigned') then raise exception '이미 추첨을 완료했습니다.';end if;
 select coalesce(array_agg(student_id),'{}') into v_candidate_ids from public.role_applications where class_id=v and role_id=p_role_id and status in('pending','assigned');
 if cardinality(v_candidate_ids)<=v_capacity then raise exception '정원 초과 지원 역할이 아닙니다.';end if;
 select coalesce(array_agg(student_no order by student_no),'{}') into v_candidate_nos from public.classroom_students where class_id=v and id=any(v_candidate_ids);
 select coalesce(array_agg(student_id),'{}') into v_winner_ids from (select student_id from public.role_applications where class_id=v and role_id=p_role_id and student_id=any(v_candidate_ids) order by random() limit v_capacity) w;
 update public.classroom_students set role_id=null where class_id=v and id=any(v_candidate_ids) and role_id=p_role_id;
 update public.classroom_students set role_id=p_role_id where class_id=v and id=any(v_winner_ids);
 update public.role_applications set status=case when student_id=any(v_winner_ids) then 'assigned' else 'unassigned' end where class_id=v and role_id=p_role_id and student_id=any(v_candidate_ids);
 select coalesce(array_agg(student_no order by student_no),'{}') into v_winner_nos from public.classroom_students where class_id=v and id=any(v_winner_ids);
 insert into public.role_lottery_audit(class_id,role_id,candidate_student_nos,winner_student_nos) values(v,p_role_id,v_candidate_nos,v_winner_nos);
 select coalesce(jsonb_agg(student_no order by student_no),'[]'::jsonb) into v_student_nos from public.classroom_students where class_id=v and id=any(v_winner_ids);
 return jsonb_build_object('studentNos',v_student_nos,'state',public.teacher_snapshot(p_token));
end$$;

create or replace function public.teacher_record_class_points(p_token uuid,p_delta integer,p_title text,p_detail text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 if p_delta=0 then raise exception '포인트를 확인하세요.';end if;
 insert into public.point_entries(student_id,delta,title,detail)
 select id,p_delta,left(p_title,40),left(coalesce(p_detail,''),80) from public.classroom_students where class_id=v and student_no>0 and active;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_record_point(p_token uuid,p_student_no smallint,p_delta integer,p_title text,p_detail text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_student_id uuid;
begin
 select id into v_student_id from public.classroom_students where class_id=v and student_no=p_student_no and student_no>0;
 if not found or p_delta=0 then raise exception '학생 번호와 포인트를 확인하세요.';end if;
 insert into public.point_entries(student_id,delta,title,detail) values(v_student_id,p_delta,left(p_title,40),left(coalesce(p_detail,''),80));
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_record_reading_bonus(p_token uuid,p_student_no smallint,p_books smallint,p_period text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_student public.classroom_students;v_bonus integer;
begin
 select s.* into v_student from public.classroom_students s join public.classroom_roles r on r.class_id=s.class_id and r.id=s.role_id
 where s.class_id=v and s.student_no=p_student_no and r.rule_key='reading';
 if not found then raise exception '다독이 역할 학생만 추천 도서를 기록할 수 있어요.';end if;
 if p_books<1 then raise exception '추천 도서는 1권 이상 입력하세요.';end if;
 if exists(select 1 from public.point_entries where student_id=v_student.id and title='역할 월급' and detail like p_period||' 역할 월급%' and (detail like '%수행 수준 미달%' or detail like '%추천 도서 추가금 공제%')) then raise exception '해당 월 수행 미달 처리되어 추천 도서 추가금은 지급할 수 없어요.';end if;
 v_bonus:=least(700,case when p_books<=2 then p_books*100 else 200+(p_books-2)*50 end);
 if exists(select 1 from public.point_entries where student_id=v_student.id and title='다독이 추천 도서 추가' and detail=p_period||' · '||p_books||'권') then raise exception '같은 월·권수 기록이 이미 있습니다.';end if;
 insert into public.point_entries(student_id,delta,title,detail) values(v_student.id,v_bonus,'다독이 추천 도서 추가',p_period||' · '||p_books||'권');
 return jsonb_build_object('bonus',v_bonus,'state',public.teacher_snapshot(p_token));
end$$;

create or replace function public.teacher_reset(p_token uuid,p_scope text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 if p_scope='roles' then
  update public.classroom_students set role_id=null where class_id=v and role_id is not null;
  delete from public.role_applications where class_id=v;
 elsif p_scope='ledger' then
  delete from public.point_entries e using public.classroom_students s where s.id=e.student_id and s.class_id=v;
 else raise exception '초기화 범위를 확인하세요.';
 end if;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_reset_code(p_token uuid,p_student_no smallint) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_code text;
begin
 if not exists(select 1 from public.classroom_students where class_id=v and student_no=p_student_no) then raise exception '학생 번호를 확인하세요.';end if;
 loop
  v_code:=lpad((floor(random()*9000)+1000)::int::text,4,'0');
  exit when not exists(select 1 from public.classroom_students where class_id=v and access_code=v_code);
 end loop;
 update public.classroom_students set access_code=v_code where class_id=v and student_no=p_student_no;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_update_code(p_token uuid,p_student_no smallint,p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 if p_code !~ '^\d{4}$' then raise exception '4자리 숫자를 입력하세요.';end if;
 update public.classroom_students set access_code=p_code where class_id=v and student_no=p_student_no;
 if not found then raise exception '학생 번호를 확인하세요.';end if;
 return public.teacher_snapshot(p_token);
exception when unique_violation then raise exception '이미 사용 중인 고유난수입니다.';
end$$;

create or replace function public.teacher_update_role_salary(p_token uuid,p_role_id text,p_salary integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);
begin
 if p_salary<0 or p_salary>10000 then raise exception '월급은 0~10,000P 사이로 입력하세요.';end if;
 update public.classroom_roles set salary=p_salary where class_id=v and id=p_role_id;
 if not found then raise exception '존재하지 않는 역할입니다.';end if;
 return public.teacher_snapshot(p_token);
end$$;

create or replace function public.teacher_run_payroll(p_token uuid,p_period text,p_adjustments jsonb default '[]'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid:=private.require_teacher(p_token);v_row record;v_adjust jsonb;v_payout integer;v_reason text;v_rate integer;v_cumulative integer;
begin
 if p_adjustments is null or jsonb_typeof(p_adjustments)<>'array' then raise exception '월급 조정 값을 확인하세요.';end if;
 for v_row in select s.id,s.student_no,r.id as role_id,r.name as role_name,r.salary from public.classroom_students s join public.classroom_roles r on r.class_id=s.class_id and r.id=s.role_id where s.class_id=v and s.student_no>0 and s.active loop
  select value into v_adjust from jsonb_array_elements(p_adjustments) value where (value->>'studentNo')::smallint=v_row.student_no limit 1;
  v_adjust:=coalesce(v_adjust,'{}'::jsonb);
  v_payout:=coalesce((v_adjust->>'payout')::integer,v_row.salary);
  if v_payout<0 or v_payout>v_row.salary then raise exception '학생 % 월급 조정값이 올바르지 않습니다.',v_row.student_no;end if;
  v_reason:=left(coalesce(v_adjust->>'reason','정상 지급'),80);
  insert into public.point_entries(student_id,delta,title,detail)
  select v_row.id,v_payout,'역할 월급',p_period||' 역할 월급 · '||v_row.role_name||' · '||v_reason
  where v_payout>0 and not exists(select 1 from public.point_entries p where p.student_id=v_row.id and p.title='역할 월급' and p.detail like p_period||' 역할 월급 · '||v_row.role_name||'%');
  if coalesce((v_adjust->>'cancelReadingBonus')::boolean,false) then
   delete from public.point_entries where student_id=v_row.id and title='다독이 추천 도서 추가' and detail like p_period||' · %';
  end if;
  v_rate:=coalesce((v_adjust->>'confiscateRate')::integer,0);
  if v_rate between 1 and 100 and not exists(select 1 from public.point_entries p where p.student_id=v_row.id and p.title='누적 월급 몰수' and p.detail=p_period||' · '||v_rate||'%') then
   select coalesce(sum(delta),0) into v_cumulative from public.point_entries where student_id=v_row.id and title='역할 월급';
   if floor(v_cumulative*v_rate/100.0)>0 then insert into public.point_entries(student_id,delta,title,detail) values(v_row.id,-floor(v_cumulative*v_rate/100.0)::integer,'누적 월급 몰수',p_period||' · '||v_rate||'%');end if;
  end if;
 end loop;
 return public.teacher_snapshot(p_token);
end$$;

-- 9. Actor and legacy router carry the class
create or replace function private.pc_actor(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess private.petclass_sessions;s public.classroom_students;v uuid;
begin
 select * into sess from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and expires_at>now();
 if not found then return null;end if;
 if sess.teacher_token is not null then
  select class_id into v from public.teacher_sessions where token=sess.teacher_token and expires_at>now();
  if v is null then return null;end if;
  return jsonb_build_object('id','teacher:'||v,'role','teacher','name','선생님','loginId','teacher','mustChangePassword',false,'teacherToken',sess.teacher_token,'classId',v);
 end if;
 select * into s from public.classroom_students where id=sess.student_id and student_no>=0 and active;
 if not found or encode(extensions.digest(s.access_code,'sha256'),'hex')<>sess.code_hash then return null;end if;
 return jsonb_build_object('id',s.id,'role','student','name',case when s.student_no=0 then '테스트 학생' else lpad(s.student_no::text,2,'0')||'번 학생' end,'loginId',s.student_no::text,'studentNo',s.student_no,'mustChangePassword',false,'classId',s.class_id);
end$$;

create or replace function private.pc_legacy(a jsonb,n text,x jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid:=(a->>'teacherToken')::uuid;v uuid:=(a->>'classId')::uuid;c text;
begin
 if a is null then raise exception '먼저 PetClass에서 로그인해 주세요.';end if;
 if n='classroom_snapshot' then return public.classroom_snapshot(v);end if;
 if n in('identify_student','submit_role_applications') then
  if a->>'role'<>'student' then raise exception '학생 계정으로 로그인해 주세요.';end if;
  select access_code into c from public.classroom_students where id=(a->>'id')::uuid and class_id=v;
  case n when 'identify_student' then return public.identify_student(v,c);
  when 'submit_role_applications' then return public.submit_role_applications(v,c,array(select jsonb_array_elements_text(x->'p_role_ids')));end case;
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
  perform public.teacher_reset_code(t,(x->>'p_student_no')::smallint);
  return jsonb_build_object('student',(select jsonb_build_object('code',access_code) from public.classroom_students where class_id=v and student_no=(x->>'p_student_no')::smallint));
 when 'teacher_update_code' then
  perform public.teacher_update_code(t,(x->>'p_student_no')::smallint,x->>'p_code');
  return jsonb_build_object('student',jsonb_build_object('code',x->>'p_code'));
 when 'teacher_change_password' then
  declare r jsonb:=public.teacher_change_password(t,x->>'p_new_password');
  begin
   update private.petclass_sessions set teacher_token=(r->>'token')::uuid where teacher_token=t;
   return jsonb_build_object('token','session','state',r->'state');
  end;
 else raise exception '지원하지 않는 작업입니다.';
 end case;
end$$;

-- pc_state: every list filtered by the actor's class
create or replace function private.pc_state(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb:=private.pc_actor(p_token);v jsonb:='{}';sid uuid;cls uuid:=(a->>'classId')::uuid;
begin
 if a->>'role'='student' then sid:=(a->>'id')::uuid;select private.pc_student(s) into v from public.classroom_students s where id=sid and class_id=cls;end if;
 return jsonb_build_object('needsSetup',false,'className',(select name from private.classes where id=cls),'user',a-'teacherToken','balance',coalesce(v->'balance','0'),'version',coalesce(v->'version','0'),'claimedStarter',coalesce(v->'claimedStarter','false'),'pets',coalesce(v->'pets','[]'),'inventory',coalesce(v->'inventory','[]'),
 'students',case when a->>'role'='teacher' then coalesce((select jsonb_agg(private.pc_student(s) order by student_no=0,student_no) from public.classroom_students s where s.class_id=cls and s.student_no>=0 and s.active),'[]') else '[]' end,
 'products',coalesce((select jsonb_agg(jsonb_build_object('sku',i.id,'name',i.name,'price',i.price,'description',i.note,'kind',coalesce(p.kind,'classroom'),'xp',p.xp,'archived',i.archived,'image',case when i.image is null then null else '/api/shop-image?c='||i.class_id||'&sku='||i.id||'&v='||left(md5(i.image),10) end) order by i.sort_order nulls last,i.price) from public.classroom_shop_items i left join private.petclass_products p on p.class_id=i.class_id and p.sku=i.id where i.class_id=cls),'[]'),
 'ledger',case when a is not null then coalesce((select jsonb_agg(to_jsonb(e) order by e."createdAt" desc) from (select p.id,s.student_no as "studentNo",p.delta,p.title,p.detail,p.created_at as "createdAt" from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.class_id=cls and (s.student_no>0 or s.id=sid) and (a->>'role'='teacher' or s.id=sid) order by p.created_at desc limit 300)e),'[]') else '[]' end,
 'orders',case when a is not null then coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from(select o.*,s.student_no from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where s.class_id=cls and (a->>'role'='teacher' or o.student_id=sid) order by o.created_at desc limit 150)o),'[]') else '[]' end,
 'logs',case when a is not null then coalesce((select jsonb_agg(to_jsonb(l) order by l."createdAt" desc) from(select id,student_id as "studentId",actor as "actorName",message,created_at as "createdAt" from private.petclass_logs where class_id=cls and (a->>'role'='teacher' or student_id=sid) order by created_at desc limit 150)l),'[]') else '[]' end,'games',(select jsonb_object_agg(id,jsonb_build_object('price',price,'prizes',prizes,'item',item,'total',total,'remaining',remaining,'seconds',seconds,'precision',precision,'active',active and coalesce(remaining,0)>0)) from private.petclass_games where class_id=cls),
 'gamePlays',case when a is not null then coalesce((select jsonb_agg(to_jsonb(g) order by g."createdAt" desc) from(select gp.id,s.student_no as "studentNo",gp.game,gp.price,gp.status,gp.result,gp.elapsed,gp.target,gp.created_at as "createdAt" from private.petclass_game_plays gp join public.classroom_students s on s.id=gp.student_id where s.class_id=cls and (a->>'role'='teacher' or gp.student_id=sid) order by gp.created_at desc limit 150)g),'[]') else '[]' end,'updatedAt',now());
end$$;

-- gateway: class from the session only, never from the request body
create or replace function public.petclass_gateway(p_key text,p_action text,p_token text,p_body jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cls uuid;gm private.petclass_games;gp private.petclass_game_plays;secs numeric;won boolean;a jsonb;sid uuid;student public.classroom_students;tok text;th uuid;lim int;f private.petclass_farms;req text;fp text;previous private.petclass_requests;item public.classroom_shop_items;qty int;bal bigint;oid uuid;eid uuid;note text;lot jsonb;ord private.petclass_orders;remaining int;target jsonb;
begin
 if not exists(select 1 from private.petclass_config where key_hash=encode(extensions.digest(coalesce(p_key,''),'sha256'),'hex')) then raise exception '서버 인증 실패';end if;
 if p_body is null or jsonb_typeof(p_body)<>'object' then raise exception '요청 형식을 확인해 주세요.';end if;
 if p_action='login' then
  if p_body->>'code' !~ '^[0-9]{4}$' or p_body->>'role' not in('student','teacher') then return jsonb_build_object('error','고유 번호를 확인해 주세요.','status',400);end if;
  insert into private.petclass_attempts values(p_body->>'limiter',1,now()+interval '15 minutes') on conflict(id) do update set attempts=case when petclass_attempts.expires_at<=now() then 1 else petclass_attempts.attempts+1 end,expires_at=case when petclass_attempts.expires_at<=now() then now()+interval '15 minutes' else petclass_attempts.expires_at end returning attempts into lim;
  if lim>15 then return jsonb_build_object('error','로그인 시도가 많아요. 15분 뒤 다시 시도해 주세요.','status',429);end if;
  if p_body->>'role'='student' then
   -- ponytail: no classId yet means the legacy class (student class picker arrives in P3).
   cls:=case when coalesce(p_body->>'classId','') ~ '^[0-9a-f-]{36}$' then (p_body->>'classId')::uuid else private.pc_legacy_class() end;
   select * into student from public.classroom_students where class_id=cls and access_code=p_body->>'code' and student_no>=0 and active;
   if not found then return jsonb_build_object('error','고유 번호를 다시 확인해 주세요.','status',401);end if;
   sid:=student.id;
  else
   begin target:=public.teacher_login(p_body->>'code');th:=(target->>'token')::uuid;select class_id into cls from public.teacher_sessions where token=th;
   exception when others then return jsonb_build_object('error','교사 비밀번호를 다시 확인해 주세요.','status',401);end;
  end if;
  tok:=gen_random_uuid()::text||gen_random_uuid()::text;
  delete from private.petclass_sessions where expires_at<=now();
  insert into private.petclass_sessions(token_hash,student_id,code_hash,teacher_token,expires_at,class_id) values(encode(extensions.digest(tok,'sha256'),'hex'),sid,case when sid is not null then encode(extensions.digest(student.access_code,'sha256'),'hex') end,th,now()+interval '2 hours',cls);
  delete from private.petclass_attempts where id=p_body->>'limiter';
  return jsonb_build_object('token',tok,'state',private.pc_state(tok));
 end if;
 a:=private.pc_actor(p_token);cls:=(a->>'classId')::uuid;
 if p_action='state' then return private.pc_state(p_token);end if;
 if p_action='logout' then
  delete from public.teacher_sessions where token=(a->>'teacherToken')::uuid;
  delete from private.petclass_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');return '{}'::jsonb;
 end if;
 if p_action='legacy' then return private.pc_legacy(a,p_body->>'name',coalesce(p_body->'args','{}'));end if;
 if p_action='productImage' then return jsonb_build_object('image',(select image from public.classroom_shop_items where class_id=case when coalesce(p_body->>'classId','') ~ '^[0-9a-f-]{36}$' then (p_body->>'classId')::uuid end and id=p_body->>'sku'));end if;
 if a is null then return jsonb_build_object('error','다시 로그인해 주세요.','status',401);end if;
 if p_action='price' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  if (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
  update public.classroom_shop_items set price=(p_body->>'price')::int where class_id=cls and id=p_body->>'sku' and not archived;
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
   insert into public.classroom_shop_items(class_id,id,name,price,note,icon,image,sort_order) values(cls,note,btrim(p_body->>'name'),(p_body->>'price')::int,coalesce(btrim(p_body->>'description'),''),'✦',p_body->>'image',(select coalesce(max(sort_order),0)+1 from public.classroom_shop_items where class_id=cls));
   if p_body->>'category'='pet' then insert into private.petclass_products(class_id,sku,kind,xp) values(cls,note,'food',(p_body->>'xp')::int);end if;
   note:=btrim(p_body->>'name')||' 상품을 추가했어요.';
  elsif p_action='removeProduct' then
   update public.classroom_shop_items set archived=true where class_id=cls and id=p_body->>'sku' and not archived returning name into note;
   if not found then raise exception '상품을 찾을 수 없어요.';end if;
   note:=note||' 상품을 삭제했어요.';
  else
   if jsonb_typeof(p_body->'skus')<>'array' then raise exception '순서를 확인해 주세요.';end if;
   update public.classroom_shop_items i set sort_order=o.n from jsonb_array_elements_text(p_body->'skus') with ordinality o(sku,n) where i.class_id=cls and i.id=o.sku;
   note:='상품 순서를 저장했어요.';
  end if;
  insert into private.petclass_logs(class_id,student_id,actor,message) values(cls,null,a->>'name',note);
  return jsonb_build_object('state',private.pc_state(p_token),'message',note);
 end if;
 if p_action in('gameConfig','gameTiming','gamePlay','gameResult','timingStart','timingStop') then
  if p_action in('gameConfig','gameTiming') then
   if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
   if p_action='gameConfig' then
    if coalesce(p_body->>'game','') not in('claw','gacha') then raise exception '게임을 확인해 주세요.';end if;
    if p_body ? 'price' then
     if coalesce(p_body->>'price','') !~ '^[0-9]{1,6}$' or (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
     update private.petclass_games set price=(p_body->>'price')::int where class_id=cls and id=p_body->>'game';note:='가격을 저장했어요.';
    end if;
    if p_body ? 'prizes' then
     if jsonb_typeof(p_body->'prizes')<>'array' or jsonb_array_length(p_body->'prizes') not between 1 and 20 then raise exception '등장할 아이템을 1~20개로 정해 주세요.';end if;
     if exists(select 1 from jsonb_array_elements(p_body->'prizes') e where length(btrim(coalesce(e->>'name',''))) not between 1 and 30 or coalesce(e->>'weight','') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (e->>'weight')::numeric<=0) then raise exception '아이템 이름과 확률을 확인해 주세요.';end if;
     if (select sum((e->>'weight')::numeric) from jsonb_array_elements(p_body->'prizes') e)<>100 then raise exception '확률 합계가 100%%가 되어야 해요.';end if;
     update private.petclass_games set prizes=(select jsonb_agg(jsonb_build_object('name',btrim(e->>'name'),'weight',(e->>'weight')::numeric) order by n) from jsonb_array_elements(p_body->'prizes') with ordinality x(e,n)) where class_id=cls and id=p_body->>'game';note:='확률을 저장했어요.';
    end if;
    if note is null then raise exception '변경할 내용을 확인해 주세요.';end if;
   elsif coalesce(p_body->>'active','true')='false' then
    update private.petclass_games set active=false where class_id=cls and id='timing';note:='시간 맞추기를 내렸어요.';
   else
    if length(btrim(coalesce(p_body->>'item',''))) not between 1 and 30 then raise exception '상품 이름은 1~30자로 입력해 주세요.';end if;
    if coalesce(p_body->>'total','') !~ '^[0-9]{1,3}$' or (p_body->>'total')::int not between 1 and 100 then raise exception '갯수는 1~100개로 입력해 주세요.';end if;
    if coalesce(p_body->>'price','') !~ '^[0-9]{1,6}$' or (p_body->>'price')::int not between 1 and 100000 then raise exception '가격은 1~100,000P 사이로 입력해 주세요.';end if;
    if coalesce(p_body->>'precision','') not in('0.1','0.01') then raise exception '판정 단위를 확인해 주세요.';end if;
    if coalesce(p_body->>'seconds','') !~ '^[0-9]{1,2}([.][0-9]{1,2})?$' or (p_body->>'seconds')::numeric not between 1 and 60 then raise exception '시간은 1~60초로 입력해 주세요.';end if;
    if (p_body->>'precision')='0.1' and (p_body->>'seconds')::numeric<>round((p_body->>'seconds')::numeric,1) then raise exception '0.1초 단위면 시간도 소수 첫째 자리까지 입력해 주세요.';end if;
    update private.petclass_games set item=btrim(p_body->>'item'),total=(p_body->>'total')::int,remaining=(p_body->>'total')::int,price=(p_body->>'price')::int,seconds=(p_body->>'seconds')::numeric,precision=(p_body->>'precision')::numeric,active=true where class_id=cls and id='timing';
    note:='시간 맞추기를 등록했어요.';
   end if;
   insert into private.petclass_logs(class_id,student_id,actor,message) values(cls,null,a->>'name',note);
   return jsonb_build_object('state',private.pc_state(p_token),'message',note);
  end if;
  if a->>'role'<>'student' then raise exception '학생 계정으로 참여해 주세요.';end if;
  sid:=(a->>'id')::uuid;
  perform 1 from public.classroom_students where id=sid and class_id=cls and student_no>=0 for update;
  if not found then raise exception '학생을 찾을 수 없어요.';end if;
  if p_action='gamePlay' then
   if coalesce(p_body->>'requestId','') !~ '^[a-zA-Z0-9-]{12,80}$' then raise exception '요청 번호를 확인해 주세요.';end if;
   select * into gp from private.petclass_game_plays where request_id=(a->>'id')||':'||(p_body->>'requestId');
   if not found and p_body->>'game' in('claw','timing') then
    select * into gp from private.petclass_game_plays where student_id=sid and game=p_body->>'game' and status='pending' and created_at>now()-interval '10 minutes' order by created_at desc limit 1;
   end if;
   if found then return jsonb_build_object('state',private.pc_state(p_token),'play',to_jsonb(gp),'message','이어서 진행해요.');end if;
   select * into gm from private.petclass_games where class_id=cls and id=p_body->>'game' for update;
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
     select * into gm from private.petclass_games where class_id=cls and id='claw';
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
     select * into gm from private.petclass_games where class_id=cls and id='timing';
    elsif won then
     update private.petclass_games g set remaining=g.remaining-1,active=g.remaining-1>0 where g.class_id=cls and g.id='timing' and g.active and g.remaining>0 returning g.* into gm;
     if not found then won:=false;end if;
    end if;
    update private.petclass_game_plays set status=case when won then 'won' else 'lost' end,result=case when won then gm.item else '실패' end,elapsed=round(secs,3) where id=gp.id returning * into gp;
    note:='시간 맞추기 '||to_char(gp.elapsed,'FM990.00')||'초 · '||gp.result;
   end if;
  end if;
  insert into private.petclass_logs(class_id,student_id,actor,message) values(cls,sid,a->>'name',note);
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
  for sid in select id from public.classroom_students where class_id=cls and student_no>0 and active and id in(select value::uuid from jsonb_array_elements_text(p_body->'studentIds')) order by id for update loop
   insert into public.point_entries(student_id,delta,title,detail) values(sid,(p_body->>'delta')::int,left(p_body->>'title',40),'교사 포인트 지급·차감');
  end loop;
  note:='선택 학생 포인트를 기록했어요.';
 elsif p_action='refund' then
  if a->>'role'<>'teacher' then raise exception '교사 인증이 필요합니다.';end if;
  select o.* into ord from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where o.id=(p_body->>'orderId')::uuid and s.class_id=cls;
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
  perform 1 from public.classroom_students where id=sid and class_id=cls and student_no>=0 for update;
  if not found then raise exception '학생을 찾을 수 없어요.';end if;
  insert into private.petclass_farms(student_id) values(sid) on conflict do nothing;
  select * into f from private.petclass_farms where student_id=sid;
  if p_action='commit' then
   if f.version<>(p_body->>'version')::int then return jsonb_build_object('error','상태가 변경됐어요. 다시 시도해 주세요.','status',409);end if;
   if jsonb_typeof(p_body->'data'->'pets')<>'array' or jsonb_array_length(p_body->'data'->'pets')>3 or jsonb_typeof(p_body->'data'->'inventory')<>'array' then raise exception '펫 저장 내용을 확인해 주세요.';end if;
   update private.petclass_farms set data=p_body->'data',version=version+1 where student_id=sid;note:=p_body->>'message';
  else
   qty:=(p_body->>'quantity')::int;if qty is null or qty not between 1 and 99 then raise exception '수량은 1~99개로 입력해 주세요.';end if;
   select * into item from public.classroom_shop_items where class_id=cls and id=p_body->>'sku' for share;
   if not found then raise exception '상품을 찾을 수 없어요.';end if;
   if item.archived then raise exception '판매가 끝난 상품이에요.';end if;
   if (p_body->>'expectedPrice')::int is distinct from item.price then raise exception '상품 가격이 바뀌었어요. 새로고침 후 다시 확인해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')=0 then raise exception '첫 무료 펫을 먼저 선택해 주세요.';end if;
   if item.id='pet-choice-ticket' and jsonb_array_length(f.data->'pets')+coalesce((select sum((g->>'remaining')::int) from jsonb_array_elements(f.data->'inventory')g where g->>'sku'='pet-choice-ticket' and not (g->>'revoked')::boolean),0)+qty>3 then raise exception '보유 펫과 미사용 선택권을 합해 최대 3마리예요.';end if;
   if item.monthly_limit is not null then
    perform pg_advisory_xact_lock(hashtextextended('monthly:'||cls||':'||item.id,0));
    if (select coalesce(sum(o.quantity-o.refunded_quantity),0) from private.petclass_orders o join public.classroom_students s on s.id=o.student_id
        where s.class_id=cls and s.student_no>0 and o.sku=item.id and o.created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')+qty>item.monthly_limit
    then raise exception '이번 달 %은(는) 모두 소진됐어요.',item.name;end if;
   end if;
   select coalesce(sum(delta),0) into bal from public.point_entries where student_id=sid;
   if bal<item.price::bigint*qty then raise exception '포인트가 부족해요.';end if;
   insert into public.point_entries(student_id,delta,title,detail) values(sid,-item.price*qty,item.name,'학급 상점 구매') returning id into eid;
   insert into private.petclass_orders(student_id,sku,quantity,unit_price,point_entry_id) values(sid,item.id,qty,item.price,eid) returning id into oid;
   if exists(select 1 from private.petclass_products where class_id=cls and sku=item.id) then
    lot:=jsonb_build_object('id',oid,'sku',item.id,'quantity',qty,'remaining',qty,'reference',oid,'note','포인트 구매','createdAt',now(),'revoked',false);
    update private.petclass_farms set data=jsonb_set(data,'{inventory}',(data->'inventory')||jsonb_build_array(lot)),version=version+1 where student_id=sid;
   end if;
   note:=item.name||' '||qty||'개 구매 완료';
  end if;
 else raise exception '지원하지 않는 작업입니다.';
 end if;
 insert into private.petclass_requests(id,fingerprint,message) values(req,fp,note);
 insert into private.petclass_logs(class_id,student_id,actor,message) values(cls,sid,a->>'name',note);
 return jsonb_build_object('state',private.pc_state(p_token),'message',note);
end$$;

-- 10. Least privilege: only the gateway is callable from outside, as before.
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.petclass_gateway(text,text,text,jsonb) to anon;
