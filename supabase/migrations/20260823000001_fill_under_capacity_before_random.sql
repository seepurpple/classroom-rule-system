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
