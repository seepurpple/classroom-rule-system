-- Production schema as of 2026-10-03 before P1 (tables, constraints, untouched helpers),
-- reconstructed from the live catalog for PGlite tests. Supabase-only pieces are stubbed.
create role anon; create role authenticated;
create schema extensions; create schema private; create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(),email text,is_anonymous boolean not null default false,raw_user_meta_data jsonb not null default '{}',created_at timestamptz not null default now());
create function extensions.digest(t text,alg text) returns bytea language sql immutable as $$ select sha256(convert_to(t,'utf8')) $$;
create function extensions.gen_salt(t text) returns text language sql as $$ select 'stub$' $$;
create function extensions.crypt(p text,s text) returns text language sql immutable as $$ select 'stub$'||md5(p) $$;

create table public.classroom_settings(id smallint primary key default 1 check(id=1),application_deadline timestamptz not null default '2026-08-20 14:59:59+00',teacher_password_hash text,created_at timestamptz not null default now());
create table public.classroom_roles(id text primary key,name text not null unique,capacity smallint not null check(capacity>0),salary integer not null check(salary>=0),display_order smallint not null default 99);
create table public.classroom_students(id uuid primary key default gen_random_uuid(),student_no smallint not null unique check(student_no>=0 and student_no<=25),access_code text not null unique check(access_code ~ '^\d{4}$'),role_id text references public.classroom_roles(id) on delete set null,created_at timestamptz not null default now());
create table public.role_applications(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id) on delete cascade,role_id text not null references public.classroom_roles(id) on delete cascade,preference smallint not null check(preference=any(array[1,2])),status text not null default 'pending' check(status=any(array['pending','assigned','unassigned','withdrawn'])),created_at timestamptz not null default now(),unique(student_id,preference),unique(student_id,role_id));
create index role_applications_role_status_idx on public.role_applications(role_id,status,preference);
create table public.point_entries(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id) on delete cascade,delta integer not null check(delta<>0),title text not null check(char_length(title)>=1 and char_length(title)<=40),detail text not null default '',created_at timestamptz not null default now());
create table public.teacher_sessions(token uuid primary key default gen_random_uuid(),expires_at timestamptz not null,created_at timestamptz not null default now());
create table public.classroom_shop_items(id text primary key,name text not null,price integer not null check(price>0),note text not null default '',icon text not null default '',archived boolean not null default false,sort_order integer,image text);
create table public.role_lottery_audit(id uuid primary key default gen_random_uuid(),role_id text not null references public.classroom_roles(id) on delete cascade,candidate_student_nos smallint[] not null,winner_student_nos smallint[] not null,reason text not null default 'final_draw',created_at timestamptz not null default now());
create table private.petclass_config(id boolean primary key default true check(id),key_hash text not null);
create table private.petclass_sessions(token_hash text primary key,student_id uuid references public.classroom_students(id),code_hash text,teacher_token uuid,expires_at timestamptz not null);
create table private.petclass_attempts(id text primary key,attempts int not null,expires_at timestamptz not null);
create table private.petclass_farms(student_id uuid primary key references public.classroom_students(id),version int not null default 0,data jsonb not null default '{"pets":[],"inventory":[],"claimedStarter":false}');
create table private.petclass_requests(id text primary key,fingerprint text not null,message text not null,created_at timestamptz not null default now());
create table private.petclass_logs(id uuid primary key default gen_random_uuid(),student_id uuid references public.classroom_students(id),actor text not null,message text not null,created_at timestamptz not null default now());
create table private.petclass_orders(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id),sku text not null,quantity int not null check(quantity>0),unit_price int not null check(unit_price>0),point_entry_id uuid not null references public.point_entries(id),refund_entry_id uuid references public.point_entries(id),refunded_quantity int not null default 0,created_at timestamptz not null default now());
create table private.petclass_products(sku text primary key references public.classroom_shop_items(id),kind text not null,xp int);
create table private.petclass_games(id text primary key check(id=any(array['claw','gacha','timing'])),price int not null check(price between 1 and 100000),prizes jsonb not null default '[]',item text,total int,remaining int,seconds numeric,precision numeric,active boolean not null default false);
create table private.petclass_game_plays(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.classroom_students(id),game text not null,price int not null,point_entry_id uuid not null references public.point_entries(id),request_id text unique,status text not null default 'pending',result text,target numeric,precision numeric,started_at timestamptz,elapsed numeric,created_at timestamptz not null default now());

create function private.pc_point_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op in('UPDATE','DELETE') and exists(select 1 from private.petclass_orders where point_entry_id=old.id or refund_entry_id=old.id) then raise exception '펫 구매 기록은 수정·삭제 대신 구매 내역에서 환불해 주세요.';end if;
 if tg_op='DELETE' then perform 1 from public.classroom_students where id=old.student_id for update;return old;end if;
 perform 1 from public.classroom_students where id=new.student_id for update;return new;
end$$;
create trigger petclass_point_guard before insert or update or delete on public.point_entries for each row execute function private.pc_point_guard();
create function private.pc_roll(p jsonb) returns text language plpgsql set search_path='' as $$
declare r numeric:=random()*100;acc numeric:=0;e jsonb;
begin
 for e in select value from jsonb_array_elements(p) loop acc:=acc+(e->>'weight')::numeric;if r<acc then return e->>'name';end if;end loop;
 return p->-1->>'name';
end$$;
create function private.pc_student(s public.classroom_students) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'studentNo',s.student_no,'name',case when s.student_no=0 then '테스트 학생' else lpad(s.student_no::text,2,'0')||'번 학생' end,'loginId',s.student_no::text,'role','student','mustChangePassword',false,'balance',coalesce((select sum(delta) from public.point_entries where student_id=s.id),0),'version',coalesce((select version from private.petclass_farms where student_id=s.id),0)) || coalesce((select data from private.petclass_farms where student_id=s.id),'{"pets":[],"inventory":[],"claimedStarter":false}'::jsonb);
$$;
