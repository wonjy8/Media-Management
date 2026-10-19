begin;
insert into auth.users(id) values('60000000-0000-0000-0000-000000000001');
insert into admins values('60000000-0000-0000-0000-000000000001');
insert into equipment(id,code,name,quantity) values('60000000-0000-0000-0000-000000000002','REVIEW-001','테스트',1);
do $$
declare a jsonb;b jsonb;args jsonb;actor uuid:='60000000-0000-0000-0000-000000000001';bad text;
begin
 args:='{"name":"테스트","phone":"01012345678","reason":"검증","start":"2030-01-01","end":"2030-01-02","items":{"60000000-0000-0000-0000-000000000002":1}}';
 foreach bad in array array['010-1234-5678','01112345678','0101234567','abcdefghijk'] loop
  begin perform equipment_workflow('create',args||jsonb_build_object('phone',bad));raise exception 'invalid phone accepted';exception when others then if sqlerrm not like '%INVALID_PHONE%' then raise;end if;end;
 end loop;
 a:=equipment_workflow('create',args);
 begin perform equipment_workflow('reject',jsonb_build_object('id',a->>'id','revision',1,'reason','사유'),gen_random_uuid());raise exception 'unauthorized rejection';exception when others then if sqlerrm not like '%FORBIDDEN%' then raise;end if;end;
 begin perform equipment_workflow('reject',jsonb_build_object('id',a->>'id','revision',1,'reason','  '),actor);raise exception 'empty reason accepted';exception when others then if sqlerrm not like '%INVALID_REQUEST%' then raise;end if;end;
 a:=equipment_workflow('reject',jsonb_build_object('id',a->>'id','revision',1,'reason','일정 변경'),actor);
 if not (a->>'rejected')::boolean or a->>'rejectionReason'<>'일정 변경' then raise exception 'missing rejection reason';end if;
 if available_quantity('60000000-0000-0000-0000-000000000002','2030-01-01','2030-01-02')<>1 then raise exception 'rejected reservation holds stock';end if;
 b:=equipment_workflow('lookup','{"name":"테스트","phone":"01012345678"}');
 if b->0->>'rejectionReason'<>'일정 변경' then raise exception 'borrower cannot see reason';end if;
 b:=equipment_workflow('create',args||'{"name":"다른이"}');
 begin perform equipment_workflow('update',args||jsonb_build_object('id',a->>'id','revision',2));raise exception 'rejected application edited';exception when others then if sqlerrm not like '%REJECTED_APPLICATION%' then raise;end if;end;
 begin perform equipment_workflow('cancel',jsonb_build_object('id',a->>'id','name','테스트','phone','01012345678','revision',2));raise exception 'rejected application cancelled';exception when others then if sqlerrm not like '%REJECTED_APPLICATION%' then raise;end if;end;
 b:=equipment_workflow('cancel',jsonb_build_object('id',b->>'id','name','다른이','phone','01012345678','revision',1));
 a:=equipment_workflow('create',args);
 a:=equipment_workflow('approve',jsonb_build_object('id',a->>'id','revision',1),actor);
 if not (a->>'approved')::boolean or not (a->>'out')::boolean then raise exception 'approve did not check out';end if;
 begin perform equipment_workflow('reject',jsonb_build_object('id',a->>'id','revision',2,'reason','늦은 반려'),actor);raise exception 'in-use equipment rejected';exception when others then if sqlerrm not like '%CONFLICT%' then raise;end if;end;
 a:=equipment_workflow('return',jsonb_build_object('id',a->>'id','name','테스트','phone','01012345678','revision',2,'items',args->'items'));
 if a->'returned'->>'60000000-0000-0000-0000-000000000002'<>'1' then raise exception 'return failed';end if;
 if not exists(select 1 from audit_log where action='reject' and reason='일정 변경') then raise exception 'missing rejection audit';end if;
end $$;
rollback;
