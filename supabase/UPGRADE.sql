begin;
-- Existing installs: run this additive migration once. No Edge Function redeploy needed.
drop policy if exists groups_admin on public.groups;
create policy groups_admin on public.groups for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Public equipment images contain no borrower information. Only admins can upload/change.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('equipment-images','equipment-images',true,1000000,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=1000000,
 allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists equipment_image_insert on storage.objects;
create policy equipment_image_insert on storage.objects for insert to authenticated
with check(bucket_id='equipment-images' and public.is_admin());
drop policy if exists equipment_image_update on storage.objects;
create policy equipment_image_update on storage.objects for update to authenticated
using(bucket_id='equipment-images' and public.is_admin())
with check(bucket_id='equipment-images' and public.is_admin());
drop policy if exists equipment_image_delete on storage.objects;
create policy equipment_image_delete on storage.objects for delete to authenticated
using(bucket_id='equipment-images' and public.is_admin());
-- Apply after 001, 002, 003. Additive data migration; preserve all existing records.
alter table public.loans add column if not exists borrower_department text not null default '';
alter table public.loans add column if not exists borrower_position text not null default '';
alter table public.loans add column if not exists approver_snapshot jsonb not null default '[]';
alter table public.loans add column if not exists application_note text;
update public.loans set application_note=notes where application_note is null;
alter table public.audit_log add column if not exists metadata jsonb;
create table if not exists public.return_events (
 id uuid primary key default gen_random_uuid(),loan_id uuid not null references public.loans,
 quantities jsonb not null,notes text,photo_paths jsonb not null default '[]',
 created_at timestamptz not null default now(),reversed_at timestamptz
);
alter table public.return_events enable row level security;
drop policy if exists return_events_admin on public.return_events;
create policy return_events_admin on public.return_events for select to authenticated using(public.is_admin());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('return-images','return-images',false,1000000,array['image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=1000000,allowed_mime_types=array['image/jpeg'];

create or replace function public.available_quantity(p_id uuid,p_start date,p_end date,p_exclude uuid default null)
returns integer language sql stable security definer set search_path=public as $$
 select greatest(0,e.quantity-e.repair_quantity-coalesce((select max(used) from (
 select day,coalesce(sum(li.quantity-li.returned_quantity),0)::integer as used
 from generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') day
 left join loans l on l.cancelled_at is null and (p_exclude is null or l.id<>p_exclude)
 and ((l.start_date<=day::date and l.end_date>=day::date) or (l.checked_out_at is not null and l.end_date<(now() at time zone 'Asia/Seoul')::date))
 left join loan_items li on li.loan_id=l.id and li.equipment_id=p_id
 group by day) daily),0))::integer from equipment e where e.id=p_id;
$$;
revoke all on function public.available_quantity(uuid,date,date,uuid) from public,anon,authenticated;
grant execute on function public.available_quantity(uuid,date,date,uuid) to service_role;
create or replace function public.create_loan(p_name text,p_phone text,p_reason text,p_start date,p_end date,p_notes text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_num text; v_seq integer; v_month text; v_day date; v_due date; v_entry record; v_available integer; v_equipment equipment;
begin
 if length(trim(p_name))=0 or p_phone !~ '^[0-9]{9,15}$' or length(trim(p_reason))=0 or p_end<p_start or jsonb_typeof(p_items)<>'object' or p_items='{}'::jsonb then raise exception 'INVALID_REQUEST'; end if;
 -- Stable lock order prevents deadlocks; inventory check and insert are atomic.
 perform 1 from equipment where id in(select key::uuid from jsonb_each(p_items)) order by id for update;
 for v_entry in select key::uuid as id, value::text::integer as qty from jsonb_each(p_items) loop
 select * into v_equipment from equipment where id=v_entry.id and active;
 if not found or v_entry.qty<=0 then raise exception 'INVALID_EQUIPMENT'; end if;
 v_available:=available_quantity(v_entry.id,p_start,p_end);
 if v_entry.qty>v_available then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 v_day:=(now() at time zone 'Asia/Seoul')::date;
 v_month:=to_char(v_day,'YYYY-MM');
 insert into monthly_sequences values(v_month,1) on conflict(month) do update set value=monthly_sequences.value+1 returning value into v_seq;
 v_num:='반출-'||v_month||'-'||lpad(v_seq::text,greatest(3,length(v_seq::text)),'0');
 v_due:=v_day+(7-extract(dow from v_day)::integer)+7;
 insert into loans(number,borrower_name,borrower_phone,reason,notes,start_date,end_date,approval_due)
 values(v_num,trim(p_name),p_phone,p_reason,p_notes,p_start,p_end,v_due) returning id into v_id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select v_id,e.id,j.value::text::integer,jsonb_build_object('name',e.name,'code',e.code,'model',e.model)
 from jsonb_each(p_items) j join equipment e on e.id=j.key::uuid;
 insert into audit_log(loan_id,action) values(v_id,'created');
 return jsonb_build_object('id',v_id,'number',v_num);
end $$;
revoke all on function public.create_loan(text,text,text,date,date,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_loan(text,text,text,date,date,text,jsonb) to service_role;
create or replace function public.loan_json(p_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',l.number,'databaseId',l.id,'name',coalesce(l.borrower_name,'익명'),'phone',coalesce(l.borrower_phone,''),
 'department',l.borrower_department,'position',l.borrower_position,'createdAt',l.created_at,'approvalDue',l.approval_due,'approvedAt',l.approved_at,'checkoutAt',l.checked_out_at,'cancelled',l.cancelled_at is not null,'approvers',l.approver_snapshot,'snapshots',coalesce((select jsonb_object_agg(equipment_id::text,equipment_snapshot) from loan_items where loan_id=l.id),'{}'),'returnNotes',coalesce((select jsonb_agg(jsonb_build_object('notes',notes,'createdAt',created_at,'reversed',reversed_at is not null) order by created_at) from return_events where loan_id=l.id),'[]'),'reason',l.reason,'start',l.start_date,'end',l.end_date,'note',coalesce(l.application_note,l.notes,''),'approved',l.approved_at is not null,
 'out',l.checked_out_at is not null,'revision',l.revision,
 'items',coalesce((select jsonb_object_agg(equipment_id::text,quantity) from loan_items where loan_id=l.id),'{}'),
 'returned',coalesce((select jsonb_object_agg(equipment_id::text,returned_quantity) from loan_items where loan_id=l.id),'{}'))
 from loans l where l.id=p_id ;
$$;
revoke all on function public.loan_json(uuid) from public,anon,authenticated;

create or replace function public.equipment_workflow(p_action text,p_args jsonb,p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l loans; e equipment; entry record; created jsonb; available integer; result jsonb; v_start date; v_end date; v_qty integer; v_revision integer;
begin
 if p_action in ('admin_list','approve','checkout','undo_return','stock') and not exists(select 1 from admins where user_id=p_actor) then raise exception 'FORBIDDEN'; end if;
 if p_action='catalog' then
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end is null or v_end<v_start then raise exception 'INVALID_REQUEST'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',eq.id,'code',eq.code,'name',eq.name,'model',coalesce(eq.model,''),
 'group',coalesce(g.name,'기타'),'description',coalesce(eq.description,''),'repair',eq.repair_quantity,'active',eq.active,
 'qty',eq.quantity,'image',eq.image_path,'available',available_quantity(eq.id,v_start,v_end)) order by eq.code),'[]') into result
 from equipment eq left join groups g on g.id=eq.group_id where eq.active;
 return result;
 elsif p_action='admin_list' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans);
 elsif p_action='lookup' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans where borrower_name=trim(p_args->>'name') and borrower_phone=p_args->>'phone' and cancelled_at is null and anonymized_at is null);
 elsif p_action='create' then
 if length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 then raise exception 'INVALID_REQUEST'; end if;
 created:=create_loan(p_args->>'name',p_args->>'phone',p_args->>'reason',(p_args->>'start')::date,(p_args->>'end')::date,p_args->>'note',p_args->'items');
 update loans set borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=p_args->>'note',
 approver_snapshot=coalesce((select jsonb_agg(to_jsonb(a)) from (select id,name,department,position,active from approvers where active order by id limit 4) a),'[]')
 where id=(created->>'id')::uuid;
 update loan_items li set equipment_snapshot=li.equipment_snapshot||jsonb_build_object('department',coalesce(g.name,'기타')) from equipment eq left join groups g on g.id=eq.group_id where li.loan_id=(created->>'id')::uuid and eq.id=li.equipment_id;
 return loan_json((created->>'id')::uuid);
 elsif p_action='stock' then
 v_qty:=(p_args->>'quantity')::integer;
 if v_qty<0 then raise exception 'INVALID_REQUEST'; end if;
 update equipment set quantity=v_qty where id=(p_args->>'equipmentId')::uuid;
 insert into audit_log(actor,action,reason) values(p_actor,'stock',p_args->>'reason');
 return '{}'::jsonb;
 end if;
 -- Lock inventory first, then loan, in stable order for every workflow.
 select * into l from loans where number=p_args->>'id' and cancelled_at is null;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from equipment where id in(select equipment_id from loan_items where loan_id=l.id union select key::uuid from jsonb_each(coalesce(p_args->'items','{}'))) order by id for update;
 select * into l from loans where id=l.id for update;
 if l.cancelled_at is not null then raise exception 'CONFLICT'; end if;
 if p_actor is null and (l.anonymized_at is not null or l.borrower_name<>trim(coalesce(p_args->>'identityName',p_args->>'name')) or l.borrower_phone<>coalesce(p_args->>'identityPhone',p_args->>'phone') or p_args->>'name' is null or p_args->>'phone' is null) then raise exception 'NOT_FOUND'; end if;
 v_revision:=(p_args->>'revision')::integer;
 if v_revision is null or v_revision<>l.revision then raise exception 'CONFLICT'; end if;
 if p_action='approve' then
 update loans set approved_at=now(),approved_by=p_actor,revision=revision+1 where id=l.id;
 elsif p_action='cancel' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 update loans set cancelled_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='update' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end<v_start or length(trim(p_args->>'reason'))=0 or length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_REQUEST'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 select * into e from equipment where id=entry.id and active;
 if not found or entry.qty<=0 then raise exception 'INVALID_REQUEST'; end if;
 available:=available_quantity(e.id,v_start,v_end,l.id);
 if available<entry.qty then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 create temporary table if not exists prior_item_snapshots(equipment_id uuid,equipment_snapshot jsonb) on commit drop;
 truncate prior_item_snapshots;
 insert into prior_item_snapshots select equipment_id,equipment_snapshot from loan_items where loan_id=l.id;
 delete from loan_items where loan_id=l.id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select l.id,eq.id,j.value::text::integer,coalesce((select equipment_snapshot from prior_item_snapshots where equipment_id=eq.id),jsonb_build_object('name',eq.name,'code',eq.code,'model',eq.model,'department',(select name from groups where id=eq.group_id))) from jsonb_each(p_args->'items') j join equipment eq on eq.id=j.key::uuid;
 update loans set borrower_name=trim(p_args->>'name'),borrower_phone=p_args->>'phone',borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=p_args->>'note',reason=p_args->>'reason',notes=p_args->>'note',start_date=v_start,end_date=v_end,approved_at=null,approved_by=null,revision=revision+1 where id=l.id;
 elsif p_action='checkout' then
 if l.checked_out_at is not null then raise exception 'CONFLICT'; end if;
 for entry in select * from loan_items where loan_id=l.id loop
 select * into e from equipment where id=entry.equipment_id;
 select e.quantity-e.repair_quantity-coalesce(sum(li.quantity-li.returned_quantity),0)::integer into available from loan_items li join loans x on x.id=li.loan_id where li.equipment_id=e.id and x.id<>l.id and x.cancelled_at is null and x.checked_out_at is not null;
 if available<entry.quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 update loans set checked_out_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='return' then
 if l.checked_out_at is null or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_RETURN'; end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_args->'photoPaths','[]')) p where p not like l.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='return-images' and name=p)) then raise exception 'INVALID_RETURN'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 update loan_items set returned_quantity=returned_quantity+entry.qty where loan_id=l.id and equipment_id=entry.id and entry.qty>0 and returned_quantity+entry.qty<=quantity;
 if not found then raise exception 'INVALID_RETURN'; end if;
 end loop;
 update loans set notes=concat_ws(E'\n',notes,nullif('반납: '||left(coalesce(p_args->>'note',''),2000),'반납: ')),revision=revision+1 where id=l.id;
 insert into return_events(loan_id,quantities,notes,photo_paths) values(l.id,p_args->'items',left(p_args->>'note',2000),coalesce(p_args->'photoPaths','[]'));
 elsif p_action='undo_return' then
 if length(trim(coalesce(p_args->>'reason','')))=0 then raise exception 'INVALID_REQUEST'; end if;
 update return_events set reversed_at=now() where loan_id=l.id and reversed_at is null;
 update loan_items set returned_quantity=0 where loan_id=l.id;
 update loans set revision=revision+1 where id=l.id;
 else raise exception 'INVALID_REQUEST'; end if;
 insert into audit_log(loan_id,actor,action,reason) values(l.id,p_actor,p_action,left(p_args->>'reason',500));
 return coalesce(loan_json(l.id),'{}');
end $$;
revoke all on function public.equipment_workflow(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.equipment_workflow(text,jsonb,uuid) to service_role;

-- Record administrator catalog changes without copying borrower data into logs.
create or replace function public.audit_equipment_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into audit_log(actor,action,reason,metadata) values(auth.uid(),'equipment_'||lower(TG_OP),'관리자 장비 변경',jsonb_build_object('equipmentId',new.id,'before',case when TG_OP='UPDATE' then jsonb_build_object('quantity',old.quantity,'repair',old.repair_quantity,'active',old.active) else null end,'after',jsonb_build_object('quantity',new.quantity,'repair',new.repair_quantity,'active',new.active)));
 return new;
end $$;
drop trigger if exists equipment_audit on public.equipment;
create trigger equipment_audit after insert or update on public.equipment for each row execute function public.audit_equipment_change();
-- Keep loan history even if an administrator uses the REST API directly.
drop policy if exists equipment_admin on public.equipment;
drop policy if exists equipment_admin_insert on public.equipment;
create policy equipment_admin_insert on public.equipment for insert to authenticated with check(public.is_admin());
drop policy if exists equipment_admin_update on public.equipment;
create policy equipment_admin_update on public.equipment for update to authenticated using(public.is_admin()) with check(public.is_admin());
create or replace function public.anonymize_expired_loans() returns void language plpgsql security definer set search_path=public as $$
begin
 update loans set borrower_name=null,borrower_phone=null,borrower_department='',borrower_position='',anonymized_at=now()
 where created_at<=now()-interval '1 year' and anonymized_at is null;
end $$;
revoke all on function public.anonymize_expired_loans() from public,anon,authenticated;
grant execute on function public.anonymize_expired_loans() to service_role;

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

-- Apply after 005. Existing applications, notes and photographs are retained.
alter table public.loans add column if not exists rejected_at timestamptz;
alter table public.loans add column if not exists rejected_by uuid references auth.users;
alter table public.loans add column if not exists rejection_reason text;
create or replace function public.available_quantity(p_id uuid,p_start date,p_end date,p_exclude uuid default null)
returns integer language sql stable security definer set search_path=public as $$
 select greatest(0,e.quantity-e.repair_quantity-coalesce((select max(used) from (
 select day,coalesce(sum(li.quantity-li.returned_quantity),0)::integer as used
 from generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') day
 left join loans l on l.cancelled_at is null and l.rejected_at is null and (p_exclude is null or l.id<>p_exclude)
 and ((l.start_date<=day::date and l.end_date>=day::date) or (l.checked_out_at is not null and l.end_date<(now() at time zone 'Asia/Seoul')::date))
 left join loan_items li on li.loan_id=l.id and li.equipment_id=p_id
 group by day) daily),0))::integer from equipment e where e.id=p_id;
$$;
revoke all on function public.available_quantity(uuid,date,date,uuid) from public,anon,authenticated;
grant execute on function public.available_quantity(uuid,date,date,uuid) to service_role;
create or replace function public.create_loan(p_name text,p_phone text,p_reason text,p_start date,p_end date,p_notes text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_num text; v_seq integer; v_month text; v_day date; v_due date; v_entry record; v_available integer; v_equipment equipment;
begin
 if length(trim(p_name))=0 or p_phone !~ '^010[0-9]{8}$' or length(trim(p_reason))=0 or p_end<p_start or jsonb_typeof(p_items)<>'object' or p_items='{}'::jsonb then raise exception 'INVALID_REQUEST'; end if;
 -- Stable lock order prevents deadlocks; inventory check and insert are atomic.
 perform 1 from equipment where id in(select key::uuid from jsonb_each(p_items)) order by id for update;
 for v_entry in select key::uuid as id, value::text::integer as qty from jsonb_each(p_items) loop
 select * into v_equipment from equipment where id=v_entry.id and active;
 if not found or v_entry.qty<=0 then raise exception 'INVALID_EQUIPMENT'; end if;
 v_available:=available_quantity(v_entry.id,p_start,p_end);
 if v_entry.qty>v_available then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 v_day:=(now() at time zone 'Asia/Seoul')::date;
 v_month:=to_char(v_day,'YYYY-MM');
 insert into monthly_sequences values(v_month,1) on conflict(month) do update set value=monthly_sequences.value+1 returning value into v_seq;
 v_num:='반출-'||v_month||'-'||lpad(v_seq::text,greatest(3,length(v_seq::text)),'0');
 v_due:=v_day+(7-extract(dow from v_day)::integer)+7;
 insert into loans(number,borrower_name,borrower_phone,reason,notes,start_date,end_date,approval_due)
 values(v_num,trim(p_name),p_phone,p_reason,p_notes,p_start,p_end,v_due) returning id into v_id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select v_id,e.id,j.value::text::integer,jsonb_build_object('name',e.name,'code',e.code,'model',e.model)
 from jsonb_each(p_items) j join equipment e on e.id=j.key::uuid;
 insert into audit_log(loan_id,action) values(v_id,'created');
 return jsonb_build_object('id',v_id,'number',v_num);
end $$;
revoke all on function public.create_loan(text,text,text,date,date,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_loan(text,text,text,date,date,text,jsonb) to service_role;
create or replace function public.loan_json(p_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',l.number,'databaseId',l.id,'name',coalesce(l.borrower_name,'익명'),'phone',coalesce(l.borrower_phone,''),
 'department',l.borrower_department,'position',l.borrower_position,'createdAt',l.created_at,'approvalDue',l.approval_due,'approvedAt',l.approved_at,'checkoutAt',l.checked_out_at,'cancelled',l.cancelled_at is not null,'rejected',l.rejected_at is not null,'rejectionReason',l.rejection_reason,'rejectedAt',l.rejected_at,'approvers',l.approver_snapshot,'snapshots',coalesce((select jsonb_object_agg(equipment_id::text,equipment_snapshot) from loan_items where loan_id=l.id),'{}'),'returnNotes',coalesce((select jsonb_agg(jsonb_build_object('notes',notes,'createdAt',created_at,'reversed',reversed_at is not null) order by created_at) from return_events where loan_id=l.id),'[]'),'reason',l.reason,'start',l.start_date,'end',l.end_date,'note',coalesce(l.application_note,l.notes,''),'approved',l.approved_at is not null,
 'out',l.checked_out_at is not null,'revision',l.revision,
 'items',coalesce((select jsonb_object_agg(equipment_id::text,quantity) from loan_items where loan_id=l.id),'{}'),
 'returned',coalesce((select jsonb_object_agg(equipment_id::text,returned_quantity) from loan_items where loan_id=l.id),'{}'))
 from loans l where l.id=p_id ;
$$;
revoke all on function public.loan_json(uuid) from public,anon,authenticated;

create or replace function public.equipment_workflow(p_action text,p_args jsonb,p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l loans; e equipment; entry record; created jsonb; available integer; result jsonb; v_start date; v_end date; v_qty integer; v_revision integer;
begin
 if p_action in ('admin_list','approve','reject','checkout','undo_return','stock') and not exists(select 1 from admins where user_id=p_actor) then raise exception 'FORBIDDEN'; end if;
 if p_action in ('create','update') and coalesce(p_args->>'phone','') !~ '^010[0-9]{8}$' then raise exception 'INVALID_PHONE'; end if;
 if p_action='catalog' then
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end is null or v_end<v_start then raise exception 'INVALID_REQUEST'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',eq.id,'code',eq.code,'name',eq.name,'model',coalesce(eq.model,''),
 'group',coalesce(g.name,'기타'),'description',coalesce(eq.description,''),'repair',eq.repair_quantity,'active',eq.active,
 'qty',eq.quantity,'image',eq.image_path,'available',available_quantity(eq.id,v_start,v_end)) order by eq.code),'[]') into result
 from equipment eq left join groups g on g.id=eq.group_id where eq.active;
 return result;
 elsif p_action='admin_list' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans);
 elsif p_action='lookup' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans where borrower_name=trim(p_args->>'name') and borrower_phone=p_args->>'phone' and cancelled_at is null and anonymized_at is null);
 elsif p_action='create' then
 p_args:=jsonb_set(p_args,'{note}','""');
 if length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 then raise exception 'INVALID_REQUEST'; end if;
 created:=create_loan(p_args->>'name',p_args->>'phone',p_args->>'reason',(p_args->>'start')::date,(p_args->>'end')::date,p_args->>'note',p_args->'items');
 update loans set borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=p_args->>'note',
 approver_snapshot=coalesce((select jsonb_agg(to_jsonb(a)) from (select id,name,department,position,active from approvers where active order by id limit 4) a),'[]')
 where id=(created->>'id')::uuid;
 update loan_items li set equipment_snapshot=li.equipment_snapshot||jsonb_build_object('department',coalesce(g.name,'기타')) from equipment eq left join groups g on g.id=eq.group_id where li.loan_id=(created->>'id')::uuid and eq.id=li.equipment_id;
 return loan_json((created->>'id')::uuid);
 elsif p_action='stock' then
 v_qty:=(p_args->>'quantity')::integer;
 if v_qty<0 then raise exception 'INVALID_REQUEST'; end if;
 update equipment set quantity=v_qty where id=(p_args->>'equipmentId')::uuid;
 insert into audit_log(actor,action,reason) values(p_actor,'stock',p_args->>'reason');
 return '{}'::jsonb;
 end if;
 -- Lock inventory first, then loan, in stable order for every workflow.
 select * into l from loans where number=p_args->>'id' and cancelled_at is null;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from equipment where id in(select equipment_id from loan_items where loan_id=l.id union select key::uuid from jsonb_each(coalesce(p_args->'items','{}'))) order by id for update;
 select * into l from loans where id=l.id for update;
 if l.cancelled_at is not null then raise exception 'CONFLICT'; end if;
 if p_actor is null and (l.anonymized_at is not null or l.borrower_name<>trim(coalesce(p_args->>'identityName',p_args->>'name')) or l.borrower_phone<>coalesce(p_args->>'identityPhone',p_args->>'phone') or p_args->>'name' is null or p_args->>'phone' is null) then raise exception 'NOT_FOUND'; end if;
 v_revision:=(p_args->>'revision')::integer;
 if v_revision is null or v_revision<>l.revision then raise exception 'CONFLICT'; end if;
 if p_action='approve' then
 if l.rejected_at is not null or l.approved_at is not null then raise exception 'CONFLICT'; end if;
 if l.checked_out_at is null then
  for entry in select * from loan_items where loan_id=l.id loop
   if available_quantity(entry.equipment_id,l.start_date,l.end_date,l.id)<entry.quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
  end loop;
 end if;
 update loans set approved_at=now(),approved_by=p_actor,checked_out_at=coalesce(checked_out_at,now()),revision=revision+1 where id=l.id;
 elsif p_action='reject' then
 if l.checked_out_at is not null or l.rejected_at is not null then raise exception 'CONFLICT'; end if;
 if length(trim(coalesce(p_args->>'reason','')))=0 or length(p_args->>'reason')>500 then raise exception 'INVALID_REQUEST'; end if;
 update loans set rejected_at=now(),rejected_by=p_actor,rejection_reason=trim(p_args->>'reason'),approved_at=null,approved_by=null,revision=revision+1 where id=l.id;
 elsif p_action='cancel' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 update loans set cancelled_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='update' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end<v_start or length(trim(p_args->>'reason'))=0 or length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_REQUEST'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 select * into e from equipment where id=entry.id and active;
 if not found or entry.qty<=0 then raise exception 'INVALID_REQUEST'; end if;
 available:=available_quantity(e.id,v_start,v_end,l.id);
 if available<entry.qty then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 create temporary table if not exists prior_item_snapshots(equipment_id uuid,equipment_snapshot jsonb) on commit drop;
 truncate prior_item_snapshots;
 insert into prior_item_snapshots select equipment_id,equipment_snapshot from loan_items where loan_id=l.id;
 delete from loan_items where loan_id=l.id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select l.id,eq.id,j.value::text::integer,coalesce((select equipment_snapshot from prior_item_snapshots where equipment_id=eq.id),jsonb_build_object('name',eq.name,'code',eq.code,'model',eq.model,'department',(select name from groups where id=eq.group_id))) from jsonb_each(p_args->'items') j join equipment eq on eq.id=j.key::uuid;
 update loans set borrower_name=trim(p_args->>'name'),borrower_phone=p_args->>'phone',borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=l.application_note,reason=p_args->>'reason',notes=l.notes,start_date=v_start,end_date=v_end,approved_at=null,approved_by=null,rejected_at=null,rejected_by=null,rejection_reason=null,revision=revision+1 where id=l.id;
 elsif p_action='checkout' then
 if l.checked_out_at is not null or l.rejected_at is not null then raise exception 'CONFLICT'; end if;
 for entry in select * from loan_items where loan_id=l.id loop
 select * into e from equipment where id=entry.equipment_id;
 select e.quantity-e.repair_quantity-coalesce(sum(li.quantity-li.returned_quantity),0)::integer into available from loan_items li join loans x on x.id=li.loan_id where li.equipment_id=e.id and x.id<>l.id and x.cancelled_at is null and x.checked_out_at is not null;
 if available<entry.quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 update loans set checked_out_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='return' then
 if l.rejected_at is not null or l.checked_out_at is null or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_RETURN'; end if;
 if coalesce(p_args->'photoPaths','[]')<>'[]'::jsonb then raise exception 'INVALID_RETURN'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 update loan_items set returned_quantity=returned_quantity+entry.qty where loan_id=l.id and equipment_id=entry.id and entry.qty>0 and returned_quantity+entry.qty<=quantity;
 if not found then raise exception 'INVALID_RETURN'; end if;
 end loop;
 update loans set notes=concat_ws(E'\n',notes,nullif('반납: '||left(coalesce(p_args->>'note',''),2000),'반납: ')),revision=revision+1 where id=l.id;
 insert into return_events(loan_id,quantities,notes,photo_paths) values(l.id,p_args->'items',left(p_args->>'note',2000),'[]'::jsonb);
 elsif p_action='undo_return' then
 if length(trim(coalesce(p_args->>'reason','')))=0 then raise exception 'INVALID_REQUEST'; end if;
 update return_events set reversed_at=now() where loan_id=l.id and reversed_at is null;
 update loan_items set returned_quantity=0 where loan_id=l.id;
 update loans set revision=revision+1 where id=l.id;
 else raise exception 'INVALID_REQUEST'; end if;
 insert into audit_log(loan_id,actor,action,reason) values(l.id,p_actor,p_action,left(p_args->>'reason',500));
 return coalesce(loan_json(l.id),'{}');
end $$;
revoke all on function public.equipment_workflow(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.equipment_workflow(text,jsonb,uuid) to service_role;


-- Existing approvals follow the new single-action workflow too. Revisions invalidate stale forms.
with changed as (
 update public.loans set checked_out_at=approved_at,revision=revision+1
 where approved_at is not null and checked_out_at is null and cancelled_at is null and rejected_at is null
 returning id
)
insert into public.audit_log(loan_id,action,reason)
select id,'approval_checkout_migration','승인·반출 통합 적용' from changed;

-- Rejected applications are final. Borrowers may submit a new application.
create or replace function public.equipment_workflow(p_action text,p_args jsonb,p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l loans; e equipment; entry record; created jsonb; available integer; result jsonb; v_start date; v_end date; v_qty integer; v_revision integer;
begin
 if p_action in ('admin_list','approve','reject','checkout','undo_return','stock') and not exists(select 1 from admins where user_id=p_actor) then raise exception 'FORBIDDEN'; end if;
 if p_action in ('create','update') and coalesce(p_args->>'phone','') !~ '^010[0-9]{8}$' then raise exception 'INVALID_PHONE'; end if;
 if p_action='catalog' then
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end is null or v_end<v_start then raise exception 'INVALID_REQUEST'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',eq.id,'code',eq.code,'name',eq.name,'model',coalesce(eq.model,''),
 'group',coalesce(g.name,'기타'),'description',coalesce(eq.description,''),'repair',eq.repair_quantity,'active',eq.active,
 'qty',eq.quantity,'image',eq.image_path,'available',available_quantity(eq.id,v_start,v_end)) order by eq.code),'[]') into result
 from equipment eq left join groups g on g.id=eq.group_id where eq.active;
 return result;
 elsif p_action='admin_list' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans);
 elsif p_action='lookup' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans where borrower_name=trim(p_args->>'name') and borrower_phone=p_args->>'phone' and cancelled_at is null and anonymized_at is null);
 elsif p_action='create' then
 p_args:=jsonb_set(p_args,'{note}','""');
 if length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 then raise exception 'INVALID_REQUEST'; end if;
 created:=create_loan(p_args->>'name',p_args->>'phone',p_args->>'reason',(p_args->>'start')::date,(p_args->>'end')::date,p_args->>'note',p_args->'items');
 update loans set borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=p_args->>'note',
 approver_snapshot=coalesce((select jsonb_agg(to_jsonb(a)) from (select id,name,department,position,active from approvers where active order by id limit 4) a),'[]')
 where id=(created->>'id')::uuid;
 update loan_items li set equipment_snapshot=li.equipment_snapshot||jsonb_build_object('department',coalesce(g.name,'기타')) from equipment eq left join groups g on g.id=eq.group_id where li.loan_id=(created->>'id')::uuid and eq.id=li.equipment_id;
 return loan_json((created->>'id')::uuid);
 elsif p_action='stock' then
 v_qty:=(p_args->>'quantity')::integer;
 if v_qty<0 then raise exception 'INVALID_REQUEST'; end if;
 update equipment set quantity=v_qty where id=(p_args->>'equipmentId')::uuid;
 insert into audit_log(actor,action,reason) values(p_actor,'stock',p_args->>'reason');
 return '{}'::jsonb;
 end if;
 -- Lock inventory first, then loan, in stable order for every workflow.
 select * into l from loans where number=p_args->>'id' and cancelled_at is null;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from equipment where id in(select equipment_id from loan_items where loan_id=l.id union select key::uuid from jsonb_each(coalesce(p_args->'items','{}'))) order by id for update;
 select * into l from loans where id=l.id for update;
 if l.cancelled_at is not null then raise exception 'CONFLICT'; end if;
 if p_actor is null and (l.anonymized_at is not null or l.borrower_name<>trim(coalesce(p_args->>'identityName',p_args->>'name')) or l.borrower_phone<>coalesce(p_args->>'identityPhone',p_args->>'phone') or p_args->>'name' is null or p_args->>'phone' is null) then raise exception 'NOT_FOUND'; end if;
 v_revision:=(p_args->>'revision')::integer;
 if v_revision is null or v_revision<>l.revision then raise exception 'CONFLICT'; end if;
 if l.rejected_at is not null and p_action in ('update','cancel') then raise exception 'REJECTED_APPLICATION'; end if;
 if p_action='approve' then
 if l.rejected_at is not null or l.approved_at is not null then raise exception 'CONFLICT'; end if;
 if l.checked_out_at is null then
  for entry in select * from loan_items where loan_id=l.id loop
   if available_quantity(entry.equipment_id,l.start_date,l.end_date,l.id)<entry.quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
  end loop;
 end if;
 update loans set approved_at=now(),approved_by=p_actor,checked_out_at=coalesce(checked_out_at,now()),revision=revision+1 where id=l.id;
 elsif p_action='reject' then
 if l.checked_out_at is not null or l.rejected_at is not null then raise exception 'CONFLICT'; end if;
 if length(trim(coalesce(p_args->>'reason','')))=0 or length(p_args->>'reason')>500 then raise exception 'INVALID_REQUEST'; end if;
 update loans set rejected_at=now(),rejected_by=p_actor,rejection_reason=trim(p_args->>'reason'),approved_at=null,approved_by=null,revision=revision+1 where id=l.id;
 elsif p_action='cancel' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 update loans set cancelled_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='update' then
 if l.checked_out_at is not null then raise exception 'ALREADY_CHECKED_OUT'; end if;
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end<v_start or length(trim(p_args->>'reason'))=0 or length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_REQUEST'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 select * into e from equipment where id=entry.id and active;
 if not found or entry.qty<=0 then raise exception 'INVALID_REQUEST'; end if;
 available:=available_quantity(e.id,v_start,v_end,l.id);
 if available<entry.qty then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 create temporary table if not exists prior_item_snapshots(equipment_id uuid,equipment_snapshot jsonb) on commit drop;
 truncate prior_item_snapshots;
 insert into prior_item_snapshots select equipment_id,equipment_snapshot from loan_items where loan_id=l.id;
 delete from loan_items where loan_id=l.id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select l.id,eq.id,j.value::text::integer,coalesce((select equipment_snapshot from prior_item_snapshots where equipment_id=eq.id),jsonb_build_object('name',eq.name,'code',eq.code,'model',eq.model,'department',(select name from groups where id=eq.group_id))) from jsonb_each(p_args->'items') j join equipment eq on eq.id=j.key::uuid;
 update loans set borrower_name=trim(p_args->>'name'),borrower_phone=p_args->>'phone',borrower_department=left(coalesce(p_args->>'department',''),80),borrower_position=left(coalesce(p_args->>'position',''),80),application_note=l.application_note,reason=p_args->>'reason',notes=l.notes,start_date=v_start,end_date=v_end,approved_at=null,approved_by=null,rejected_at=null,rejected_by=null,rejection_reason=null,revision=revision+1 where id=l.id;
 elsif p_action='checkout' then
 if l.checked_out_at is not null or l.rejected_at is not null then raise exception 'CONFLICT'; end if;
 for entry in select * from loan_items where loan_id=l.id loop
 select * into e from equipment where id=entry.equipment_id;
 select e.quantity-e.repair_quantity-coalesce(sum(li.quantity-li.returned_quantity),0)::integer into available from loan_items li join loans x on x.id=li.loan_id where li.equipment_id=e.id and x.id<>l.id and x.cancelled_at is null and x.checked_out_at is not null;
 if available<entry.quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 update loans set checked_out_at=now(),revision=revision+1 where id=l.id;
 elsif p_action='return' then
 if l.rejected_at is not null or l.checked_out_at is null or jsonb_typeof(p_args->'items')<>'object' or p_args->'items'='{}' then raise exception 'INVALID_RETURN'; end if;
 if coalesce(p_args->'photoPaths','[]')<>'[]'::jsonb then raise exception 'INVALID_RETURN'; end if;
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 update loan_items set returned_quantity=returned_quantity+entry.qty where loan_id=l.id and equipment_id=entry.id and entry.qty>0 and returned_quantity+entry.qty<=quantity;
 if not found then raise exception 'INVALID_RETURN'; end if;
 end loop;
 update loans set notes=concat_ws(E'\n',notes,nullif('반납: '||left(coalesce(p_args->>'note',''),2000),'반납: ')),revision=revision+1 where id=l.id;
 insert into return_events(loan_id,quantities,notes,photo_paths) values(l.id,p_args->'items',left(p_args->>'note',2000),'[]'::jsonb);
 elsif p_action='undo_return' then
 if length(trim(coalesce(p_args->>'reason','')))=0 then raise exception 'INVALID_REQUEST'; end if;
 update return_events set reversed_at=now() where loan_id=l.id and reversed_at is null;
 update loan_items set returned_quantity=0 where loan_id=l.id;
 update loans set revision=revision+1 where id=l.id;
 else raise exception 'INVALID_REQUEST'; end if;
 insert into audit_log(loan_id,actor,action,reason) values(l.id,p_actor,p_action,left(p_args->>'reason',500));
 return coalesce(loan_json(l.id),'{}');
end $$;
revoke all on function public.equipment_workflow(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.equipment_workflow(text,jsonb,uuid) to service_role;



-- Apply after 007. Templates are immutable; each application retains its snapshot.
create table if not exists public.pdf_templates (
 version bigint generated always as identity primary key,settings jsonb not null,
 created_at timestamptz not null default now(),created_by uuid references auth.users
);
create table if not exists public.pdf_template_current (
 id boolean primary key default true check(id),version bigint not null references public.pdf_templates
);
alter table public.loans add column if not exists pdf_template jsonb;
alter table public.pdf_templates enable row level security;
alter table public.pdf_template_current enable row level security;
drop policy if exists pdf_templates_admin_read on public.pdf_templates;
create policy pdf_templates_admin_read on public.pdf_templates for select to authenticated using(public.is_admin());
drop policy if exists pdf_template_current_admin_read on public.pdf_template_current;
create policy pdf_template_current_admin_read on public.pdf_template_current for select to authenticated using(public.is_admin());
insert into public.pdf_templates(settings)
select $template${"version":1,"title":"장비 사용 신청서","organization":"서울영동교회","department":"미디어사역부","showLogo":true,"logoUrl":null,"notices":["미디어장비를 반출할 경우, 반출 전 반드시 <미디어 사역부> 담당자 통해 장비점검 받아주세요.","미디어 사역부 담당자, 사무실 담당자의 확인을 받아야 반출할 수 있습니다.","방송 장비외의 악기류 및 시설장비는 <미디어 사역부> 대여 대상이 아닙니다.","사용 후 반드시 장비점검 확인 후 반납해주세요. 추후 장비 문제가 있을 경우 책임을 물을 수 있습니다.","본 반출증은 1부 작성 후 복사하여 1부는 발행부서, 1부는 관리부에서 보관합니다."],"noticeHeading":"사용 및 반납 확인","signatureHeading":"신청 및 승인","approverLabels":["장비 승인자","사무실 확인","추가 승인자","추가 승인자"],"borrowerLabel":"신청자","showSignatureDepartment":true,"showSignaturePosition":true,"fontSize":9,"margin":48,"rowHeight":31,"columns":[{"key":"number","label":"No.","visible":true},{"key":"code","label":"관리번호","visible":true},{"key":"name","label":"장비명","visible":true},{"key":"quantity","label":"수량","visible":true},{"key":"department","label":"장비 소속","visible":true},{"key":"check","label":"확인","visible":true}]}$template$::jsonb-'version' where not exists(select 1 from public.pdf_templates);
insert into public.pdf_template_current(id,version)
select true,min(version) from public.pdf_templates on conflict(id) do nothing;

create or replace function public.current_pdf_template() returns jsonb language sql stable security definer set search_path=public as $$
 select t.settings||jsonb_build_object('version',t.version) from pdf_templates t join pdf_template_current c on c.version=t.version where c.id;
$$;
revoke all on function public.current_pdf_template() from public;
grant execute on function public.current_pdf_template() to anon,authenticated,service_role;

create or replace function public.validate_pdf_template(s jsonb) returns boolean language plpgsql immutable set search_path=public as $$
declare k text;c jsonb;keys text[];value text;
begin
 if jsonb_typeof(s) is distinct from 'object' or octet_length(s::text)>80000 then return false;end if;
 foreach k in array array['title','organization','department','noticeHeading','signatureHeading','borrowerLabel'] loop
  if jsonb_typeof(s->k) is distinct from 'string' or length(trim(s->>k))=0 or length(s->>k)>80 then return false;end if;
 end loop;
 foreach k in array array['title','organization','department'] loop
  if length(s->>k)>30 then return false;end if;
 end loop;
 foreach k in array array['showLogo','showSignatureDepartment','showSignaturePosition'] loop
  if jsonb_typeof(s->k) is distinct from 'boolean' then return false;end if;
 end loop;
 if jsonb_typeof(s->'fontSize') is distinct from 'number' or (s->>'fontSize')::numeric not between 8 and 11 or jsonb_typeof(s->'margin') is distinct from 'number' or (s->>'margin')::numeric not between 36 and 60 or jsonb_typeof(s->'rowHeight') is distinct from 'number' or (s->>'rowHeight')::numeric not between 26 and 44 then return false;end if;
 if s->'logoUrl' is null then return false;end if;
 if s->'logoUrl'<>'null'::jsonb and (jsonb_typeof(s->'logoUrl')<>'string' or s->>'logoUrl' not like 'https://%' or length(s->>'logoUrl')>2048) then return false;end if;
 if jsonb_typeof(s->'notices') is distinct from 'array' or jsonb_array_length(s->'notices')>20 then return false;end if;
 if exists(select 1 from jsonb_array_elements(s->'notices') v where jsonb_typeof(v)<>'string' or length(v#>>'{}')>1000) or (select coalesce(sum(length(v#>>'{}')),0) from jsonb_array_elements(s->'notices') v)>5000 then return false;end if;
 if jsonb_typeof(s->'approverLabels') is distinct from 'array' or jsonb_array_length(s->'approverLabels')<>4 then return false;end if;
 if exists(select 1 from jsonb_array_elements(s->'approverLabels') v where jsonb_typeof(v)<>'string' or length(trim(v#>>'{}'))=0 or length(v#>>'{}')>80) then return false;end if;
 if jsonb_typeof(s->'columns') is distinct from 'array' or jsonb_array_length(s->'columns')<>6 then return false;end if;
 keys:=array[]::text[];
 for c in select * from jsonb_array_elements(s->'columns') loop
  if c->>'key' is null or c->>'key'<>all(array['number','code','name','quantity','department','check']) or c->>'key'=any(keys) or jsonb_typeof(c->'visible') is distinct from 'boolean' or jsonb_typeof(c->'label') is distinct from 'string' or length(trim(c->>'label'))=0 or length(c->>'label')>24 then return false;end if;
  if c->>'key'=any(array['name','quantity']) and c->'visible'<>'true'::jsonb then return false;end if;
  keys:=array_append(keys,c->>'key');
 end loop;
 return true;
exception when others then return false;
end $$;
revoke all on function public.validate_pdf_template(jsonb) from public,anon,authenticated;

create or replace function public.save_pdf_template(p_settings jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path=public as $$
declare current_version bigint;new_version bigint;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN' using errcode='42501';end if;
 if not coalesce(validate_pdf_template(p_settings),false) then raise exception 'INVALID_TEMPLATE';end if;
 select version into current_version from pdf_template_current where id for update;
 if p_expected_version is null or p_expected_version<>current_version then raise exception 'CONFLICT';end if;
 insert into pdf_templates(settings,created_by) values(p_settings-'version',auth.uid()) returning version into new_version;
 update pdf_template_current set version=new_version where id;
 insert into audit_log(actor,action,metadata) values(auth.uid(),'pdf_template_saved',jsonb_build_object('version',new_version));
 return current_pdf_template();
end $$;
revoke all on function public.save_pdf_template(jsonb,bigint) from public,anon;
grant execute on function public.save_pdf_template(jsonb,bigint) to authenticated;

create or replace function public.snapshot_pdf_template() returns trigger language plpgsql security definer set search_path=public as $$
begin
 new.pdf_template:=current_pdf_template();
 return new;
end $$;
drop trigger if exists loan_pdf_template on public.loans;
create trigger loan_pdf_template before insert on public.loans for each row execute function public.snapshot_pdf_template();
revoke all on function public.snapshot_pdf_template() from public,anon,authenticated;
create or replace function public.loan_json(p_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('pdfTemplate',l.pdf_template,'id',l.number,'databaseId',l.id,'name',coalesce(l.borrower_name,'익명'),'phone',coalesce(l.borrower_phone,''),
 'department',l.borrower_department,'position',l.borrower_position,'createdAt',l.created_at,'approvalDue',l.approval_due,'approvedAt',l.approved_at,'checkoutAt',l.checked_out_at,'cancelled',l.cancelled_at is not null,'rejected',l.rejected_at is not null,'rejectionReason',l.rejection_reason,'rejectedAt',l.rejected_at,'approvers',l.approver_snapshot,'snapshots',coalesce((select jsonb_object_agg(equipment_id::text,equipment_snapshot) from loan_items where loan_id=l.id),'{}'),'returnNotes',coalesce((select jsonb_agg(jsonb_build_object('notes',notes,'createdAt',created_at,'reversed',reversed_at is not null) order by created_at) from return_events where loan_id=l.id),'[]'),'reason',l.reason,'start',l.start_date,'end',l.end_date,'note',coalesce(l.application_note,l.notes,''),'approved',l.approved_at is not null,
 'out',l.checked_out_at is not null,'revision',l.revision,
 'items',coalesce((select jsonb_object_agg(equipment_id::text,quantity) from loan_items where loan_id=l.id),'{}'),
 'returned',coalesce((select jsonb_object_agg(equipment_id::text,returned_quantity) from loan_items where loan_id=l.id),'{}'))
 from loans l where l.id=p_id ;
$$;
revoke all on function public.loan_json(uuid) from public,anon,authenticated;


commit;
