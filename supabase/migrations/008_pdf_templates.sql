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

