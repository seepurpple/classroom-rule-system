create or replace function public.student_purchase(p_code text, p_item_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_student public.classroom_students; v_item public.classroom_shop_items; v_balance int; v_seat_sold int; v_purchased_at timestamptz;
begin
  select * into v_student from public.classroom_students where access_code = p_code;
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
$$;
