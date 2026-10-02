CREATE OR REPLACE FUNCTION public.classroom_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'deadline', (select application_deadline from public.classroom_settings where id = 1),
    'applicationsOpen', (select now() <= application_deadline from public.classroom_settings where id = 1),
    'roles', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'capacity',capacity,'salary',salary) order by display_order) from public.classroom_roles), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('number',student_no,'roleId',role_id) order by student_no) from public.classroom_students where student_no between 1 and 25), '[]'::jsonb),
    'applicationCounts', coalesce((select jsonb_object_agg(role_id, count) from (select role_id, count(*)::int as count from public.role_applications where status <> 'withdrawn' group by role_id) c), '{}'::jsonb),
    'applicationStudentCount', (select count(distinct student_id)::int from public.role_applications where status <> 'withdrawn'),
    'seatSelectionRemaining', greatest(0, 3 - (select count(*) from public.point_entries p where p.title = '학급 자리 선정권' and p.detail = '학급 상점 구매' and p.created_at >= date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')),
    'shopItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'price',price,'note',note,'icon',icon) order by case id when 'normal-draw-1' then 1 when 'normal-draw-3' then 2 when 'normal-draw-5' then 3 when 'premium-draw-1' then 4 when 'premium-draw-3' then 5 when 'premium-draw-5' then 6 when 'seat' then 7 else 99 end) from public.classroom_shop_items), '[]'::jsonb),
    'publicLedger', '[]'::jsonb
  );
$function$;

CREATE OR REPLACE FUNCTION public.student_purchase(p_code text, p_item_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_student public.classroom_students; v_item public.classroom_shop_items; v_balance int; v_seat_sold int; v_purchased_at timestamptz;
begin
  select * into v_student from public.classroom_students where access_code = p_code for update;
  if not found then raise exception '고유난수 4자리를 다시 확인하세요.'; end if;
  select * into v_item from public.classroom_shop_items where id = p_item_id;
  if not found then raise exception '상품을 확인하세요.'; end if;
  if v_item.id = 'seat' then
    -- ponytail: global lock; per-month lock only if seat purchases become high-volume.
    perform pg_advisory_xact_lock(734521);
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
$function$;

CREATE OR REPLACE FUNCTION public.teacher_run_payroll(p_token uuid, p_period text, p_adjustments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record; v_adjust jsonb; v_payout integer; v_reason text; v_rate integer; v_cumulative integer;
begin
  perform private.require_teacher(p_token);
  if p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array' then raise exception '월급 조정 값을 확인하세요.'; end if;
  for v_row in select s.id, s.student_no, r.id as role_id, r.name as role_name, r.salary from public.classroom_students s join public.classroom_roles r on r.id=s.role_id loop
    select value into v_adjust from jsonb_array_elements(p_adjustments) value where (value->>'studentNo')::smallint = v_row.student_no limit 1;
    v_adjust := coalesce(v_adjust, '{}'::jsonb);
    v_payout := coalesce((v_adjust->>'payout')::integer, v_row.salary);
    if v_payout < 0 or v_payout > v_row.salary then raise exception '학생 % 월급 조정값이 올바르지 않습니다.', v_row.student_no; end if;
    v_reason := left(coalesce(v_adjust->>'reason', '정상 지급'), 80);
    insert into public.point_entries(student_id, delta, title, detail)
    select v_row.id, v_payout, '역할 월급', p_period || ' 역할 월급 · ' || v_row.role_name || ' · ' || v_reason
    where v_payout > 0 and not exists (select 1 from public.point_entries p where p.student_id=v_row.id and p.title='역할 월급' and p.detail like p_period || ' 역할 월급 · ' || v_row.role_name || '%');
    if coalesce((v_adjust->>'cancelReadingBonus')::boolean, false) then
      delete from public.point_entries where student_id=v_row.id and title='다독이 추천 도서 추가' and detail like p_period || ' · %';
    end if;
    v_rate := coalesce((v_adjust->>'confiscateRate')::integer, 0);
    if v_rate between 1 and 100 and not exists (select 1 from public.point_entries p where p.student_id=v_row.id and p.title='누적 월급 몰수' and p.detail=p_period || ' · ' || v_rate || '%') then
      select coalesce(sum(delta), 0) into v_cumulative from public.point_entries where student_id=v_row.id and title='역할 월급';
      if floor(v_cumulative * v_rate / 100.0)>0 then insert into public.point_entries(student_id, delta, title, detail) values (v_row.id, -floor(v_cumulative * v_rate / 100.0)::integer, '누적 월급 몰수', p_period || ' · ' || v_rate || '%'); end if;
    end if;
  end loop;
  return public.teacher_snapshot(p_token);
end;
$function$;

alter table public.consultation_bookings drop constraint consultation_bookings_break_no_check;
alter table public.consultation_bookings add constraint consultation_bookings_break_no_check check(break_no between 1 and 8);
