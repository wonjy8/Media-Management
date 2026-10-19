-- Run in a new Supabase project. Anonymous clients must never read borrower tables.
create extension if not exists pgcrypto;
create table public.admins (user_id uuid primary key references auth.users(id));
create function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from admins where user_id=auth.uid()) $$;
create table public.groups (id uuid primary key default gen_random_uuid(), name text not null unique);
create table public.equipment (
 id uuid primary key default gen_random_uuid(), code text unique not null, name text not null,
 model text, group_id uuid references public.groups, image_path text, description text,
 quantity integer not null check(quantity>=0), repair_quantity integer not null default 0 check(repair_quantity>=0),
 active boolean not null default true, check(repair_quantity<=quantity)
);
create table public.approvers (id uuid primary key default gen_random_uuid(), name text not null, department text, position text, active boolean not null default true);
create table public.monthly_sequences (month text primary key, value integer not null);
create table public.loans (
 id uuid primary key default gen_random_uuid(), number text unique not null,
 borrower_name text, borrower_phone text, reason text not null, notes text,
 start_date date not null, end_date date not null, created_at timestamptz not null default now(),
 approved_at timestamptz, approved_by uuid references auth.users, checked_out_at timestamptz,
 cancelled_at timestamptz, anonymized_at timestamptz, revision integer not null default 1,
 approval_due date not null, check(end_date>=start_date)
);
create table public.loan_items (
 id uuid primary key default gen_random_uuid(), loan_id uuid not null references public.loans,
 equipment_id uuid not null references public.equipment, quantity integer not null check(quantity>0),
 returned_quantity integer not null default 0, equipment_snapshot jsonb not null,
 check(returned_quantity between 0 and quantity), unique(loan_id,equipment_id)
);
create table public.audit_log (id bigint generated always as identity primary key, loan_id uuid references public.loans, actor uuid, action text not null, reason text, created_at timestamptz not null default now());
-- Only a trusted server / Edge Function may invoke this transaction. It must validate
-- input lengths and rate limits before calling; never expose service_role in the client.
create function public.create_loan(p_name text,p_phone text,p_reason text,p_start date,p_end date,p_notes text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_num text; v_seq integer; v_month text; v_day date; v_due date; v_entry record; v_available integer; v_equipment equipment;
begin
 if length(trim(p_name))=0 or p_phone !~ '^[0-9]{9,15}$' or length(trim(p_reason))=0 or p_end<p_start or jsonb_typeof(p_items)<>'object' or p_items='{}'::jsonb then raise exception 'INVALID_REQUEST'; end if;
 -- Stable lock order prevents deadlocks; inventory check and insert are atomic.
 perform 1 from equipment where id in(select key::uuid from jsonb_each(p_items)) order by id for update;
 for v_entry in select key::uuid as id, value::text::integer as qty from jsonb_each(p_items) loop
 select * into v_equipment from equipment where id=v_entry.id and active;
 if not found or v_entry.qty<=0 then raise exception 'INVALID_EQUIPMENT'; end if;
 select v_equipment.quantity-v_equipment.repair_quantity-coalesce(sum(li.quantity-li.returned_quantity),0)::integer into v_available
 from loan_items li join loans l on l.id=li.loan_id where li.equipment_id=v_entry.id and l.cancelled_at is null
 and ((l.start_date<=p_end and l.end_date>=p_start) or (l.checked_out_at is not null and l.end_date<(now() at time zone 'Asia/Seoul')::date));
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
-- Schedule daily with Supabase Cron. Operational rows remain, identity is erased.
create function public.anonymize_expired_loans() returns void language sql security definer set search_path=public as $$
 update loans set borrower_name=null,borrower_phone=null,anonymized_at=now()
 where created_at<=now()-interval '1 year' and anonymized_at is null;
$$;
revoke all on function public.anonymize_expired_loans() from public,anon,authenticated;
grant execute on function public.anonymize_expired_loans() to service_role;
alter table public.admins enable row level security;
alter table public.groups enable row level security;
alter table public.equipment enable row level security;
alter table public.approvers enable row level security;
alter table public.monthly_sequences enable row level security;
alter table public.loans enable row level security;
alter table public.loan_items enable row level security;
alter table public.audit_log enable row level security;
create policy groups_read on public.groups for select using(true);
create policy equipment_read on public.equipment for select using(active or public.is_admin());
create policy equipment_admin on public.equipment for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy loans_admin on public.loans for select to authenticated using(public.is_admin());
create policy items_admin on public.loan_items for select to authenticated using(public.is_admin());
create policy audit_admin on public.audit_log for select to authenticated using(public.is_admin());
create policy approvers_admin on public.approvers for all to authenticated using(public.is_admin()) with check(public.is_admin());
