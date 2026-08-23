create table if not exists public.role_lottery_audit (
  id uuid primary key default gen_random_uuid(),
  role_id text not null references public.classroom_roles(id) on delete cascade,
  candidate_student_nos smallint[] not null,
  winner_student_nos smallint[] not null,
  reason text not null default 'final_draw',
  created_at timestamptz not null default now()
);
alter table public.role_lottery_audit enable row level security;

create or replace function public.teacher_lottery(p_token uuid, p_role_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_capacity int; v_candidate_ids uuid[]; v_winner_ids uuid[]; v_student_nos jsonb; v_candidate_nos smallint[]; v_winner_nos smallint[];
begin
  perform private.require_teacher(p_token);
  if now() <= (select application_deadline from public.classroom_settings where id = 1) then raise exception '지원 마감 후 추첨할 수 있습니다.'; end if;
  select capacity into v_capacity from public.classroom_roles where id = p_role_id;
  if not found then raise exception '존재하지 않는 역할입니다.'; end if;
  if exists (select 1 from public.role_applications where role_id = p_role_id and status = 'unassigned') then raise exception '이미 추첨을 완료했습니다.'; end if;
  select coalesce(array_agg(student_id), '{}') into v_candidate_ids from public.role_applications where role_id = p_role_id and status in ('pending', 'assigned');
  if cardinality(v_candidate_ids) <= v_capacity then raise exception '정원 초과 지원 역할이 아닙니다.'; end if;
  select coalesce(array_agg(student_no order by student_no), '{}') into v_candidate_nos from public.classroom_students where id = any(v_candidate_ids);
  select coalesce(array_agg(student_id), '{}') into v_winner_ids from (select student_id from public.role_applications where student_id = any(v_candidate_ids) order by random() limit v_capacity) winners;
  update public.classroom_students set role_id = null where id = any(v_candidate_ids) and role_id = p_role_id;
  update public.classroom_students set role_id = p_role_id where id = any(v_winner_ids);
  update public.role_applications set status = case when student_id = any(v_winner_ids) then 'assigned' else 'unassigned' end where role_id = p_role_id and student_id = any(v_candidate_ids);
  select coalesce(array_agg(student_no order by student_no), '{}') into v_winner_nos from public.classroom_students where id = any(v_winner_ids);
  insert into public.role_lottery_audit(role_id, candidate_student_nos, winner_student_nos) values (p_role_id, v_candidate_nos, v_winner_nos);
  select coalesce(jsonb_agg(student_no order by student_no), '[]'::jsonb) into v_student_nos from public.classroom_students where id = any(v_winner_ids);
  return jsonb_build_object('studentNos', v_student_nos, 'state', public.teacher_snapshot(p_token));
end;
$$;
