begin;
insert into equipment(id,code,name,quantity) values('70000000-0000-0000-0000-000000000001','LEGACY-APPROVED','기존 승인 장비',1);
select equipment_workflow('create','{"name":"테스트","phone":"01012345678","reason":"기존 승인 검증","start":"2031-01-01","end":"2031-01-02","items":{"70000000-0000-0000-0000-000000000001":1}}');
update loans set approved_at=now() where reason='기존 승인 검증';
\ir ../supabase/migrations/006_application_review.sql
do $$begin
 if not exists(select 1 from loans where reason='기존 승인 검증' and checked_out_at=approved_at and revision=2) then raise exception 'legacy approval stranded';end if;
end $$;
\ir ../supabase/migrations/006_application_review.sql
do $$begin
 if not exists(select 1 from loans where reason='기존 승인 검증' and revision=2) then raise exception 'migration is not idempotent';end if;
 if (select count(*) from audit_log where action='approval_checkout_migration')<>1 then raise exception 'missing/duplicate migration audit';end if;
end $$;
rollback;
