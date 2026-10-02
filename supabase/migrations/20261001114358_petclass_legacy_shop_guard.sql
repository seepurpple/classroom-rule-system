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
    'shopItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'price',price,'note',note,'icon',icon) order by case id when 'normal-draw-1' then 1 when 'normal-draw-3' then 2 when 'normal-draw-5' then 3 when 'premium-draw-1' then 4 when 'premium-draw-3' then 5 when 'premium-draw-5' then 6 when 'seat' then 7 else 99 end) from public.classroom_shop_items where id not in (select sku from private.petclass_products)), '[]'::jsonb),
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
  if exists(select 1 from private.petclass_products where sku=p_item_id) then raise exception '펫 용품은 PetClass에서 구매해 주세요.'; end if;
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
