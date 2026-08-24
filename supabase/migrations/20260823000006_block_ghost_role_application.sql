create or replace function public.submit_role_applications(p_code text, p_role_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student public.classroom_students; v_deadline timestamptz;
begin
  select application_deadline into v_deadline from public.classroom_settings where id = 1;
  if now() > v_deadline then raise exception '역할 지원 기간이 마감되었습니다.'; end if;
  if cardinality(p_role_ids) <> 1 then raise exception '희망 역할은 1개만 선택하세요.'; end if;
  if (select count(*) from public.classroom_roles where id = any(p_role_ids)) <> 1 then raise exception '지원 역할을 확인하세요.'; end if;
  select * into v_student from public.classroom_students where access_code = p_code;
  if not found or v_student.student_no = 0 then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
  if v_student.role_id is not null then raise exception '이미 역할이 배정되었습니다.'; end if;
  delete from public.role_applications where student_id = v_student.id;
  insert into public.role_applications(student_id, role_id, preference) values (v_student.id, p_role_ids[1], 1);
  return jsonb_build_object('studentNo', v_student.student_no, 'snapshot', public.classroom_snapshot());
end;
$$;
