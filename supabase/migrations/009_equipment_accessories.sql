-- Apply after 008. Existing stock checks and item-by-item returns also cover accessories.
-- No Edge Function redeploy is required.
begin;
create table if not exists public.equipment_accessories (
 equipment_id uuid not null references public.equipment(id) on delete cascade,
 accessory_id uuid not null references public.equipment(id) on delete cascade,
 quantity integer not null default 1 check(quantity between 1 and 10000),
 selected_by_default boolean not null default true,
 primary key(equipment_id,accessory_id),check(equipment_id<>accessory_id)
);
create index if not exists equipment_accessories_child on public.equipment_accessories(accessory_id);
alter table public.equipment_accessories enable row level security;
drop policy if exists equipment_accessories_read on public.equipment_accessories;
create policy equipment_accessories_read on public.equipment_accessories for select to anon,authenticated using (
 public.is_admin() or (
 exists(select 1 from public.equipment where id=equipment_id and active) and
 exists(select 1 from public.equipment where id=accessory_id and active)
 ));
revoke all on public.equipment_accessories from anon,authenticated;
grant select on public.equipment_accessories to anon,authenticated;

-- Save equipment and replace its accessory links in one transaction.
create or replace function public.admin_save_equipment_with_accessories(p_equipment jsonb,p_accessories jsonb,p_id uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; link jsonb; child uuid;seen uuid[]:=array[]::uuid[];
begin
 if not public.is_admin() then raise exception 'FORBIDDEN' using errcode='42501';end if;
 if jsonb_typeof(p_equipment) is distinct from 'object' or
 length(trim(coalesce(p_equipment->>'name','')))=0 or length(p_equipment->>'name')>150 or
 length(trim(coalesce(p_equipment->>'code','')))=0 or length(p_equipment->>'code')>80 or
 jsonb_typeof(p_equipment->'quantity') is distinct from 'number' or (p_equipment->>'quantity') !~ '^[0-9]+$' or
 jsonb_typeof(p_equipment->'repair_quantity') is distinct from 'number' or (p_equipment->>'repair_quantity') !~ '^[0-9]+$' or
 (p_equipment->>'quantity')::numeric>10000 or (p_equipment->>'repair_quantity')::numeric>(p_equipment->>'quantity')::numeric or
 jsonb_typeof(p_equipment->'active') is distinct from 'boolean' or
 jsonb_typeof(p_accessories) is distinct from 'array' then raise exception 'INVALID_REQUEST';end if;
 if jsonb_array_length(p_accessories)>50 then raise exception 'INVALID_ACCESSORIES';end if;
 if p_id is null then
  insert into equipment(code,name,model,group_id,image_path,description,quantity,repair_quantity,active)
  values(trim(p_equipment->>'code'),trim(p_equipment->>'name'),p_equipment->>'model',nullif(p_equipment->>'group_id','')::uuid,
   p_equipment->>'image_path',p_equipment->>'description',(p_equipment->>'quantity')::integer,(p_equipment->>'repair_quantity')::integer,(p_equipment->>'active')::boolean)
  returning id into v_id;
 else
  update equipment set code=trim(p_equipment->>'code'),name=trim(p_equipment->>'name'),model=p_equipment->>'model',
   group_id=nullif(p_equipment->>'group_id','')::uuid,image_path=p_equipment->>'image_path',description=p_equipment->>'description',
   quantity=(p_equipment->>'quantity')::integer,repair_quantity=(p_equipment->>'repair_quantity')::integer,active=(p_equipment->>'active')::boolean
  where id=p_id returning id into v_id;
  if v_id is null then raise exception 'NOT_FOUND';end if;
 end if;
 delete from equipment_accessories where equipment_id=v_id;
 for link in select * from jsonb_array_elements(p_accessories) loop
  if jsonb_typeof(link) is distinct from 'object' or jsonb_typeof(link->'quantity') is distinct from 'number' or
   (link->>'quantity') !~ '^[0-9]+$' or (link->>'quantity')::numeric not between 1 and 10000 or
   jsonb_typeof(link->'selectedByDefault') is distinct from 'boolean' or nullif(link->>'id','') is null then raise exception 'INVALID_ACCESSORIES';end if;
  child:=(link->>'id')::uuid;
  if child=v_id or child=any(seen) then raise exception 'INVALID_ACCESSORIES';end if;
  insert into equipment_accessories(equipment_id,accessory_id,quantity,selected_by_default)
  values(v_id,child,(link->>'quantity')::integer,(link->>'selectedByDefault')::boolean);
  seen:=array_append(seen,child);
 end loop;
 return v_id;
end $$;
revoke all on function public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid) from public,anon;
grant execute on function public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid) to authenticated;
commit;
