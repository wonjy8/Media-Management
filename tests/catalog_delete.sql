begin;
insert into auth.users(id) values('50000000-0000-0000-0000-000000000001');
insert into admins values('50000000-0000-0000-0000-000000000001');
insert into groups(id,name) values('50000000-0000-0000-0000-000000000002','삭제 그룹');
insert into equipment(id,code,name,quantity,group_id) values
 ('50000000-0000-0000-0000-000000000003','DELETE-NEW','새 장비',2,'50000000-0000-0000-0000-000000000002'),
 ('50000000-0000-0000-0000-000000000004','DELETE-HISTORY','이력 장비',2,'50000000-0000-0000-0000-000000000002');
select equipment_workflow('create','{"name":"테스트","phone":"01000000000","reason":"보존","start":"2029-01-01","end":"2029-01-02","items":{"50000000-0000-0000-0000-000000000004":1}}');
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000099',true);
set local role authenticated;
do $$begin
 begin perform admin_delete_catalog('group','50000000-0000-0000-0000-000000000002');raise exception 'non-admin deleted group';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$begin
 if admin_delete_catalog('group','50000000-0000-0000-0000-000000000002')<>'deleted' then raise exception 'group failed';end if;
 if admin_delete_catalog('equipment','50000000-0000-0000-0000-000000000003')<>'deleted' then raise exception 'delete failed';end if;
 if admin_delete_catalog('equipment','50000000-0000-0000-0000-000000000004')<>'archived' then raise exception 'archive failed';end if;
end $$;
reset role;
do $$begin
 if exists(select 1 from equipment where code='DELETE-NEW') then raise exception 'not deleted';end if;
 if not exists(select 1 from equipment where code='DELETE-HISTORY' and active=false and group_id is null) then raise exception 'history lost';end if;
 if not exists(select 1 from loan_items where equipment_id='50000000-0000-0000-0000-000000000004') then raise exception 'loan lost';end if;
 if has_function_privilege('anon','admin_delete_catalog(text,uuid)','EXECUTE') then raise exception 'anon permission';end if;
end $$;
rollback;
