begin;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000002');
insert into admins values('00000000-0000-0000-0000-000000000002');
insert into groups(id,name) values('30000000-0000-0000-0000-000000000001','음향');
insert into equipment(id,code,name,group_id,quantity) values('30000000-0000-0000-0000-000000000002','SNAP-001','원래 장비명','30000000-0000-0000-0000-000000000001',3);
insert into approvers(id,name,department,position) values('30000000-0000-0000-0000-000000000003','원래승인자','미디어','부장');
do $$
declare a jsonb; b jsonb; c jsonb; n integer;
begin
 a:=equipment_workflow('create','{"name":"테스트","phone":"01000000000","department":"청년부","position":"팀장","reason":"사진/PDF","note":"신청특이사항","start":"2028-01-01","end":"2028-01-02","items":{"30000000-0000-0000-0000-000000000002":2}}');
 b:=equipment_workflow('create','{"name":"다른이","phone":"01000000001","reason":"다른기간","start":"2028-01-03","end":"2028-01-04","items":{"30000000-0000-0000-0000-000000000002":2}}');
 -- Peak daily occupancy is 2, not 4.
 if available_quantity('30000000-0000-0000-0000-000000000002','2028-01-01','2028-01-04')<>1 then raise exception 'incorrect daily peak'; end if;
 c:=equipment_workflow('create','{"name":"세번째","phone":"01000000002","reason":"남은1개","start":"2028-01-01","end":"2028-01-04","items":{"30000000-0000-0000-0000-000000000002":1}}');
 update equipment set name='새 장비명' where code='SNAP-001';update approvers set name='새승인자';
 a:=loan_json((a->>'databaseId')::uuid);
 if a->'snapshots'->'30000000-0000-0000-0000-000000000002'->>'name'<>'원래 장비명' then raise exception 'equipment snapshot changed'; end if;
 if a->'approvers'->0->>'name'<>'원래승인자' then raise exception 'approver snapshot changed'; end if;
 if a->>'department'<>'청년부' then raise exception 'borrower department missing'; end if;
 c:=equipment_workflow('cancel',jsonb_build_object('id',c->>'id','name','세번째','phone','01000000002','revision',1));
 a:=equipment_workflow('update',jsonb_build_object('id',a->>'id','name','테스트','phone','01000000000','revision',1,'department','청년부','position','팀장','reason','변경','note','변경특이사항','start','2028-01-01','end','2028-01-02','items',jsonb_build_object('30000000-0000-0000-0000-000000000002',1)));
 if a->'snapshots'->'30000000-0000-0000-0000-000000000002'->>'name'<>'원래 장비명' then raise exception 'snapshot lost on update'; end if;
 a:=equipment_workflow('checkout',jsonb_build_object('id',a->>'id','revision',2),'00000000-0000-0000-0000-000000000002');
 a:=equipment_workflow('return',jsonb_build_object('id',a->>'id','name','테스트','phone','01000000000','revision',3,'note','반납시기록','items',jsonb_build_object('30000000-0000-0000-0000-000000000002',1)));
 if a->>'note'<>'변경특이사항' then raise exception 'return overwrote application note'; end if;
 select count(*) into n from return_events where loan_id=(a->>'databaseId')::uuid;
 if n<>1 then raise exception 'missing return event'; end if;
 a:=equipment_workflow('undo_return',jsonb_build_object('id',a->>'id','revision',4,'reason','정정'),'00000000-0000-0000-0000-000000000002');
 if exists(select 1 from return_events where loan_id=(a->>'databaseId')::uuid and reversed_at is null) then raise exception 'return history not reversed'; end if;
 if not exists(select 1 from audit_log where action='equipment_update') then raise exception 'catalog audit missing'; end if;
 if has_function_privilege('anon','public.available_quantity(uuid,date,date,uuid)','execute') then raise exception 'unsafe public RPC'; end if;
 raise notice 'PASS: daily peak, snapshots, departments, note isolation, reversal history, equipment audit, RPC protection';
end $$;
-- RLS: administrator can write groups/equipment, ordinary authenticated user cannot.
grant usage on schema public,auth to authenticated;
grant select,insert,update,delete on groups,equipment,approvers to authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into groups(name) values('관리자등록그룹');
update equipment set repair_quantity=1 where code='SNAP-001';
delete from equipment where code='SNAP-001';
do $$ begin if not exists(select 1 from equipment where code='SNAP-001') then raise exception 'equipment history could be deleted'; end if; end $$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',true);
set local role authenticated;
do $$ begin
 begin insert into groups(name) values('비관리자그룹');raise exception 'RLS bypass';exception when insufficient_privilege then null;end;
 if exists(select 1 from equipment where active=false) then raise exception 'inactive catalog visible'; end if;
end $$;
reset role;
rollback;
