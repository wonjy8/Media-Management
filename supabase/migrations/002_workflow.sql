-- Apply after 001_initial.sql. All mutation RPCs are service_role only.
create table public.request_limits (
 key text primary key, window_start timestamptz not null default now(), hits integer not null default 0
);
alter table public.request_limits enable row level security;
create function public.consume_request_limit(p_ip text,p_target text,p_action text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
declare k text; n integer; ok boolean:=true;
begin
 -- Separate IP and target buckets: allow normal repeated use on a church Wi-Fi.
 foreach k in array array['ip:'||md5(p_ip),'target:'||md5(p_target)] loop
 insert into request_limits(key,hits) values(k,1) on conflict(key) do update
 set hits=case when request_limits.window_start<now()-interval '15 minutes' then 1 else request_limits.hits+1 end,
 window_start=case when request_limits.window_start<now()-interval '15 minutes' then now() else request_limits.window_start end
 returning hits into n;
 if n>(case when k like 'ip:%' then 300 else 40 end) then ok:=false; end if;
 end loop;
 delete from request_limits where window_start<now()-interval '1 day';
 return ok;
end $$;
revoke all on function public.consume_request_limit(text,text,text) from public,anon,authenticated;
grant execute on function public.consume_request_limit(text,text,text) to service_role;

create function public.loan_json(p_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',l.number,'databaseId',l.id,'name',coalesce(l.borrower_name,'익명'),'phone',coalesce(l.borrower_phone,''),
 'reason',l.reason,'start',l.start_date,'end',l.end_date,'note',coalesce(l.notes,''),'approved',l.approved_at is not null,
 'out',l.checked_out_at is not null,'revision',l.revision,
 'items',coalesce((select jsonb_object_agg(equipment_id::text,quantity) from loan_items where loan_id=l.id),'{}'),
 'returned',coalesce((select jsonb_object_agg(equipment_id::text,returned_quantity) from loan_items where loan_id=l.id),'{}'))
 from loans l where l.id=p_id and l.cancelled_at is null;
$$;
revoke all on function public.loan_json(uuid) from public,anon,authenticated;

create function public.equipment_workflow(p_action text,p_args jsonb,p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l loans; e equipment; entry record; created jsonb; available integer; result jsonb; v_start date; v_end date; v_qty integer; v_revision integer;
begin
 if p_action in ('admin_list','approve','checkout','undo_return','stock') and not exists(select 1 from admins where user_id=p_actor) then raise exception 'FORBIDDEN'; end if;
 if p_action='catalog' then
 v_start:=(p_args->>'start')::date; v_end:=(p_args->>'end')::date;
 if v_start is null or v_end is null or v_end<v_start then raise exception 'INVALID_REQUEST'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',eq.id,'code',eq.code,'name',eq.name,'model',coalesce(eq.model,''),
 'group',coalesce(g.name,'기타'),'qty',eq.quantity,'image',eq.image_path,'available',greatest(0,eq.quantity-eq.repair_quantity-
 coalesce((select sum(li.quantity-li.returned_quantity) from loan_items li join loans x on x.id=li.loan_id where li.equipment_id=eq.id and x.cancelled_at is null and
 ((x.start_date<=v_end and x.end_date>=v_start) or (x.checked_out_at is not null and x.end_date<(now() at time zone 'Asia/Seoul')::date))),0))) order by eq.code),'[]') into result
 from equipment eq left join groups g on g.id=eq.group_id where eq.active;
 return result;
 elsif p_action='admin_list' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans where cancelled_at is null);
 elsif p_action='lookup' then
 return (select coalesce(jsonb_agg(loan_json(id) order by created_at desc),'[]') from loans where borrower_name=trim(p_args->>'name') and borrower_phone=p_args->>'phone' and cancelled_at is null and anonymized_at is null);
 elsif p_action='create' then
 if length(p_args->>'reason')>500 or length(coalesce(p_args->>'note',''))>2000 then raise exception 'INVALID_REQUEST'; end if;
 created:=create_loan(p_args->>'name',p_args->>'phone',p_args->>'reason',(p_args->>'start')::date,(p_args->>'end')::date,p_args->>'note',p_args->'items');
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
 if p_actor is null and (l.anonymized_at is not null or l.borrower_name<>trim(p_args->>'name') or l.borrower_phone<>p_args->>'phone' or p_args->>'name' is null or p_args->>'phone' is null) then raise exception 'NOT_FOUND'; end if;
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
 select e.quantity-e.repair_quantity-coalesce(sum(li.quantity-li.returned_quantity),0)::integer into available
 from loan_items li join loans x on x.id=li.loan_id where li.equipment_id=e.id and x.id<>l.id and x.cancelled_at is null
 and ((x.start_date<=v_end and x.end_date>=v_start) or (x.checked_out_at is not null and x.end_date<(now() at time zone 'Asia/Seoul')::date));
 if available<entry.qty then raise exception 'INSUFFICIENT_STOCK'; end if;
 end loop;
 delete from loan_items where loan_id=l.id;
 insert into loan_items(loan_id,equipment_id,quantity,equipment_snapshot)
 select l.id,eq.id,j.value::text::integer,jsonb_build_object('name',eq.name,'code',eq.code,'model',eq.model) from jsonb_each(p_args->'items') j join equipment eq on eq.id=j.key::uuid;
 update loans set reason=p_args->>'reason',notes=p_args->>'note',start_date=v_start,end_date=v_end,approved_at=null,approved_by=null,revision=revision+1 where id=l.id;
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
 for entry in select key::uuid as id,value::text::integer as qty from jsonb_each(p_args->'items') loop
 update loan_items set returned_quantity=returned_quantity+entry.qty where loan_id=l.id and equipment_id=entry.id and entry.qty>0 and returned_quantity+entry.qty<=quantity;
 if not found then raise exception 'INVALID_RETURN'; end if;
 end loop;
 update loans set notes=concat_ws(E'\n',notes,nullif('반납: '||left(coalesce(p_args->>'note',''),2000),'반납: ')),revision=revision+1 where id=l.id;
 elsif p_action='undo_return' then
 if length(trim(coalesce(p_args->>'reason','')))=0 then raise exception 'INVALID_REQUEST'; end if;
 update loan_items set returned_quantity=0 where loan_id=l.id;
 update loans set revision=revision+1 where id=l.id;
 else raise exception 'INVALID_REQUEST'; end if;
 insert into audit_log(loan_id,actor,action,reason) values(l.id,p_actor,p_action,left(p_args->>'reason',500));
 return coalesce(loan_json(l.id),'{}');
end $$;
revoke all on function public.equipment_workflow(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.equipment_workflow(text,jsonb,uuid) to service_role;
