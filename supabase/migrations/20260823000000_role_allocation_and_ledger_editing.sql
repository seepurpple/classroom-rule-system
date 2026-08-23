-- Allocate after deadline so every applicant to an oversubscribed role enters one draw.
alter table public.role_applications drop constraint role_applications_status_check;
alter table public.role_applications add constraint role_applications_status_check
  check (status = any (array['pending', 'assigned', 'unassigned', 'withdrawn']));

create or replace function public.submit_role_applications(p_code text, p_role_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student public.classroom_students; v_deadline timestamptz;
begin
  select application_deadline into v_deadline from public.classroom_settings where id = 1;
  if now() > v_deadline then raise exception '역할 지원 기간이 마감되었습니다.'; end if;
  if cardinality(p_role_ids) <> 1 then raise exception '희망 역할은 1개만 선택하세요.'; end if;
  if (select count(*) from public.classroom_roles where id = any(p_role_ids)) <> 1 then raise exception '지원 역할을 확인하세요.'; end if;
  select * into v_student from public.classroom_students where access_code = p_code;
  if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
  if v_student.role_id is not null then raise exception '이미 역할이 배정되었습니다.'; end if;
  delete from public.role_applications where student_id = v_student.id;
  insert into public.role_applications(student_id, role_id, preference) values (v_student.id, p_role_ids[1], 1);
  return jsonb_build_object('studentNo', v_student.student_no, 'snapshot', public.classroom_snapshot());
end;
$$;

create or replace function public.classroom_snapshot()
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object(
    'deadline', (select application_deadline from public.classroom_settings where id = 1),
    'applicationsOpen', (select now() <= application_deadline from public.classroom_settings where id = 1),
    'roles', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'capacity',capacity,'salary',salary) order by display_order) from public.classroom_roles), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('number',student_no,'roleId',role_id) order by student_no) from public.classroom_students), '[]'::jsonb),
    'applicationCounts', coalesce((select jsonb_object_agg(role_id, count) from (select role_id, count(*)::int as count from public.role_applications where status <> 'withdrawn' group by role_id) c), '{}'::jsonb),
    'applicationStudentCount', (select count(distinct student_id)::int from public.role_applications where status <> 'withdrawn'),
    'shopItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'price',price,'note',note,'icon',icon) order by price) from public.classroom_shop_items), '[]'::jsonb),
    'publicLedger', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'studentNo',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'createdAt',p.created_at) order by p.created_at desc) from public.point_entries p join public.classroom_students s on s.id=p.student_id), '[]'::jsonb)
  );
$$;

create or replace function public.teacher_lottery(p_token uuid, p_role_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_capacity int; v_candidate_ids uuid[]; v_winner_ids uuid[]; v_student_nos jsonb;
begin
  perform private.require_teacher(p_token);
  if now() <= (select application_deadline from public.classroom_settings where id = 1) then raise exception '지원 마감 후 추첨할 수 있습니다.'; end if;
  select capacity into v_capacity from public.classroom_roles where id = p_role_id;
  if not found then raise exception '존재하지 않는 역할입니다.'; end if;
  if exists (select 1 from public.role_applications where role_id = p_role_id and status = 'unassigned') then raise exception '이미 추첨을 완료했습니다.'; end if;
  select coalesce(array_agg(student_id), '{}') into v_candidate_ids from public.role_applications where role_id = p_role_id and status in ('pending', 'assigned');
  if cardinality(v_candidate_ids) <= v_capacity then raise exception '정원 초과 지원 역할이 아닙니다.'; end if;
  select coalesce(array_agg(student_id), '{}') into v_winner_ids from (select student_id from public.role_applications where student_id = any(v_candidate_ids) order by random() limit v_capacity) winners;
  update public.classroom_students set role_id = null where id = any(v_candidate_ids) and role_id = p_role_id;
  update public.classroom_students set role_id = p_role_id where id = any(v_winner_ids);
  update public.role_applications set status = case when student_id = any(v_winner_ids) then 'assigned' else 'unassigned' end where role_id = p_role_id and student_id = any(v_candidate_ids);
  select coalesce(jsonb_agg(student_no order by student_no), '[]'::jsonb) into v_student_nos from public.classroom_students where id = any(v_winner_ids);
  return jsonb_build_object('studentNos', v_student_nos, 'state', public.teacher_snapshot(p_token));
end;
$$;

create or replace function public.teacher_fill_unassigned_roles(p_token uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student_nos jsonb;
begin
  perform private.require_teacher(p_token);
  if now() <= (select application_deadline from public.classroom_settings where id = 1) then raise exception '지원 마감 후 배정할 수 있습니다.'; end if;
  with openings as (
    select r.id as role_id, r.capacity - count(s.id)::int as slots
    from public.classroom_roles r left join public.classroom_students s on s.role_id = r.id group by r.id, r.capacity
  ), eligible as (
    select a.student_id, a.role_id from public.role_applications a join openings o on o.role_id = a.role_id
    where a.status = 'pending' and o.slots > 0
      and (select count(*) from public.role_applications x where x.role_id = a.role_id and x.status in ('pending', 'assigned')) <= o.slots
  ) update public.classroom_students s set role_id = e.role_id from eligible e where s.id = e.student_id and s.role_id is null;
  update public.role_applications a set status = 'assigned' from public.classroom_students s
  where a.student_id = s.id and a.status = 'pending' and a.role_id = s.role_id;
  with openings as (
    select r.id as role_id, generate_series(1, greatest(r.capacity - count(s.id)::int, 0)) as slot
    from public.classroom_roles r left join public.classroom_students s on s.role_id = r.id group by r.id, r.capacity
  ), candidates as (
    select id, row_number() over (order by random()) as slot from public.classroom_students where role_id is null
  ), assigned as (
    update public.classroom_students s set role_id = o.role_id from openings o join candidates c using (slot) where s.id = c.id returning s.student_no
  ) select coalesce(jsonb_agg(student_no order by student_no), '[]'::jsonb) into v_student_nos from assigned;
  return jsonb_build_object('studentNos', v_student_nos, 'state', public.teacher_snapshot(p_token));
end;
$$;

create or replace function public.teacher_update_point_entry(p_token uuid, p_entry_id uuid, p_delta integer, p_title text, p_detail text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_teacher(p_token);
  if p_delta = 0 or btrim(coalesce(p_title, '')) = '' then raise exception '포인트와 내역을 확인하세요.'; end if;
  update public.point_entries set delta = p_delta, title = left(btrim(p_title), 40), detail = left(coalesce(p_detail, ''), 80) where id = p_entry_id;
  if not found then raise exception '포인트 기록을 찾을 수 없습니다.'; end if;
  return public.teacher_snapshot(p_token);
end;
$$;

create or replace function public.teacher_delete_point_entry(p_token uuid, p_entry_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_teacher(p_token);
  delete from public.point_entries where id = p_entry_id;
  if not found then raise exception '포인트 기록을 찾을 수 없습니다.'; end if;
  return public.teacher_snapshot(p_token);
end;
$$;
