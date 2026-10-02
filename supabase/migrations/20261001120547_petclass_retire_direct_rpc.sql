-- Apply only after the PetClass deployment replaces the legacy production site.
-- Internal SECURITY DEFINER calls remain available to the gateway owner.
do $$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (
 p.proname like 'teacher\_%' escape '\'
 or p.proname in ('classroom_snapshot','consultation_snapshot','identify_student','student_purchase','submit_consultation_booking','submit_role_applications'))
 loop execute 'revoke all on function '||f.signature||' from public, anon, authenticated';end loop;
end$$;
revoke all on function public.petclass_gateway(text,text,text,jsonb) from public, authenticated;
grant execute on function public.petclass_gateway(text,text,text,jsonb) to anon;
