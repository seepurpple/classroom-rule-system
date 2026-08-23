alter table public.classroom_settings add column if not exists consultation_breaks jsonb not null default '{"1":[],"2":[],"3":[],"4":[],"5":[]}'::jsonb;
create or replace function public.consultation_snapshot() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('startDate',s.consultation_start,'endDate',s.consultation_end,'location',s.consultation_location,'availableBreaks',s.consultation_breaks,
 'open',(current_date between s.consultation_start and s.consultation_end),
 'slots',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d::date,'YYYY-MM-DD'),'breakNo',q.break_no,'booked',x.student_id is not null) order by d,q.break_no)
 from generate_series(s.consultation_start,s.consultation_end,interval '1 day') d
 cross join lateral (select value::smallint as break_no from jsonb_array_elements_text(coalesce(s.consultation_breaks->extract(isodow from d)::text,'[]'::jsonb))) q
 left join public.consultation_bookings x on x.consultation_date=d::date and x.break_no=q.break_no
 where extract(isodow from d) between 1 and 5),'[]'::jsonb)) from public.classroom_settings s where s.id=1;
$$;

create or replace function public.submit_consultation_booking(p_code text,p_date date,p_break_no smallint) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student public.classroom_students; v_start date; v_end date; v_breaks jsonb;
begin
 select * into v_student from public.classroom_students where access_code=p_code; if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
 select consultation_start,consultation_end,consultation_breaks into v_start,v_end,v_breaks from public.classroom_settings where id=1;
 if current_date not between v_start and v_end then raise exception '상담 신청 기간이 아닙니다.'; end if;
 if p_date not between v_start and v_end or extract(isodow from p_date) not between 1 and 5 or not exists(select 1 from jsonb_array_elements_text(coalesce(v_breaks->extract(isodow from p_date)::text,'[]'::jsonb)) q where q.value::smallint=p_break_no) then raise exception '상담 시간을 확인하세요.'; end if;
 if exists(select 1 from public.consultation_bookings where consultation_date=p_date and break_no=p_break_no and student_id<>v_student.id) then raise exception '이미 신청된 시간입니다.'; end if;
 insert into public.consultation_bookings(student_id,consultation_date,break_no) values(v_student.id,p_date,p_break_no)
 on conflict(student_id) do update set consultation_date=excluded.consultation_date,break_no=excluded.break_no;
 return jsonb_build_object('studentNo',v_student.student_no,'state',public.consultation_snapshot());
end; $$;

drop function if exists public.teacher_update_consultation_settings(uuid,date,date,text);
create function public.teacher_update_consultation_settings(p_token uuid,p_start date,p_end date,p_location text,p_breaks jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_teacher(p_token); if p_end<p_start then raise exception '종료일은 시작일 이후여야 합니다.'; end if;
 if jsonb_typeof(p_breaks)<>'object' or exists(select 1 from jsonb_each(p_breaks) e where e.key not in ('1','2','3','4','5') or jsonb_typeof(e.value)<>'array' or exists(select 1 from jsonb_array_elements_text(e.value) q where q.value !~ '^[1-8]$')) then raise exception '요일별 쉬는시간 설정을 확인하세요.'; end if;
 if exists(select 1 from public.consultation_bookings b where b.consultation_date not between p_start and p_end or extract(isodow from b.consultation_date) not between 1 and 5 or not exists(select 1 from jsonb_array_elements_text(coalesce(p_breaks->extract(isodow from b.consultation_date)::text,'[]'::jsonb)) q where q.value::smallint=b.break_no)) then raise exception '새 설정에서 제외되는 신청이 있어 먼저 조정해야 합니다.'; end if;
 update public.classroom_settings set consultation_start=p_start,consultation_end=p_end,consultation_location=left(coalesce(p_location,''),80),consultation_breaks=jsonb_build_object('1',coalesce(p_breaks->'1','[]'::jsonb),'2',coalesce(p_breaks->'2','[]'::jsonb),'3',coalesce(p_breaks->'3','[]'::jsonb),'4',coalesce(p_breaks->'4','[]'::jsonb),'5',coalesce(p_breaks->'5','[]'::jsonb)) where id=1;
 return public.teacher_snapshot(p_token);
end; $$;

create function public.teacher_update_consultation_settings(p_token uuid,p_start date,p_end date,p_location text) returns jsonb language sql security definer set search_path='' as $$
 select public.teacher_update_consultation_settings(p_token,p_start,p_end,p_location,consultation_breaks) from public.classroom_settings where id=1;
$$;
