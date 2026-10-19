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


