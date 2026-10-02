-- Remove the retired individual consultation feature (bookings are deleted).
begin;

create or replace function private.pc_legacy(a jsonb,n text,x jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid:=(a->>'teacherToken')::uuid;c text;r jsonb;
begin
 if n='classroom_snapshot' then return public.classroom_snapshot()-'publicLedger'||jsonb_build_object('publicLedger','[]'::jsonb);end if;
 if a is null then raise exception '먼저 PetClass에서 로그인해 주세요.';end if;
 if n in('identify_student','submit_role_applications') then
  if a->>'role'<>'student' then raise exception '학생 계정으로 로그인해 주세요.';end if;
  select access_code into c from public.classroom_students where id=(a->>'id')::uuid;
  case n when 'identify_student' then return public.identify_student(c);
  when 'submit_role_applications' then return public.submit_role_applications(c,array(select jsonb_array_elements_text(x->'p_role_ids')));end case;
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
 when 'teacher_change_password' then
  r:=public.teacher_change_password(t,x->>'p_new_password');
  update private.petclass_sessions set teacher_token=(r->>'token')::uuid where teacher_token=t;
  return jsonb_build_object('token','session','state',r->'state');
 else raise exception '지원하지 않는 작업입니다.';
 end case;
end$$;
revoke all on function private.pc_legacy(jsonb,text,jsonb) from public,anon,authenticated;

create or replace function public.teacher_snapshot(p_token uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select private.require_teacher(p_token);
  select jsonb_build_object(
    'base', public.classroom_snapshot(),
    'students', coalesce((select jsonb_agg(jsonb_build_object('number',student_no,'roleId',role_id,'code',access_code,'balance',(select coalesce(sum(delta),0) from public.point_entries p where p.student_id=s.id)) order by student_no) from public.classroom_students s where student_no between 1 and 25), '[]'::jsonb),
    'applications', coalesce((select jsonb_agg(jsonb_build_object('studentNo',s.student_no,'roleId',a.role_id,'preference',a.preference,'status',a.status) order by s.student_no,a.preference) from public.role_applications a join public.classroom_students s on s.id=a.student_id where s.student_no between 1 and 25), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'studentNo',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'createdAt',p.created_at) order by p.created_at desc) from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.student_no between 1 and 25), '[]'::jsonb)
  );
$$;

drop function if exists public.consultation_snapshot();
drop function if exists public.submit_consultation_booking(text,date,smallint);
drop function if exists public.teacher_update_consultation_settings(uuid,date,date,text);
drop function if exists public.teacher_update_consultation_settings(uuid,date,date,text,jsonb);
drop table if exists public.consultation_bookings;
alter table public.classroom_settings drop column if exists consultation_start, drop column if exists consultation_end, drop column if exists consultation_location, drop column if exists consultation_breaks;

commit;

select count(*) as "남은 상담 함수" from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and (p.proname ilike '%consult%' or p.prosrc ilike '%consultation%');
