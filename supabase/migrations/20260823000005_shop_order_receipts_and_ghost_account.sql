alter table public.classroom_students drop constraint classroom_students_student_no_check;
alter table public.classroom_students add constraint classroom_students_student_no_check check (student_no between 0 and 25);

insert into public.classroom_students (student_no, access_code, role_id)
values (0, '2456', null)
on conflict (student_no) do update set access_code = excluded.access_code, role_id = null;

insert into public.point_entries (student_id, delta, title, detail)
select id, 99999, '고스트 시작 포인트', '고스트 계정 전용'
from public.classroom_students
where student_no = 0
  and not exists (
    select 1 from public.point_entries p
    where p.student_id = public.classroom_students.id and p.title = '고스트 시작 포인트'
  );

create or replace function public.classroom_snapshot()
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object(
    'deadline', (select application_deadline from public.classroom_settings where id = 1),
    'applicationsOpen', (select now() <= application_deadline from public.classroom_settings where id = 1),
    'roles', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'capacity',capacity,'salary',salary) order by display_order) from public.classroom_roles), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('number',student_no,'roleId',role_id) order by student_no) from public.classroom_students where student_no between 1 and 25), '[]'::jsonb),
    'applicationCounts', coalesce((select jsonb_object_agg(role_id, count) from (select role_id, count(*)::int as count from public.role_applications where status <> 'withdrawn' group by role_id) c), '{}'::jsonb),
    'applicationStudentCount', (select count(distinct student_id)::int from public.role_applications where status <> 'withdrawn'),
    'seatSelectionRemaining', greatest(0, 3 - (select count(*) from public.point_entries p where p.title = '학급 자리 선정권' and p.detail = '학급 상점 구매' and p.created_at >= date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')),
    'shopItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'price',price,'note',note,'icon',icon) order by case id when 'normal-draw-1' then 1 when 'normal-draw-3' then 2 when 'normal-draw-5' then 3 when 'premium-draw-1' then 4 when 'premium-draw-3' then 5 when 'premium-draw-5' then 6 when 'seat' then 7 else 99 end) from public.classroom_shop_items), '[]'::jsonb),
    'publicLedger', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'studentNo',s.student_no,'delta',p.delta,'title',p.title,'detail',p.detail,'createdAt',p.created_at) order by p.created_at desc) from public.point_entries p join public.classroom_students s on s.id=p.student_id where s.student_no between 1 and 25), '[]'::jsonb)
  );
$$;

create or replace function public.student_purchase(p_code text, p_item_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student public.classroom_students; v_item public.classroom_shop_items; v_balance int; v_seat_sold int; v_purchased_at timestamptz;
begin
  select * into v_student from public.classroom_students where access_code = p_code;
  if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
  select * into v_item from public.classroom_shop_items where id = p_item_id;
  if not found then raise exception '상품을 확인하세요.'; end if;
  if v_item.id = 'seat' then
    select count(*) into v_seat_sold from public.point_entries
    where title = '학급 자리 선정권' and detail = '학급 상점 구매'
      and created_at >= date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
    if v_seat_sold >= 3 then raise exception '이번 달 자리 선정권은 모두 소진되었습니다.'; end if;
  end if;
  select coalesce(sum(delta), 0) into v_balance from public.point_entries where student_id = v_student.id;
  if v_balance < v_item.price then raise exception '포인트가 부족합니다.'; end if;
  insert into public.point_entries(student_id, delta, title, detail)
  values(v_student.id, -v_item.price, v_item.name, '학급 상점 구매')
  returning created_at into v_purchased_at;
  return jsonb_build_object('message', '구매 완료!', 'purchasedAt', to_char(v_purchased_at at time zone 'Asia/Seoul', 'YYYY.MM.DD HH24:MI'), 'state', public.classroom_snapshot());
end;
$$;

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

create or replace function public.identify_student(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.classroom_students;
begin
  select * into s from public.classroom_students where access_code = p_code;
  if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
  if s.student_no = 0 then raise exception '고스트 계정은 상점에서만 사용할 수 있어요.'; end if;
  return jsonb_build_object('studentNo',s.student_no,'assigned',s.role_id is not null,'roleIds',coalesce((select jsonb_agg(role_id order by preference) from public.role_applications where student_id=s.id and status='pending'),'[]'::jsonb));
end;
$$;

create or replace function public.submit_consultation_booking(p_code text, p_date date, p_break_no smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student public.classroom_students; v_start date; v_end date; v_breaks jsonb;
begin
 select * into v_student from public.classroom_students where access_code=p_code; if not found or v_student.student_no = 0 then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
 select consultation_start,consultation_end,consultation_breaks into v_start,v_end,v_breaks from public.classroom_settings where id=1;
 if current_date not between v_start and v_end then raise exception '상담 신청 기간이 아닙니다.'; end if;
 if p_date not between v_start and v_end or extract(isodow from p_date) not between 1 and 5 or not exists(select 1 from jsonb_array_elements_text(coalesce(v_breaks->extract(isodow from p_date)::text,'[]'::jsonb)) q where q.value::smallint=p_break_no) then raise exception '상담 시간을 확인하세요.'; end if;
 if exists(select 1 from public.consultation_bookings where consultation_date=p_date and break_no=p_break_no and student_id<>v_student.id) then raise exception '이미 신청된 시간입니다.'; end if;
 insert into public.consultation_bookings(student_id,consultation_date,break_no) values(v_student.id,p_date,p_break_no) on conflict(student_id) do update set consultation_date=excluded.consultation_date,break_no=excluded.break_no;
 return jsonb_build_object('studentNo',v_student.student_no,'state',public.consultation_snapshot());
end;
$$;

create or replace function public.teacher_record_class_points(p_token uuid, p_delta integer, p_title text, p_detail text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_teacher(p_token);
  if p_delta = 0 then raise exception '포인트를 확인하세요.'; end if;
  insert into public.point_entries(student_id, delta, title, detail)
  select id, p_delta, left(p_title, 40), left(coalesce(p_detail, ''), 80) from public.classroom_students where student_no between 1 and 25;
  return public.teacher_snapshot(p_token);
end;
$$;
