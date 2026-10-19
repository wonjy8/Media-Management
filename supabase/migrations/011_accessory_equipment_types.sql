-- Apply after 010. No Edge Function redeploy is required.
begin;
lock table public.equipment in share row exclusive mode;
alter table public.equipment add column if not exists is_accessory boolean not null default false;
-- Preserve existing one-level links; nested legacy links must be corrected before migration.
do $$begin
 if exists(select 1 from equipment_accessories a join equipment_accessories b on a.accessory_id=b.equipment_id) then
  raise exception '기존 부속품의 중첩 연결을 먼저 해제해 주세요.';
 end if;
end $$;
update equipment set is_accessory=true where id in(select accessory_id from equipment_accessories) and not is_accessory;

-- Deferred validation allows an equipment record and all links to change atomically.
create or replace function public.validate_equipment_accessory_roles() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 perform pg_advisory_xact_lock(hashtext('equipment-accessory-roles'));
 if exists(select 1 from equipment_accessories a join equipment p on p.id=a.equipment_id join equipment c on c.id=a.accessory_id where p.is_accessory or not c.is_accessory) then
  raise exception '부속품에는 다른 부속품을 연결할 수 없습니다. 일반 장비와 부속품을 연결해 주세요.' using errcode='23514';
 end if;
 if exists(select 1 from equipment e where e.is_accessory and not exists(select 1 from equipment_accessories a where a.accessory_id=e.id)) then
  raise exception '부속품이 종속될 장비를 하나 이상 선택해 주세요.' using errcode='23514';
 end if;
 return null;
end $$;
revoke all on function public.validate_equipment_accessory_roles() from public,anon,authenticated;
drop trigger if exists accessory_roles_equipment on public.equipment;
create constraint trigger accessory_roles_equipment after insert or update or delete on public.equipment
 deferrable initially deferred for each row execute function public.validate_equipment_accessory_roles();
drop trigger if exists accessory_roles_links on public.equipment_accessories;
create constraint trigger accessory_roles_links after insert or update or delete on public.equipment_accessories
 deferrable initially deferred for each row execute function public.validate_equipment_accessory_roles();

-- If a parent is physically deleted, hide orphan accessories rather than exposing them as standalone items.
create or replace function public.archive_orphan_accessories_on_delete() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 update equipment set is_accessory=false,active=false where is_accessory and id in(
  select a.accessory_id from equipment_accessories a where a.equipment_id=old.id
  and not exists(select 1 from equipment_accessories other where other.accessory_id=a.accessory_id and other.equipment_id<>old.id)
 );
 return old;
end $$;
revoke all on function public.archive_orphan_accessories_on_delete() from public,anon,authenticated;
drop trigger if exists archive_parent_accessories on public.equipment;
create trigger archive_parent_accessories before delete on public.equipment for each row execute function public.archive_orphan_accessories_on_delete();

-- Keep the validated 010 save as a private implementation detail, avoiding ambiguous RPC overloads.
do $$begin
 if to_regprocedure('public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid)') is not null then
  alter function public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid) rename to save_equipment_catalog_v10;
 end if;
end $$;
revoke all on function public.save_equipment_catalog_v10(jsonb,jsonb,uuid) from public,anon,authenticated;
create or replace function public.admin_save_equipment_with_accessories(p_equipment jsonb,p_accessories jsonb,p_id uuid default null,p_parents jsonb default '[]')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;is_part boolean;link jsonb;parent_id uuid;seen uuid[]:=array[]::uuid[];
begin
 if not public.is_admin() then raise exception 'FORBIDDEN' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtext('equipment-accessory-roles'));
 if p_equipment?'is_accessory' and jsonb_typeof(p_equipment->'is_accessory') is distinct from 'boolean' then raise exception 'INVALID_REQUEST';end if;
 is_part:=coalesce((p_equipment->>'is_accessory')::boolean,false);
 if jsonb_typeof(p_parents) is distinct from 'array' or jsonb_typeof(p_accessories) is distinct from 'array' then raise exception 'INVALID_REQUEST';end if;
 if jsonb_array_length(p_parents)>50 or (is_part and (jsonb_array_length(p_parents)=0 or jsonb_array_length(p_accessories)>0)) or (not is_part and jsonb_array_length(p_parents)>0) then
  raise exception '부속품은 일반 장비에 하나 이상 연결해야 하며, 다른 부속품을 연결할 수 없습니다.' using errcode='23514';
 end if;
 v_id:=save_equipment_catalog_v10(p_equipment,p_accessories,p_id);
 update equipment set is_accessory=is_part where id=v_id;
 delete from equipment_accessories where accessory_id=v_id;
 if is_part then
  for link in select * from jsonb_array_elements(p_parents) loop
   if jsonb_typeof(link) is distinct from 'object' or nullif(link->>'id','') is null or
    jsonb_typeof(link->'quantity') is distinct from 'number' or (link->>'quantity') !~ '^[0-9]+$' or (link->>'quantity')::numeric not between 1 and 10000 or
    jsonb_typeof(link->'selectedByDefault') is distinct from 'boolean' then raise exception 'INVALID_REQUEST';end if;
   parent_id:=(link->>'id')::uuid;
   if parent_id=v_id or parent_id=any(seen) then raise exception 'INVALID_REQUEST';end if;
   insert into equipment_accessories(equipment_id,accessory_id,quantity,selected_by_default)
    values(parent_id,v_id,(link->>'quantity')::integer,(link->>'selectedByDefault')::boolean);
   seen:=array_append(seen,parent_id);
  end loop;
 end if;
 -- Run validation now as well, so API clients receive an actionable error before committing.
 if exists(select 1 from equipment_accessories a join equipment p on p.id=a.equipment_id join equipment c on c.id=a.accessory_id where p.is_accessory or not c.is_accessory) or
  exists(select 1 from equipment e where e.is_accessory and not exists(select 1 from equipment_accessories a where a.accessory_id=e.id)) then
  raise exception '부속품은 일반 장비에 하나 이상 연결해야 하며, 다른 부속품을 연결할 수 없습니다.' using errcode='23514';
 end if;
 return v_id;
end $$;
revoke all on function public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid,jsonb) from public,anon;
grant execute on function public.admin_save_equipment_with_accessories(jsonb,jsonb,uuid,jsonb) to authenticated;

-- Accessory IDs cannot be used to submit standalone requests through the public API either.
create or replace function public.validate_loan_accessory_parents() returns trigger
language plpgsql security definer set search_path=public as $$
declare target uuid;
begin
 if tg_op='UPDATE' and new.equipment_id=old.equipment_id and new.quantity=old.quantity then return null;end if;
 target:=coalesce(new.loan_id,old.loan_id);
 if exists(select 1 from loan_items li join equipment e on e.id=li.equipment_id where li.loan_id=target and e.is_accessory
  and not exists(select 1 from equipment_accessories a join loan_items p on p.equipment_id=a.equipment_id and p.loan_id=target where a.accessory_id=e.id)) then
  raise exception 'INVALID_REQUEST: ACCESSORY_REQUIRES_PARENT';
 end if;
 return null;
end $$;
revoke all on function public.validate_loan_accessory_parents() from public,anon,authenticated;
drop trigger if exists loan_accessory_parents on public.loan_items;
create constraint trigger loan_accessory_parents after insert or update or delete on public.loan_items
 deferrable initially deferred for each row execute function public.validate_loan_accessory_parents();
commit;
