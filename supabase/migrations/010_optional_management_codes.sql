-- Apply after 009. Blank management codes are NULL; comma-separated codes are unique individually.
begin;
lock table public.equipment in share row exclusive mode;
alter table public.equipment alter column code drop not null;

create or replace function public.normalize_equipment_code(value text) returns text
language plpgsql immutable set search_path=public as $$
declare token text;codes text[]:=array[]::text[];
begin
 foreach token in array string_to_array(coalesce(value,''),',') loop
  token:=btrim(token,E' \t\n\r\f');
  if token='' then continue;end if;
  if length(token)>80 or cardinality(codes)>=50 then raise exception 'INVALID_MANAGEMENT_CODES' using errcode='23514';end if;
  if token=any(codes) then raise exception 'DUPLICATE_MANAGEMENT_CODE' using errcode='23505';end if;
  codes:=array_append(codes,token);
 end loop;
 return nullif(array_to_string(codes,', '),'');
end $$;
revoke all on function public.normalize_equipment_code(text) from public,anon,authenticated;

-- A unique row per number prevents overlaps such as 'CAM-001, CAM-002' and 'CAM-002'.
create table if not exists public.equipment_management_codes (
 code text primary key,equipment_id uuid not null references public.equipment(id) on delete cascade
);
create index if not exists equipment_management_codes_equipment on public.equipment_management_codes(equipment_id);
alter table public.equipment_management_codes enable row level security;
revoke all on public.equipment_management_codes from public,anon,authenticated;
update public.equipment set code=normalize_equipment_code(code) where code is distinct from normalize_equipment_code(code);
delete from public.equipment_management_codes;
insert into public.equipment_management_codes(code,equipment_id)
select btrim(token),e.id from public.equipment e cross join lateral unnest(string_to_array(e.code,', ')) token where e.code is not null;

create or replace function public.normalize_equipment_code_row() returns trigger
language plpgsql security definer set search_path=public as $$
begin new.code:=normalize_equipment_code(new.code);return new;end $$;
create or replace function public.sync_equipment_management_codes() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 delete from equipment_management_codes where equipment_id=new.id;
 if new.code is not null then
  insert into equipment_management_codes(code,equipment_id) select token,new.id from unnest(string_to_array(new.code,', ')) token;
 end if;
 return new;
end $$;
revoke all on function public.normalize_equipment_code_row() from public,anon,authenticated;
revoke all on function public.sync_equipment_management_codes() from public,anon,authenticated;
drop trigger if exists equipment_code_normalize on public.equipment;
create trigger equipment_code_normalize before insert or update of code on public.equipment for each row execute function public.normalize_equipment_code_row();
drop trigger if exists equipment_codes_sync on public.equipment;
create trigger equipment_codes_sync after insert or update of code on public.equipment for each row execute function public.sync_equipment_management_codes();

create or replace function public.admin_save_equipment_with_accessories(p_equipment jsonb,p_accessories jsonb,p_id uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_code text;v_id uuid; link jsonb; child uuid;seen uuid[]:=array[]::uuid[];
begin
 if not public.is_admin() then raise exception 'FORBIDDEN' using errcode='42501';end if;
 if jsonb_typeof(p_equipment) is distinct from 'object' or
 length(trim(coalesce(p_equipment->>'name','')))=0 or length(p_equipment->>'name')>150 or
 jsonb_typeof(p_equipment->'quantity') is distinct from 'number' or (p_equipment->>'quantity') !~ '^[0-9]+$' or
 jsonb_typeof(p_equipment->'repair_quantity') is distinct from 'number' or (p_equipment->>'repair_quantity') !~ '^[0-9]+$' or
 (p_equipment->>'quantity')::numeric>10000 or (p_equipment->>'repair_quantity')::numeric>(p_equipment->>'quantity')::numeric or
 jsonb_typeof(p_equipment->'active') is distinct from 'boolean' or
 jsonb_typeof(p_accessories) is distinct from 'array' then raise exception 'INVALID_REQUEST';end if;
 v_code:=normalize_equipment_code(p_equipment->>'code');
 if jsonb_array_length(p_accessories)>50 then raise exception 'INVALID_ACCESSORIES';end if;
 if p_id is null then
  insert into equipment(code,name,model,group_id,image_path,description,quantity,repair_quantity,active)
  values(v_code,trim(p_equipment->>'name'),p_equipment->>'model',nullif(p_equipment->>'group_id','')::uuid,
   p_equipment->>'image_path',p_equipment->>'description',(p_equipment->>'quantity')::integer,(p_equipment->>'repair_quantity')::integer,(p_equipment->>'active')::boolean)
  returning id into v_id;
 else
  update equipment set code=v_code,name=trim(p_equipment->>'name'),model=p_equipment->>'model',
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
