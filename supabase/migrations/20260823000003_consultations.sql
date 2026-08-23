alter table public.classroom_settings add column if not exists consultation_start date not null default date '2026-08-24';
alter table public.classroom_settings add column if not exists consultation_end date not null default date '2026-08-31';
alter table public.classroom_settings add column if not exists consultation_location text not null default '';
create table if not exists public.consultation_bookings (
  student_id uuid primary key references public.classroom_students(id) on delete cascade,
  consultation_date date not null,
  break_no smallint not null check (break_no in (1,2)),
  created_at timestamptz not null default now(),
  unique (consultation_date, break_no)
);
alter table public.consultation_bookings enable row level security;

create or replace function public.consultation_snapshot() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('startDate',s.consultation_start,'endDate',s.consultation_end,'location',s.consultation_location,
 'open',(current_date between s.consultation_start and s.consultation_end),
 'slots',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d::date,'YYYY-MM-DD'),'breakNo',b,'booked',x.student_id is not null) order by d,b)
 from generate_series(s.consultation_start,s.consultation_end,interval '1 day') d cross join (values(1),(2)) q(b)
 left join public.consultation_bookings x on x.consultation_date=d::date and x.break_no=b),'[]'::jsonb)) from public.classroom_settings s where s.id=1;
$$;

create or replace function public.submit_consultation_booking(p_code text,p_date date,p_break_no smallint) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student public.classroom_students; v_start date; v_end date;
begin
 select * into v_student from public.classroom_students where access_code=p_code; if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
 select consultation_start,consultation_end into v_start,v_end from public.classroom_settings where id=1;
 if current_date not between v_start and v_end then raise exception '상담 신청 기간이 아닙니다.'; end if;
 if p_date not between v_start and v_end or p_break_no not in (1,2) then raise exception '상담 시간을 확인하세요.'; end if;
 if exists(select 1 from public.consultation_bookings where consultation_date=p_date and break_no=p_break_no and student_id<>v_student.id) then raise exception '이미 신청된 시간입니다.'; end if;
 insert into public.consultation_bookings(student_id,consultation_date,break_no) values(v_student.id,p_date,p_break_no)
 on conflict(student_id) do update set consultation_date=excluded.consultation_date,break_no=excluded.break_no;
 return jsonb_build_object('studentNo',v_student.student_no,'state',public.consultation_snapshot());
end; $$;

create or replace function public.teacher_update_consultation_settings(p_token uuid,p_start date,p_end date,p_location text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_teacher(p_token); if p_end<p_start then raise exception '종료일은 시작일 이후여야 합니다.'; end if;
 if exists(select 1 from public.consultation_bookings where consultation_date not between p_start and p_end) then raise exception '새 기간 밖의 신청이 있어 먼저 조정해야 합니다.'; end if;
 update public.classroom_settings set consultation_start=p_start,consultation_end=p_end,consultation_location=left(coalesce(p_location,''),80) where id=1;
 return public.teacher_snapshot(p_token);
end; $$;
