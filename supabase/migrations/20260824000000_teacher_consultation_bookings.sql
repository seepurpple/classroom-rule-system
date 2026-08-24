create or replace function public.teacher_snapshot(p_token uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select private.require_teacher(p_token);
  select jsonb_build_object(
    'base', public.classroom_snapshot(),
    'students', coalesce((select jsonb_agg(jsonb_build_object('number',student_no,'roleId',role_id,'code',access_code,'balance',(select coalesce(sum(delta),0) from public.point_entries p where p.student_id=s.id)) order by student_no) from public.classroom_students s where student_no between 1 and 25), '[]'::jsonb),
    'applications', coalesce((select jsonb_agg(jsonb_build_object('studentNo',s.student_no,'roleId',a.role_id,'preference',a.preference,'status',a.status) order by s.student_no,a.preference) from public.role_applications a join public.classroom_students s on s.id=a.student_id where s.student_no between 1 and 25), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'studentNo',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'createdAt',p.created_at) order by p.created_at desc) from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.student_no between 1 and 25), '[]'::jsonb),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('studentNo',s.student_no,'date',to_char(b.consultation_date,'YYYY-MM-DD'),'breakNo',b.break_no,'createdAt',b.created_at) order by b.consultation_date,b.break_no) from public.consultation_bookings b join public.classroom_students s on s.id=b.student_id), '[]'::jsonb)
  );
$$;
