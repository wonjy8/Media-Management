-- Only administrators may delete catalog records. Preserve referenced equipment.
create or replace function public.admin_delete_catalog(p_kind text,p_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare result text;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_kind='group' then
  perform 1 from groups where id=p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  update equipment set group_id=null where group_id=p_id;
  delete from groups where id=p_id;
  result:='deleted';
 elsif p_kind='equipment' then
  perform 1 from equipment where id=p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if exists(select 1 from loan_items where equipment_id=p_id) then
   update equipment set active=false where id=p_id;
   result:='archived';
  else
   delete from equipment where id=p_id;
   result:='deleted';
  end if;
 else raise exception 'INVALID_REQUEST'; end if;
 insert into audit_log(actor,action,metadata) values(auth.uid(),p_kind||'_'||result,jsonb_build_object('id',p_id));
 return result;
end $$;
revoke all on function public.admin_delete_catalog(text,uuid) from public,anon;
grant execute on function public.admin_delete_catalog(text,uuid) to authenticated;
